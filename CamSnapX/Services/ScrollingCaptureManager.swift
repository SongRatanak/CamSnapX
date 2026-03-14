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

    // Auto-scroll tuning
    private let scrollPixelsPerStep: Int32 = -180   // negative = scroll down
    private let scrollInterval: TimeInterval = 0.45  // time between scroll+capture
    private let renderDelay: TimeInterval = 0.15      // wait for render after scroll
    private let maxDuplicatesBeforeStop: Int = 3      // stop after N identical frames
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
        delegate?.hideScrollingCaptureShelf()
        delegate?.setSelectionOverlayVisible(false)
        delegate?.setPanelsIgnoreMouseEvents(true)
        delegate?.showScrollingCaptureControls()

        // Capture first frame immediately, then start auto-scroll loop
        delegate?.captureScrollFrame()
        startAutoScroll()
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
        }
    }

    func appendScrollingFrame(_ frame: CGImage) {
        guard isScrollingCaptureActive else { return }

        let tw = targetWidth > 0 ? targetWidth : frame.width
        guard let scaled = scaleImage(frame, toWidth: tw) else { return }
        if targetWidth == 0 { targetWidth = tw }

        // Check for duplicate frame (page reached bottom)
        if let hash = averageHash(scaled) {
            if hammingDistance(hash, lastHash) < duplicateHashThreshold {
                duplicateCount += 1
                if duplicateCount >= maxDuplicatesBeforeStop {
                    // Page bottom reached — auto-finish
                    endScrollingCapture(shouldCapture: true)
                }
                return
            }
            duplicateCount = 0
        }

        guard let previous = lastFrame else {
            // First frame
            lastFrame = scaled
            stitchedImage = scaled
            lastHash = averageHash(scaled) ?? 0
            return
        }

        // Detect overlap using multi-band matching
        guard let shift = detectShift(previous: previous, next: scaled) else { return }

        let overlap = scaled.height - shift
        guard overlap >= 10, shift >= 20 else { return }

        let base = stitchedImage ?? previous

        if isDuplicateTail(stitched: base, next: scaled, overlap: overlap) { return }

        if let result = stitchFrames(base: base, next: scaled, overlap: overlap) {
            stitchedImage = result
            lastFrame = scaled
            lastHash = averageHash(scaled) ?? lastHash
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

    // MARK: - Duplicate Tail Detection

    private func isDuplicateTail(stitched: CGImage, next: CGImage, overlap: Int) -> Bool {
        let newHeight = next.height - overlap
        guard newHeight > 0, stitched.height >= newHeight else { return false }

        let compareH = min(newHeight, 400)
        let compareW = min(stitched.width, next.width)
        guard compareH >= 20, compareW >= 20 else { return false }

        let tailRect = CGRect(x: 0, y: stitched.height - compareH, width: compareW, height: compareH)
        let newRect = CGRect(x: 0, y: overlap, width: compareW, height: compareH)

        guard let tailCrop = stitched.cropping(to: tailRect),
              let newCrop = next.cropping(to: newRect) else { return false }

        let dsW = min(180, compareW)
        guard let tailSmall = resizeImage(tailCrop, targetWidth: dsW),
              let newSmall = resizeImage(newCrop, targetWidth: dsW),
              let tailData = tailSmall.dataProvider?.data,
              let newData = newSmall.dataProvider?.data,
              let tailBytes = CFDataGetBytePtr(tailData),
              let newBytes = CFDataGetBytePtr(newData) else { return false }

        let w = min(tailSmall.width, newSmall.width)
        let h = min(tailSmall.height, newSmall.height)
        guard w > 0, h > 0 else { return false }

        var totalDiff: Double = 0
        var count: Double = 0
        for y in 0..<h {
            let tRow = y * tailSmall.bytesPerRow
            let nRow = y * newSmall.bytesPerRow
            for x in stride(from: 0, to: w, by: max(1, w / 40)) {
                let t = tRow + x * 4
                let n = nRow + x * 4
                totalDiff += abs(Double(tailBytes[t]) - Double(newBytes[n]))
                totalDiff += abs(Double(tailBytes[t + 1]) - Double(newBytes[n + 1]))
                totalDiff += abs(Double(tailBytes[t + 2]) - Double(newBytes[n + 2]))
                count += 3
            }
        }

        guard count > 0 else { return false }
        return (totalDiff / count) < 12.0
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
