//
//  ScrollingCaptureManager.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import Foundation

protocol ScrollingCaptureDelegate: AnyObject {
    func showScrollingCaptureShelf()
    func hideScrollingCaptureShelf()
    func showScrollingCaptureControls()
    func hideScrollingCaptureControls()
    func closeOverlay()
    func showPreviewForImage(_ image: NSImage)
    func setSelectionOverlayVisible(_ visible: Bool)
    func setPanelsIgnoreMouseEvents(_ ignore: Bool)
    func captureScrollFrame()
    func didUpdateStitchedPreview(_ image: CGImage, totalHeight: Int)
}

final class ScrollingCaptureManager {
    weak var delegate: ScrollingCaptureDelegate?

    private(set) var isScrollingCaptureActive = false
    private var stitchedImage: CGImage?
    private var lastFrame: CGImage?
    private var lastHash: UInt64 = 0
    private var targetWidth: Int = 0
    private var autoScrollTimer: Timer?
    private var duplicateCount: Int = 0
    /// Fingerprints of each new-content strip that was stitched, used to reject duplicates.
    private var stripFingerprints: [[Double]] = []

    // Auto-scroll is disabled; capture follows user scrolling.
    private let autoScrollEnabled = false
    private let scrollPixelsPerStep: Int32 = -280
    private let scrollInterval: TimeInterval = 0.34
    private let renderDelay: TimeInterval = 0.18
    private let maxDuplicatesBeforeStop: Int = 8
    private let duplicateHashThreshold: Int = 3

    // MARK: - Public API

    func startScrollingCapture() {
        guard !isScrollingCaptureActive else { return }
        isScrollingCaptureActive = true
        stitchedImage = nil
        lastFrame = nil
        lastHash = 0
        targetWidth = 0
        duplicateCount = 0
        stripFingerprints = []
        delegate?.hideScrollingCaptureShelf()
        delegate?.setSelectionOverlayVisible(false)
        delegate?.setPanelsIgnoreMouseEvents(true)
        delegate?.showScrollingCaptureControls()

        // Capture first frame immediately
        delegate?.captureScrollFrame()
        if autoScrollEnabled {
            startAutoScroll()
        }
    }

    /// Called when user scrolls manually — capture a frame
    func userDidScroll() {
        guard isScrollingCaptureActive else { return }
        delegate?.captureScrollFrame()
    }

    func endScrollingCapture(shouldCapture: Bool) {
        stopAutoScroll()
        isScrollingCaptureActive = false
        delegate?.setSelectionOverlayVisible(true)
        delegate?.setPanelsIgnoreMouseEvents(false)
        delegate?.hideScrollingCaptureControls()
        if shouldCapture {
            deliverResult()
        } else {
            stitchedImage = nil
            lastFrame = nil
            targetWidth = 0
            stripFingerprints = []
        }
    }

    func appendScrollingFrame(_ frame: CGImage) {
        guard isScrollingCaptureActive else { return }

        let tw = targetWidth > 0 ? targetWidth : frame.width
        guard let scaled = scaleImage(frame, toWidth: tw) else { return }
        if targetWidth == 0 { targetWidth = tw }

        guard let previous = lastFrame else {
            // First frame
            lastFrame = scaled
            stitchedImage = scaled
            lastHash = averageHash(scaled) ?? 0
            delegate?.didUpdateStitchedPreview(scaled, totalHeight: scaled.height)
            return
        }

        // Detect overlap using multi-band matching, then fallback row-signature matching.
        guard let shift = detectShift(previous: previous, next: scaled)
            ?? detectShiftByRowSignature(previous: previous, next: scaled) else {
            return
        }

        // Check for true near-duplicate only after we have a measured shift.
        if let hash = averageHash(scaled),
           hammingDistance(hash, lastHash) < duplicateHashThreshold,
           shift < 12 {
            duplicateCount += 1
            if duplicateCount >= maxDuplicatesBeforeStop {
                // Likely reached page bottom; stop auto-scroll and wait for user Done/Cancel.
                stopAutoScroll()
            }
            return
        } else {
            duplicateCount = 0
        }

        let overlap = scaled.height - shift
        guard overlap >= 10, shift >= 20 else { return }

        let base = stitchedImage ?? previous

        // Fingerprint the new content strip and check against all previously stitched strips
        let newContentHeight = scaled.height - overlap
        guard newContentHeight > 0 else { return }
        if let newStrip = scaled.cropping(to: CGRect(x: 0, y: overlap, width: scaled.width, height: newContentHeight)) {
            let fp = stripFingerprint(newStrip)
            for existing in stripFingerprints {
                if fingerprintDistance(fp, existing) < 4.0 {
                    // This strip's content already exists in the stitched image — skip
                    return
                }
            }
            stripFingerprints.append(fp)
        }

        if let result = stitchFrames(base: base, next: scaled, overlap: overlap) {
            stitchedImage = result
            lastFrame = scaled
            lastHash = averageHash(scaled) ?? lastHash
            delegate?.didUpdateStitchedPreview(result, totalHeight: result.height)
        }
    }

