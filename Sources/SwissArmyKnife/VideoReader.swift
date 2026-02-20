//
//  File.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 04/12/2025.
//

import Foundation
import AVFoundation
import CoreImage

#if os(iOS)

@available(iOS, introduced: 11.0, obsoleted: 16.0)
extension CMTime: Hashable {
    public var hashValue: Int {
        get {
            var hasher = Hasher()
            
            hasher.combine(value)
            hasher.combine(timescale)
            hasher.combine(flags.rawValue)
            hasher.combine(epoch)

            return hasher.finalize()
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        hasher.combine(timescale)
        hasher.combine(flags.rawValue)
        hasher.combine(epoch)
    }
}

#endif

public final class VideoReader {
    public let url:URL
    public let asset: AVAsset
    public let duration: CMTime
    
    private let videoTrack: AVAssetTrack?
    
    private var lastRandomAudioWindow: CMTimeRange?
    
    public let preferredImageRotation: CGFloat
    public let fps:Float
    public let sourceResolution:CGSize
    
    public var destinationResolution: CGSize {
        // If not set, keep source
        guard let target = outputResolution else { return sourceResolution }
        
        // Must be valid positive target
        guard target.width > 0, target.height > 0 else { return sourceResolution }
        
        // Match scaleSampleBufferIfNeeded's rounding behavior
        let dstW = target.width.rounded()
        let dstH = target.height.rounded()
        
        // If rounding collapses to non-positive, treat as "not set"
        guard dstW > 0, dstH > 0 else { return sourceResolution }
        
        // If it would be a no-op anyway, keep source
        let srcW = sourceResolution.width.rounded()
        let srcH = sourceResolution.height.rounded()
        if srcW == dstW && srcH == dstH {
            return sourceResolution
        }
        
        return CGSize(width: dstW, height: dstH)
    }
    
    public private(set) var framePTS: [CMTime] = []
    public private(set) var currentFrameIndex = -1
    
    public var outputResolution: CGSize? = nil
    public var skippedFrameCount: Int = 0 // USE THIS
    private let ciContext = CIContext(options: [.cacheIntermediates: true])
    
    public var outputFps: Float {
        guard fps.isFinite, fps > 0 else { return .nan }
        let skip = max(0, skippedFrameCount)
        return fps / Float(skip + 1)
    }
    
    public var frameCount:Int {
        try? buildFrameIndexIfNeeded()
        
        return framePTS.count
    }
    
    public init(url: URL) {
        self.url = url
        self.asset = AVAsset(url: url)
        self.duration = asset.duration
        self.videoTrack = asset.tracks(withMediaType: .video).first
        
        if let videoTrack {
            self.sourceResolution = videoTrack.naturalSize   // ✅ raw track dimensions
            
            let t = videoTrack.preferredTransform
            let angle = atan2(t.b, t.a)
            let quarterTurn = CGFloat.pi / 2
            preferredImageRotation = round(angle / quarterTurn) * quarterTurn
            
            fps = videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : .nan
        }
        else {
            self.sourceResolution = .invalid
            preferredImageRotation = .nan
            fps = .nan
        }
    }
    
    public func copyVideoSample(atFrameIndex index: Int) throws -> CMSampleBuffer? {
        try buildFrameIndexIfNeeded()
        guard !framePTS.isEmpty else { return nil }
        
        let clamped = clamp(index, minValue: 0, maxValue: framePTS.count - 1)
        
        let step = max(0, skippedFrameCount) + 1
        let validIndex = (clamped / step) * step    // round down to previous kept frame
        
        let pts = framePTS[validIndex]
        currentFrameIndex = validIndex              // source index
        
        return try copyVideoSample(at: pts)
    }
    
    public func copyCurrentVideoSample() throws -> CMSampleBuffer? {
        return try copyVideoSample(atFrameIndex: currentFrameIndex)
    }
    
    public func copyNextVideoSample() throws -> CMSampleBuffer? {
        try buildFrameIndexIfNeeded()
        guard !framePTS.isEmpty else { return nil }
        
        let step = max(0, skippedFrameCount) + 1
        
        // If not started yet, start at first valid frame (0)
        let baseIndex = (currentFrameIndex < 0) ? 0 : currentFrameIndex
        let nextIndex = clamp(baseIndex + step, minValue: 0, maxValue: framePTS.count - 1)
        
        // Round down just in case we hit the end non-aligned (keeps invariant)
        let validNextIndex = (nextIndex / step) * step
        
        let pts = framePTS[validNextIndex]
        guard let sample = try copyVideoSample(at: pts) else { return nil }
        
        currentFrameIndex = validNextIndex
        return sample
    }
    
    public func copyPrevVideoSample() throws -> CMSampleBuffer? {
        try buildFrameIndexIfNeeded()
        guard !framePTS.isEmpty else { return nil }
        
        let step = max(0, skippedFrameCount) + 1
        
        // If not started yet, there's no "previous"
        guard currentFrameIndex >= 0 else { return nil }
        
        let prevIndex = clamp(currentFrameIndex - step, minValue: 0, maxValue: framePTS.count - 1)
        let validPrevIndex = (prevIndex / step) * step
        
        let pts = framePTS[validPrevIndex]
        guard let sample = try copyVideoSample(at: pts) else { return nil }
        
        currentFrameIndex = validPrevIndex
        return sample
    }
    
