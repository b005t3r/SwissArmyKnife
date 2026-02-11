//
//  Stopwatch.swift
//  GPUImageTest
//
//  Created by Łukasz Łazarecki on 19/11/2025.
//

import Foundation
import AVFoundation

public class VideoRecorder {
    public struct FrameData {
        public let timestamp:CMTime
        public let encoded:Bool
        
        public init(timestamp: CMTime, encoded: Bool) {
            self.timestamp = timestamp
            self.encoded = encoded
        }
    }
    
    let assetWriter: AVAssetWriter
    let assetWriterVideoInput: AVAssetWriterInput
    var assetWriterAudioInput: AVAssetWriterInput?
    
    let assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor
    let size: CGSize
    private var isRecording = false
    private var videoEncodingIsFinished = false
    private var audioEncodingIsFinished = false
    private var startTime: CMTime?
    private var previousFrameTime = CMTime.negativeInfinity
    private var previousAudioTime = CMTime.negativeInfinity
    private var encodingLiveVideo: Bool
    
    private let frameDataQueue = DispatchQueue(label: "VideoRecorder.frameDataQueue")

    private var _frameData = [FrameData]()
    public var frameData: [FrameData] {
        frameDataQueue.sync { _frameData }
    }
    
    var transform: CGAffineTransform {
        get {
            return assetWriterVideoInput.transform
        }
        set {
            assetWriterVideoInput.transform = newValue
        }
    }
    