    // MARK: - Auto-Scroll

    private func startAutoScroll() {
        stopAutoScroll()
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: scrollInterval, repeats: true) { [weak self] _ in
            self?.performScrollStep()
        }
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func performScrollStep() {
        guard isScrollingCaptureActive else {
            stopAutoScroll()
            return
        }

        // Inject a scroll wheel event to scroll the page down
        injectScrollEvent(deltaY: scrollPixelsPerStep)

        // Wait for the page to render, then capture
        DispatchQueue.main.asyncAfter(deadline: .now() + renderDelay) { [weak self] in
            guard let self, self.isScrollingCaptureActive else { return }
            self.delegate?.captureScrollFrame()
        }
    }

    private func injectScrollEvent(deltaY: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Shift Detection (multi-band template matching)

    private func detectShift(previous: CGImage, next: CGImage) -> Int? {
        let dsWidth = 300
        guard let prevSmall = resizeImage(previous, targetWidth: dsWidth),
              let nextSmall = resizeImage(next, targetWidth: dsWidth),
              let prevData = prevSmall.dataProvider?.data,
              let nextData = nextSmall.dataProvider?.data,
              let prevBytes = CFDataGetBytePtr(prevData),
              let nextBytes = CFDataGetBytePtr(nextData) else {
            return nil
        }

        let scale = CGFloat(previous.height) / CGFloat(prevSmall.height)
        let w = min(prevSmall.width, nextSmall.width)
        let pH = prevSmall.height
        let nH = nextSmall.height
        let pBPR = prevSmall.bytesPerRow
        let nBPR = nextSmall.bytesPerRow
        let bandH = max(6, pH / 20)

        let bandPositions = [pH * 40 / 100, pH * 55 / 100, pH * 70 / 100, pH * 82 / 100]
        var shiftVotes: [Int] = []

        for bandY in bandPositions {
            guard bandY + bandH <= pH else { continue }

            let maxSearchY = min(nH - bandH, nH * 90 / 100)
            guard maxSearchY > 0 else { continue }

            var bestY = -1
            var bestScore = Double.greatestFiniteMagnitude

            // Coarse search (step 3)
            var y = 0
            while y < maxSearchY {
                let score = bandScore(
                    prevBytes: prevBytes, nextBytes: nextBytes,
                    pBPR: pBPR, nBPR: nBPR, w: w,
                    bandY: bandY, searchY: y, bandH: bandH
                )
                if score < bestScore {
                    bestScore = score
                    bestY = y
                }
                y += 3
            }

            // Fine search ±3
            if bestY >= 0 {
                let fStart = max(0, bestY - 3)
                let fEnd = min(maxSearchY - 1, bestY + 3)
                for y in fStart...fEnd {
                    let score = bandScore(
                        prevBytes: prevBytes, nextBytes: nextBytes,
                        pBPR: pBPR, nBPR: nBPR, w: w,
                        bandY: bandY, searchY: y, bandH: bandH
                    )
                    if score < bestScore {
                        bestScore = score
                        bestY = y
                    }
                }
            }

            if bestScore < 8.0, bestY >= 0 {
                let s = bandY - bestY
                if s > 0 { shiftVotes.append(s) }
            }
        }

        guard shiftVotes.count >= 2 else { return nil }

        shiftVotes.sort()
        let median = shiftVotes[shiftVotes.count / 2]
        let agreeing = shiftVotes.filter { abs($0 - median) <= 2 }
        guard agreeing.count >= 2 else { return nil }

        let avgShift = agreeing.reduce(0, +) / agreeing.count
        let fullShift = Int((CGFloat(avgShift) * scale).rounded())

        let minShift = max(10, Int(CGFloat(previous.height) * 0.03))
        let maxShift = Int(CGFloat(previous.height) * 0.90)
        guard fullShift >= minShift, fullShift <= maxShift else { return nil }

        return fullShift
    }

    // Fallback matcher for pages where mixed moving content (e.g. video + feed) confuses band matching.
    private func detectShiftByRowSignature(previous: CGImage, next: CGImage) -> Int? {
        let dsWidth = 220
        guard let prevSmall = resizeImage(previous, targetWidth: dsWidth),
              let nextSmall = resizeImage(next, targetWidth: dsWidth),
              let prevData = prevSmall.dataProvider?.data,
              let nextData = nextSmall.dataProvider?.data,
              let prevBytes = CFDataGetBytePtr(prevData),
              let nextBytes = CFDataGetBytePtr(nextData) else {
            return nil
        }

        let w = min(prevSmall.width, nextSmall.width)
        let h = min(prevSmall.height, nextSmall.height)
        guard w >= 20, h >= 40 else { return nil }

        let pBPR = prevSmall.bytesPerRow
        let nBPR = nextSmall.bytesPerRow
        let xStart = w / 5
        let xEnd = w * 4 / 5
        guard xEnd > xStart else { return nil }

        var prevRows = Array(repeating: Double.zero, count: h)
        var nextRows = Array(repeating: Double.zero, count: h)

        for y in 0..<h {
            let pRow = y * pBPR
            let nRow = y * nBPR
            var pSum = 0.0
            var nSum = 0.0
            var count = 0.0

            for x in stride(from: xStart, to: xEnd, by: 2) {
                let pi = pRow + x * 4
                let ni = nRow + x * 4
                pSum += 0.299 * Double(prevBytes[pi]) + 0.587 * Double(prevBytes[pi + 1]) + 0.114 * Double(prevBytes[pi + 2])
                nSum += 0.299 * Double(nextBytes[ni]) + 0.587 * Double(nextBytes[ni + 1]) + 0.114 * Double(nextBytes[ni + 2])
                count += 1
            }

            if count > 0 {
                prevRows[y] = pSum / count
                nextRows[y] = nSum / count
            }
        }

        let minShiftSmall = max(6, h / 40)
        let maxShiftSmall = min(h - 8, h * 9 / 10)
        guard maxShiftSmall > minShiftSmall else { return nil }

        var bestShift = -1
        var bestScore = Double.greatestFiniteMagnitude

        for shift in minShiftSmall...maxShiftSmall {
            var total = 0.0
            var samples = 0.0
            let upper = h - shift
            if upper <= 0 { continue }

            for y in stride(from: 0, to: upper, by: 2) {
                total += abs(prevRows[y + shift] - nextRows[y])
                samples += 1
            }

            guard samples > 0 else { continue }
            let score = total / samples
            if score < bestScore {
                bestScore = score
                bestShift = shift
            }
        }

        guard bestShift > 0 else { return nil }

        let scale = CGFloat(previous.height) / CGFloat(prevSmall.height)
        let fullShift = Int((CGFloat(bestShift) * scale).rounded())
        let minShift = max(10, Int(CGFloat(previous.height) * 0.03))
        let maxShift = Int(CGFloat(previous.height) * 0.90)
        guard fullShift >= minShift, fullShift <= maxShift else { return nil }
        return fullShift
    }

    private func bandScore(
        prevBytes: UnsafePointer<UInt8>, nextBytes: UnsafePointer<UInt8>,
        pBPR: Int, nBPR: Int, w: Int,
        bandY: Int, searchY: Int, bandH: Int
    ) -> Double {
        var totalDiff: Double = 0
        var count: Double = 0
        let rowStep = max(1, bandH / 5)
        let colStep = max(1, w / 40)

        var dy = 0
        while dy < bandH {
            let pRow = (bandY + dy) * pBPR
            let nRow = (searchY + dy) * nBPR
            var x = 0
            while x < w {
                let p = pRow + x * 4
                let n = nRow + x * 4
                totalDiff += abs(Double(prevBytes[p]) - Double(nextBytes[n]))
                totalDiff += abs(Double(prevBytes[p + 1]) - Double(nextBytes[n + 1]))
                totalDiff += abs(Double(prevBytes[p + 2]) - Double(nextBytes[n + 2]))
                count += 3
                x += colStep
            }
            dy += rowStep
        }

        guard count > 0 else { return .greatestFiniteMagnitude }
        return totalDiff / count
    }

    // MARK: - Strip Fingerprinting (for duplicate detection)

    /// Creates a compact fingerprint of an image strip by dividing it into a grid
    /// and computing the average luminance of each cell.
    private func stripFingerprint(_ image: CGImage) -> [Double] {
        let gridW = 16
        let gridH = 8
        guard let small = resizeImage(image, targetWidth: 160),
              let data = small.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return []
        }
        let w = small.width
        let h = small.height
        guard w > 0, h > 0 else { return [] }
        let bpr = small.bytesPerRow
        let cellW = max(1, w / gridW)
        let cellH = max(1, h / gridH)
        var result = [Double]()
        result.reserveCapacity(gridW * gridH)

        for gy in 0..<gridH {
            let startY = gy * cellH
            guard startY < h else {
                // Image too short for remaining grid rows — pad with 0
                for _ in 0..<gridW { result.append(0) }
                continue
            }
            let endY = min(startY + cellH, h)
            for gx in 0..<gridW {
                let startX = gx * cellW
                guard startX < w else {
                    result.append(0)
                    continue
                }
                let endX = min(startX + cellW, w)
                var sum = 0.0
                var count = 0.0
                for y in startY..<endY {
                    let row = y * bpr
                    for x in startX..<endX {
                        let i = row + x * 4
                        sum += 0.299 * Double(bytes[i]) + 0.587 * Double(bytes[i + 1]) + 0.114 * Double(bytes[i + 2])
                        count += 1
                    }
                }
                result.append(count > 0 ? sum / count : 0)
            }
        }
        return result
    }

