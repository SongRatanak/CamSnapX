//
//  ScrollingCaptureManager.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import Foundation
import Vision

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
    private var lastFrame: CGImage?
    private var lastHash: UInt64 = 0
    private var targetWidth: Int = 0
    private var duplicateCount: Int = 0
    /// Original captured strips (drawn once at delivery for max quality).
    private var capturedStrips: [(image: CGImage, height: Int)] = []
    private var totalStitchedHeight: Int = 0

    private let maxDuplicatesBeforeStop: Int = 8
    private let duplicateHashThreshold: Int = 3

    // MARK: - Public API

    func startScrollingCapture() {
        guard !isScrollingCaptureActive else { return }
        isScrollingCaptureActive = true
        lastFrame = nil
        lastHash = 0
        targetWidth = 0
        duplicateCount = 0
        capturedStrips = []
        totalStitchedHeight = 0
        delegate?.hideScrollingCaptureShelf()
        delegate?.setSelectionOverlayVisible(false)
        delegate?.setPanelsIgnoreMouseEvents(true)
        delegate?.showScrollingCaptureControls()

        // Capture first frame immediately
        delegate?.captureScrollFrame()
    }

    /// Called when user scrolls manually — capture a frame
    func userDidScroll() {
        guard isScrollingCaptureActive else { return }
        delegate?.captureScrollFrame()
    }

    func endScrollingCapture(shouldCapture: Bool) {
        isScrollingCaptureActive = false
        delegate?.setSelectionOverlayVisible(true)
        delegate?.setPanelsIgnoreMouseEvents(false)
        delegate?.hideScrollingCaptureControls()
        if shouldCapture {
            deliverResult()
        } else {
            lastFrame = nil
            targetWidth = 0
            capturedStrips = []
            totalStitchedHeight = 0
        }
    }

    func appendScrollingFrame(_ frame: CGImage) {
        guard isScrollingCaptureActive else { return }

        let tw = targetWidth > 0 ? targetWidth : frame.width
        guard let scaled = scaleImage(frame, toWidth: tw) else { return }
        if targetWidth == 0 { targetWidth = tw }

        guard let previous = lastFrame else {
            // First frame — store the full frame as the first strip
            lastFrame = scaled
            lastHash = averageHash(scaled) ?? 0
            capturedStrips.append((image: scaled, height: scaled.height))
            totalStitchedHeight = scaled.height
            delegate?.didUpdateStitchedPreview(scaled, totalHeight: scaled.height)
            return
        }

        // Primary: Apple Vision framework for precise alignment
        // Fallback: multi-band template matching, then row-signature matching
        guard let shift = detectShiftVision(previous: previous, next: scaled)
            ?? detectShiftBand(previous: previous, next: scaled)
            ?? detectShiftByRowSignature(previous: previous, next: scaled) else {
            return
        }

        // Check for near-duplicate (page bottom reached)
        if let hash = averageHash(scaled),
           hammingDistance(hash, lastHash) < duplicateHashThreshold,
           shift < 12 {
            duplicateCount += 1
            return
        } else {
            duplicateCount = 0
        }

        let overlap = scaled.height - shift
        guard overlap >= 10, shift >= 20 else { return }

        // Extract the new content strip
        let newContentHeight = scaled.height - overlap
        guard newContentHeight > 0 else { return }
        guard let newStrip = scaled.cropping(to: CGRect(x: 0, y: overlap, width: scaled.width, height: newContentHeight)) else { return }

        // Store the strip (drawn once at delivery for maximum quality)
        capturedStrips.append((image: newStrip, height: newContentHeight))
        totalStitchedHeight += newContentHeight
        lastFrame = scaled
        lastHash = averageHash(scaled) ?? lastHash

        // Generate a quick preview
        if let preview = buildPreviewImage() {
            delegate?.didUpdateStitchedPreview(preview, totalHeight: totalStitchedHeight)
        }
    }

    // MARK: - Shift Detection (Apple Vision Framework)

    /// Uses VNTranslationalImageRegistrationRequest to find the precise vertical
    /// pixel displacement between two frames. This is Apple's built-in image
    /// alignment API — much more reliable than custom template matching.
    private func detectShiftVision(previous: CGImage, next: CGImage) -> Int? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: next)

        let handler = VNImageRequestHandler(cgImage: previous)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let result = request.results?.first as? VNImageTranslationAlignmentObservation else {
            return nil
        }

        // alignmentTransform.ty gives the vertical displacement in pixels.
        // Positive ty means the next image is shifted DOWN relative to previous,
        // which corresponds to scrolling down (content moved up).
        let ty = result.alignmentTransform.ty

        // We expect the content to have scrolled up, so ty should be negative
        // (next image content is higher than previous). The shift is the absolute value.
        // But Vision may report in either direction depending on coordinate system,
        // so we take the absolute value and validate the range.
        let rawShift = Int(abs(ty).rounded())

        let minShift = max(10, Int(CGFloat(previous.height) * 0.03))
        let maxShift = Int(CGFloat(previous.height) * 0.90)
        guard rawShift >= minShift, rawShift <= maxShift else { return nil }

        return rawShift
    }

    // MARK: - Shift Detection (multi-band template matching fallback)

    private func detectShiftBand(previous: CGImage, next: CGImage) -> Int? {
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

    // Fallback matcher for pages where mixed moving content confuses band matching.
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

    // MARK: - Stitching (one-shot at delivery)

    /// Combines all stored strips into a single full-quality image. Each strip is drawn
    /// exactly once, so there is no quality loss from repeated re-drawing.
    private func stitchAllStrips() -> CGImage? {
        guard !capturedStrips.isEmpty else { return nil }
        if capturedStrips.count == 1 { return capturedStrips[0].image }

        let width = targetWidth
        guard let context = createRGBContext(width: width, height: totalStitchedHeight) else { return nil }

        // Draw strips from top to bottom. In CGContext, y=0 is bottom,
        // so the first strip goes at the highest y position.
        var yOffset = totalStitchedHeight
        for strip in capturedStrips {
            yOffset -= strip.height
            context.draw(strip.image, in: CGRect(x: 0, y: yOffset, width: strip.image.width, height: strip.height))
        }

        return context.makeImage()
    }

    /// Builds a low-res preview for the live preview panel.
    private func buildPreviewImage() -> CGImage? {
        guard !capturedStrips.isEmpty else { return nil }
        if capturedStrips.count == 1 { return capturedStrips[0].image }

        let maxPreviewH = 2000
        let scale = min(1.0, CGFloat(maxPreviewH) / CGFloat(totalStitchedHeight))
        let previewW = max(1, Int(CGFloat(targetWidth) * scale))
        let previewH = max(1, Int(CGFloat(totalStitchedHeight) * scale))

        guard let context = createRGBContext(width: previewW, height: previewH) else { return nil }
        context.interpolationQuality = .low

        var yOffset = CGFloat(previewH)
        for strip in capturedStrips {
            let stripH = CGFloat(strip.height) * scale
            yOffset -= stripH
            context.draw(strip.image, in: CGRect(x: 0, y: yOffset, width: CGFloat(previewW), height: stripH))
        }

        return context.makeImage()
    }

    // MARK: - Result Delivery

    private func deliverResult() {
        let finalImage = stitchAllStrips()
        capturedStrips = []
        totalStitchedHeight = 0
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
