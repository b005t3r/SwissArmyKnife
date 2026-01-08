//
//  File.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 04/12/2025.
//

import Foundation
import AVFoundation

//
//  File.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 04/12/2025.
//

import Foundation
import AVFoundation

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
    public let asset: AVAsset
    public let duration: CMTime
    
    private let videoTrack: AVAssetTrack?
    
    private let readingQueue = DispatchQueue(label: "VideoReader.reading.queue")
    
    private var continuousReader: AVAssetReader?
    private var continuousVideoOutput: AVAssetReaderTrackOutput?
    
    private var lastRandomAudioWindow: CMTimeRange?
    
    public let preferredImageRotation: CGFloat
    public let fps:Float
    
    public private(set) var framePTS: [CMTime] = []
    public private(set) var currentFrameIndex = -1

    public var frameCount:Int {
        try? buildFrameIndexIfNeeded()
        
        return framePTS.count
    }
    
    public init(url: URL) {
        self.asset = AVAsset(url: url)
        self.duration = asset.duration
        self.videoTrack = asset.tracks(withMediaType: .video).first

        if let t = videoTrack?.preferredTransform {
            let angle = atan2(t.b, t.a)
            let quarterTurn = CGFloat.pi / 2

            preferredImageRotation = round(angle / quarterTurn) * quarterTurn
            if let track = videoTrack, track.nominalFrameRate > 0 {
                fps = track.nominalFrameRate
            } else {
                fps = .nan
            }
        }
        else {
            preferredImageRotation = .nan
            fps = .nan
        }
    }
    
    public func copyVideoSample(atFrameIndex index: Int) throws -> CMSampleBuffer? {
        try buildFrameIndexIfNeeded()
        guard framePTS.indices.contains(index) else { return nil }
        let pts = framePTS[index]
        
        currentFrameIndex = index

        return try copyVideoSample(at: pts)
    }
        
    public func copyNextVideoSample() throws -> CMSampleBuffer? {
        try buildFrameIndexIfNeeded()
        guard !framePTS.isEmpty else { return nil }
        
        let nextIndex = clamp(currentFrameIndex + 1, minValue: 0, maxValue: framePTS.count - 1)
        
        let pts = framePTS[nextIndex]
        guard let sample = try copyVideoSample(at: pts) else { return nil }
        
        currentFrameIndex = nextIndex
        return sample
    }
    
    public func copyPrevVideoSample() throws -> CMSampleBuffer? {
        try buildFrameIndexIfNeeded()
        guard !framePTS.isEmpty else { return nil }
        
        let prevIndex = clamp(currentFrameIndex - 1, minValue: 0, maxValue: framePTS.count - 1)

        let pts = framePTS[prevIndex]
        guard let sample = try copyVideoSample(at: pts) else { return nil }
        
        currentFrameIndex = prevIndex
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
        
        return sample
    }
}
