//
//  Stopwatch.swift
//  GPUImageTest
//
//  Created by Łukasz Łazarecki on 19/11/2025.
//

import Foundation
import AVFoundation

public class VideoRecorder {
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
        if let transform = transform {
            assetWriterVideoInput.transform = transform
        }
        
        startTime = nil
        self.isRecording = self.assetWriter.startWriting()
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
    
    public func processPixelBuffer(pixelBuffer: CVPixelBuffer, frameTime:CMTime, queue:DispatchQueue? = nil, stopwatch:Stopwatch? = nil) {
        guard isRecording else { return }
        
        // If two consecutive times with the same value are added to the movie, it aborts recording, so I bail on that case
        guard frameTime != previousFrameTime else { return }
        
        if startTime == nil {
            if assetWriter.status != .writing {
                assetWriter.startWriting()
            }
            
            assetWriter.startSession(atSourceTime: frameTime)
            startTime = frameTime
        }
        
        let work = {
            stopwatch?.start()
            defer { stopwatch?.stop() }

            guard self.assetWriterVideoInput.isReadyForMoreMediaData || (!self.encodingLiveVideo) else {
                debugPrint("Had to drop a frame at time \(frameTime)")
                return
            }
            
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            
            if !self.assetWriterPixelBufferInput.append(pixelBuffer, withPresentationTime: frameTime) {
                print("Problem appending pixel buffer at time: \(frameTime)")
            }
            
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        
        if let queue = queue {
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
}