    /// Mean absolute difference between two fingerprints.
    private func fingerprintDistance(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .greatestFiniteMagnitude }
        var total = 0.0
        for i in 0..<a.count {
            total += abs(a[i] - b[i])
        }
        return total / Double(a.count)
    }

    // MARK: - Stitching

    private func stitchFrames(base: CGImage, next: CGImage, overlap: Int) -> CGImage? {
        let newContentHeight = next.height - overlap
        guard newContentHeight > 0 else { return base }

        let totalHeight = base.height + newContentHeight
        let width = max(base.width, next.width)

        guard let context = createRGBContext(width: width, height: totalHeight) else { return nil }

        context.draw(base, in: CGRect(x: 0, y: newContentHeight, width: base.width, height: base.height))

        if let newSlice = next.cropping(to: CGRect(x: 0, y: overlap, width: next.width, height: newContentHeight)) {
            context.draw(newSlice, in: CGRect(x: 0, y: 0, width: next.width, height: newContentHeight))
        }

        return context.makeImage()
    }

    // MARK: - Result Delivery

    private func deliverResult() {
        let finalImage = stitchedImage ?? lastFrame
        stitchedImage = nil
        lastFrame = nil
        targetWidth = 0

        guard let finalImage else {
            delegate?.closeOverlay()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let nsImage = NSImage(
                cgImage: finalImage,
                size: NSSize(width: finalImage.width, height: finalImage.height)
            )
            self.delegate?.showPreviewForImage(nsImage)
        }
    }

    // MARK: - Image Utilities

    private func createRGBContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func scaleImage(_ image: CGImage, toWidth width: Int) -> CGImage? {
        guard image.width != width else { return image }
        let scale = CGFloat(width) / CGFloat(image.width)
        let h = Int((CGFloat(image.height) * scale).rounded())
        guard let ctx = createRGBContext(width: width, height: h) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: h))
        return ctx.makeImage()
    }

    private func resizeImage(_ image: CGImage, targetWidth tw: Int) -> CGImage? {
        let scale = CGFloat(tw) / CGFloat(image.width)
        let th = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let ctx = createRGBContext(width: tw, height: th) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage()
    }

    private func averageHash(_ image: CGImage) -> UInt64? {
        let size = 8
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: size * size)

        var total = 0
        for i in 0..<(size * size) { total += Int(px[i]) }
        let avg = total / (size * size)

        var hash: UInt64 = 0
        for i in 0..<(size * size) {
            if Int(px[i]) >= avg { hash |= (1 << UInt64(i)) }
        }
        return hash
    }

    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        Int((a ^ b).nonzeroBitCount)
    }
}
