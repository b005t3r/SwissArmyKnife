//
//  AudioReader.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 06/03/2026.
//

import Foundation
import AVFoundation

public enum AudioReaderError: Error {
    case noAudioTrack
}

public final class AudioReader {
    public let url: URL
    public let asset: AVAsset
    public let duration: CMTime
    
    private let audioTrack: AVAssetTrack?
    
    public private(set) var samplePTS: [CMTime] = []
    public private(set) var currentSampleIndex = -1
    
    public var sampleCount: Int {
        try? buildSampleIndexIfNeeded()
        return samplePTS.count
    }
    
    private var cachedReader: AVAssetReader?
    private var cachedOutput: AVAssetReaderTrackOutput?
    private var cachedLastPTS: CMTime?
    
    public init(url: URL) throws {
        self.url = url
        self.asset = AVAsset(url: url)
        self.duration = asset.duration
        self.audioTrack = asset.tracks(withMediaType: .audio).first
        
        guard audioTrack != nil else {
            throw AudioReaderError.noAudioTrack
        }
    }
    
    public func copyAudioSample(atSampleIndex index: Int) throws -> CMSampleBuffer? {
        try buildSampleIndexIfNeeded()
        guard !samplePTS.isEmpty else { return nil }
        
        let clamped = clamp(index, minValue: 0, maxValue: samplePTS.count - 1)
        let pts = samplePTS[clamped]
        currentSampleIndex = clamped
        
        return try copyAudioSample(at: pts)
    }
    
    public func copyCurrentAudioSample() throws -> CMSampleBuffer? {
        return try copyAudioSample(atSampleIndex: currentSampleIndex)
    }
    
    public func copyNextAudioSample() throws -> CMSampleBuffer? {
        try buildSampleIndexIfNeeded()
        guard !samplePTS.isEmpty else { return nil }
        
        let nextIndex = clamp(currentSampleIndex + 1, minValue: 0, maxValue: samplePTS.count - 1)
        let pts = samplePTS[nextIndex]
        
        guard let sample = try copyAudioSample(at: pts) else { return nil }
        
        currentSampleIndex = nextIndex
        return sample
    }
    
    public func copyPrevAudioSample() throws -> CMSampleBuffer? {
        try buildSampleIndexIfNeeded()
        guard !samplePTS.isEmpty else { return nil }
        guard currentSampleIndex >= 0 else { return nil }
        
        let prevIndex = clamp(currentSampleIndex - 1, minValue: 0, maxValue: samplePTS.count - 1)
        let pts = samplePTS[prevIndex]
        
        guard let sample = try copyAudioSample(at: pts) else { return nil }
        
        currentSampleIndex = prevIndex
        return sample
    }
    
    private func createAudioAssetReader(asset: AVAsset, track: AVAssetTrack) throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput) {
        let assetReader = try AVAssetReader(asset: asset)
        
        let readerAudioTrackOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: nil
        )
        readerAudioTrackOutput.alwaysCopiesSampleData = false
        
        guard assetReader.canAdd(readerAudioTrackOutput) else {
            throw NSError(
                domain: "AudioReader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add audio output"]
            )
        }
        
        assetReader.add(readerAudioTrackOutput)
        
        return (assetReader, readerAudioTrackOutput)
    }
    
    private func buildSampleIndexIfNeeded() throws {
        guard samplePTS.isEmpty else { return }
        guard let audioTrack else { return }
        
        teardownCachedReader()
        
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: nil
        )
        output.alwaysCopiesSampleData = false
        
        guard reader.canAdd(output) else {
            throw NSError(
                domain: "AudioReader",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add audio output for index building"]
            )
        }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        guard reader.startReading() else {
            throw reader.error ?? NSError(
                domain: "AudioReader",
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
        
        samplePTS = Array(Set(ptsArray)).sorted()
    }
    
    private func copyAudioSample(at time: CMTime) throws -> CMSampleBuffer? {
        guard let audioTrack else { return nil }
        
        let clampedTime = clamp(time, minValue: .zero, maxValue: duration)
        let remainingDuration = duration - clampedTime
        guard remainingDuration > .zero else { return nil }
        
        if shouldUseCachedReader(for: clampedTime),
           let out = cachedOutput,
           let reader = cachedReader,
           reader.status == .reading {
            
            guard let sample = out.copyNextSampleBuffer() else {
                teardownCachedReader()
                return nil
            }
            
            updateCachedLastPTS(from: sample, fallback: clampedTime)
            return sample
        }
        
        teardownCachedReader()
        
        let created = try createAudioAssetReader(asset: asset, track: audioTrack)
        created.reader.timeRange = CMTimeRange(start: clampedTime, duration: remainingDuration)
        
        guard created.reader.startReading() else {
            throw created.reader.error ?? NSError(
                domain: "AudioReader",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start reading"]
            )
        }
        
        guard let sample = created.output.copyNextSampleBuffer() else {
            created.reader.cancelReading()
            return nil
        }
        
        cachedReader = created.reader
        cachedOutput = created.output
        updateCachedLastPTS(from: sample, fallback: clampedTime)
        
        return sample
    }
}

private extension AudioReader {
    func teardownCachedReader() {
        cachedReader?.cancelReading()
        cachedReader = nil
        cachedOutput = nil
        cachedLastPTS = nil
    }
    
    func updateCachedLastPTS(from sample: CMSampleBuffer, fallback: CMTime) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        cachedLastPTS = pts.isValid ? pts : fallback
    }
    
    func shouldUseCachedReader(for requestedPTS: CMTime) -> Bool {
        guard
            let last = cachedLastPTS,
            let lastIndex = samplePTS.firstIndex(of: last)
        else { return false }
        
        let nextIndex = lastIndex + 1
        guard nextIndex < samplePTS.count else { return false }
        
        return samplePTS[nextIndex] == requestedPTS
    }
}