    public init(URL: Foundation.URL, size: CGSize, fileType: AVFileType = AVFileType.mov, liveVideo: Bool = false, enableAudio:Bool = false, settings: [String: AnyObject]? = nil
    ) throws {
        self.size = size
        assetWriter = try AVAssetWriter(url: URL, fileType: fileType)
        // Set this to make sure that a functional movie is produced, even if the recording is cut off mid-stream. Only the last second should be lost in that case.
        assetWriter.movieFragmentInterval = CMTimeMakeWithSeconds(1.0, preferredTimescale: 1000)
        
        var localSettings: [String: AnyObject]
        if let settings = settings {
            localSettings = settings
        } else {
            localSettings = [String: AnyObject]()
        }
        
        func heuristicBitrate(size: CGSize, fps: Double) -> Int {
            let size = min(size.width, size.height)

            if size < 1080 {
                return 10_000_000
            }
            
            let is4K = size > 1080 * 1.5
            let is60fps = fps > 30.0 * 1.5

            switch (is4K, is60fps) {
            case (false, false): return 15_000_000 // 1080p @ 30
            case (false, true):  return 25_000_000 // 1080p @ 60
            case (true, false):  return 40_000_000 // 4K @ 30
            case (true, true):   return 65_000_000 // 4K @ 60
            }
        }

        var compression = [String: Any]()
        compression[AVVideoAverageBitRateKey] = heuristicBitrate(size: size, fps: 60.0) // target 60 fps, since we don't have the actual value here
        
        localSettings[AVVideoCompressionPropertiesKey] = compression as AnyObject
        localSettings[AVVideoWidthKey] =
        localSettings[AVVideoWidthKey] ?? NSNumber(value: size.width)
        localSettings[AVVideoHeightKey] =
        localSettings[AVVideoHeightKey] ?? NSNumber(value: size.height)
        localSettings[AVVideoCodecKey] =
        localSettings[AVVideoCodecKey] ?? AVVideoCodecType.hevc as NSString
        
        assetWriterVideoInput = AVAssetWriterInput(
            mediaType: AVMediaType.video, outputSettings: localSettings)
        assetWriterVideoInput.expectsMediaDataInRealTime = liveVideo
        encodingLiveVideo = liveVideo
        
        let sourcePixelBufferAttributesDictionary: [String: AnyObject] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(
                value: Int32(kCVPixelFormatType_32BGRA)),
            kCVPixelBufferWidthKey as String: NSNumber(value: size.width),
            kCVPixelBufferHeightKey as String: NSNumber(value: size.height),
        ]
        
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterVideoInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary)
        
        assetWriter.add(assetWriterVideoInput)
        
        if enableAudio {
            assetWriterAudioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: nil)
            assetWriterAudioInput?.expectsMediaDataInRealTime = liveVideo
            
            assetWriter.add(assetWriterAudioInput!)
        }
    }
    
    public func startRecording(transform: CGAffineTransform? = nil) {
        if let transform {
            assetWriterVideoInput.transform = transform
        }

        startTime = nil
        previousFrameTime = CMTime.negativeInfinity
        previousAudioTime = CMTime.negativeInfinity
        frameDataQueue.sync {
            self._frameData.removeAll()
        }

        isRecording = assetWriter.startWriting()
    }
    
    public func finishRecording(_ completionCallback: (() -> Void)? = nil) {
        self.isRecording = false
        
        if self.assetWriter.status == .completed || self.assetWriter.status == .cancelled
            || self.assetWriter.status == .unknown
        {
            DispatchQueue.global().async {
                completionCallback?()
            }
            return
        }
        if (self.assetWriter.status == .writing) && (!self.videoEncodingIsFinished) {
            self.videoEncodingIsFinished = true
            self.assetWriterVideoInput.markAsFinished()
        }
        if (self.assetWriter.status == .writing) && (!self.audioEncodingIsFinished) {
            self.audioEncodingIsFinished = true
            self.assetWriterAudioInput?.markAsFinished()
        }
        
        // Why can't I use ?? here for the callback?
        if let callback = completionCallback {
            self.assetWriter.finishWriting(completionHandler: callback)
        } else {
            self.assetWriter.finishWriting {}
        }
    }
    
    public func processPixelBuffer(pixelBuffer: CVPixelBuffer,
                                   frameTime: CMTime,
                                   queue: DispatchQueue? = nil,
                                   stopwatch: Stopwatch? = nil)
    {
        guard isRecording else {
            recordFrame(frameTime, encoded: false)
            return
        }

        let work = {
            stopwatch?.start()

            defer { stopwatch?.stop() }

            // Only compare against last *encoded* frame
            if frameTime == self.previousFrameTime {
                self.recordFrame(frameTime, encoded: false)
                return
            }

            // For live sources, do not start session until ready
            guard self.assetWriterVideoInput.isReadyForMoreMediaData || (!self.encodingLiveVideo) else {
                self.recordFrame(frameTime, encoded: false)
                return
            }

            if self.assetWriter.status == .unknown {
                _ = self.assetWriter.startWriting()
            }

            // Start session immediately before first append attempt
            if self.startTime == nil {
                self.assetWriter.startSession(atSourceTime: frameTime)
                self.startTime = frameTime
            }

            let ok = self.assetWriterPixelBufferInput.append(pixelBuffer, withPresentationTime: frameTime)
            if ok {
                self.recordFrame(frameTime, encoded: true)
                self.previousFrameTime = frameTime
            } else {
                self.recordFrame(frameTime, encoded: false)
            }
        }

        if let queue {
            queue.async(execute: work)
        } else {
            work()
        }
    }
    
    public func processAudioBuffer(sampleBuffer: CMSampleBuffer, queue: DispatchQueue? = nil, stopwatch:Stopwatch? = nil) {
        guard let startTime else { return } // wait until video starts the session
        guard let assetWriterAudioInput else { return }
        
        let work = {
            stopwatch?.start()
            defer { stopwatch?.stop() }
            
            guard assetWriterAudioInput.isReadyForMoreMediaData || (!self.encodingLiveVideo) else {
                return
            }
            
            if !assetWriterAudioInput.append(sampleBuffer) {
                print("Trouble appending audio sample buffer")
            }
        }
        
        if let queue = queue {
            queue.async(execute: work)
        } else {
            work()
        }
    }
    
    private func recordFrame(_ timestamp: CMTime, encoded: Bool) {
        frameDataQueue.sync {
            self._frameData.append(FrameData(timestamp: timestamp, encoded: encoded))
        }
    }
}