    private func createVideoAssetReader(asset: AVAsset, track: AVAssetTrack) throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput)  {
        let assetReader = try AVAssetReader(asset: asset)
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)),
        ]
        
        let readerVideoTrackOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: outputSettings)
        readerVideoTrackOutput.alwaysCopiesSampleData = false
        
        assetReader.add(readerVideoTrackOutput)
        
        return (assetReader, readerVideoTrackOutput)
    }
    
    private func buildFrameIndexIfNeeded() throws {
        guard framePTS.isEmpty else { return }
        guard let videoTrack else { return }   // no video – nothing to do
        
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: nil  // compressed; faster and low-memory
        )
        output.alwaysCopiesSampleData = false
        
        guard reader.canAdd(output) else {
            throw NSError(
                domain: "VideoReader",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add video output for index building"]
            )
        }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        guard reader.startReading() else {
            throw reader.error ?? NSError(
                domain: "VideoReader",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start index-building reader"]
            )
        }
        
        var ptsArray: [CMTime] = []
        
        while let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if pts.isValid {
                ptsArray.append(pts)
            }
        }
        
        reader.cancelReading()
        
        framePTS = Array(Set(ptsArray)).sorted()
    }
    
    private func copyVideoSample(at time: CMTime) throws -> CMSampleBuffer? {
        guard let videoTrack else { return nil }
        
        let clampedTime = clamp(time, minValue: .zero, maxValue: duration)
        let remainingDuration = duration - clampedTime
        
        guard remainingDuration > .zero else { return nil }
        
        let reader = try createVideoAssetReader(asset: self.asset, track: videoTrack)
        reader.reader.timeRange = CMTimeRange(start: clampedTime, duration: remainingDuration)
        
        guard reader.reader.startReading() else {
            throw reader.reader.error ?? NSError(
                domain: "VideoReader",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start reading"]
            )
        }
        
        let sample = reader.output.copyNextSampleBuffer()
        reader.reader.cancelReading()
        
        guard let sample else { return nil }
        
        if let target = outputResolution {
            return try scaleSampleBufferIfNeeded(sample)
        }
        
        return sample
    }
    
    private func scaleSampleBufferIfNeeded(_ sample: CMSampleBuffer) throws -> CMSampleBuffer {
        guard
            let srcPB = CMSampleBufferGetImageBuffer(sample)
        else { return sample }
        
        let srcW = CVPixelBufferGetWidth(srcPB)
        let srcH = CVPixelBufferGetHeight(srcPB)
        
        let dstSize = destinationResolution
        let dstW = Int(dstSize.width)
        let dstH = Int(dstSize.height)
        
        // No-op: destination matches source
        if srcW == dstW && srcH == dstH {
            return sample
        }
        
        // Create destination PB (same pixel format as source)
        var dstPB: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: dstW,
            kCVPixelBufferHeightKey as String: dstH,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String:
                CVPixelBufferGetPixelFormatType(srcPB)
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            dstW,
            dstH,
            CVPixelBufferGetPixelFormatType(srcPB),
            attrs as CFDictionary,
            &dstPB
        )
        
        guard status == kCVReturnSuccess, let dstPB else {
            throw NSError(
                domain: "VideoReader",
                code: -30,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to create destination pixel buffer (\(status))"
                ]
            )
        }
        
        // Scale using CI
        let srcImage = CIImage(cvPixelBuffer: srcPB)
        let sx = CGFloat(dstW) / CGFloat(srcW)
        let sy = CGFloat(dstH) / CGFloat(srcH)
        let scaled = srcImage.transformed(
            by: CGAffineTransform(scaleX: sx, y: sy)
        )
        
        ciContext.render(scaled, to: dstPB)
        
        // Preserve timing
        var timing = CMSampleTimingInfo()
        var timingCount: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: 1,
            arrayToFill: &timing,
            entriesNeededOut: &timingCount
        )
        
        var formatDesc: CMVideoFormatDescription?
        let fdStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: dstPB,
            formatDescriptionOut: &formatDesc
        )
        
        guard fdStatus == noErr, let formatDesc else {
            throw NSError(
                domain: "VideoReader",
                code: -31,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to create format description (\(fdStatus))"
                ]
            )
        }
        
        var out: CMSampleBuffer?
        let sbStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: dstPB,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &out
        )
        
        guard sbStatus == noErr, let out else {
            throw NSError(
                domain: "VideoReader",
                code: -32,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to create scaled CMSampleBuffer (\(sbStatus))"
                ]
            )
        }
        
        return out
    }
}

public extension VideoReader {
    public func createDummyVideoData() -> VideoData {
        try? buildFrameIndexIfNeeded()

        let landscapeInput = destinationResolution.width > destinationResolution.height
        let quaterTurnCount = Int(round(abs(preferredImageRotation) / (.pi * 0.5)))
        let landscapeOutput = (landscapeInput && (quaterTurnCount % 2 == 0)) || (!landscapeInput && (quaterTurnCount % 2 == 1))
        
        return VideoData(videoTimestamps: framePTS,
                         skippedTimestamps: [],
                         gyro: framePTS.map { _ in landscapeOutput ? simd_quatf(real: 1.0, imag: SIMD3<Float>(0.0, -1.0, 0.0)) : simd_quatf(real: 1.0, imag: SIMD3<Float>(-1.0, 0.0, 0.0)) },
                         gyroTimestamps: framePTS.map { t in t.seconds },
                         horizontalFOV: 1.22,
                         verticalFOV: 0.93,
                         shutterSpeed: 1.0 / 1000)
    }
}
