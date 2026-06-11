//
//  PixelBufferRenderer.swift
//  StabilizedTrackingTester
//
//  Created by Łukasz Łazarecki on 05/12/2025.
//

import Foundation
import CoreMedia

import GPUImage

public class VideoFrameRenderer: ImageSource {
    public let targets = TargetContainer()

    var videoTextureCache: CVMetalTextureCache?
    let yuvConversionRenderPipelineState: MTLRenderPipelineState
    var yuvLookupTable: [String: (Int, MTLStructMember)] = [:]
    var yuvBufferSize: Int = 0

    public init() {
        let (pipelineState, lookupTable, bufferSize) = generateRenderPipelineState(
            device: sharedMetalRenderingDevice, vertexFunctionName: "twoInputVertex",
            fragmentFunctionName: "yuvConversionFullRangeFragment", operationName: "YUVToRGB")
        self.yuvConversionRenderPipelineState = pipelineState
        self.yuvLookupTable = lookupTable
        self.yuvBufferSize = bufferSize
    
        let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, sharedMetalRenderingDevice.device, nil, &videoTextureCache)
    }
    
    public func transmitPreviousImage(to target: any GPUImage.ImageConsumer, atIndex: UInt) {
        // do nothing
    }

    public func process(movieFrame frame: CMSampleBuffer, rotation: CGFloat = .nan) {
        let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(frame)
        let movieFrame = CMSampleBufferGetImageBuffer(frame)!

        //        processingFrameTime = currentSampleTime
        self.process(movieFrame: movieFrame, sampleTime: currentSampleTime, rotation: rotation)
    }

    public func process(movieFrame: CVPixelBuffer, sampleTime: CMTime, rotation: CGFloat = .nan) {
        let bufferHeight = CVPixelBufferGetHeight(movieFrame)
        let bufferWidth = CVPixelBufferGetWidth(movieFrame)

        CVPixelBufferLockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

        let conversionMatrix = colorConversionMatrix601FullRangeDefault

        let texture: Texture?
        var luminanceTextureRef: CVMetalTexture? = nil
        var chrominanceTextureRef: CVMetalTexture? = nil
        // Luminance plane
        let _ = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, self.videoTextureCache!, movieFrame, nil, .r8Unorm, bufferWidth,
            bufferHeight, 0, &luminanceTextureRef)
        // Chrominance plane
        let _ = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, self.videoTextureCache!, movieFrame, nil, .rg8Unorm,
            bufferWidth / 2, bufferHeight / 2, 1, &chrominanceTextureRef)

        let inputOrientation:ImageOrientation = bufferWidth >= bufferHeight ? .landscapeRight : .portrait
        let outputOrientation:ImageOrientation
        
        if rotation.isFinite {
            let twoPi = CGFloat.pi * 2

            var clamped = rotation.truncatingRemainder(dividingBy: twoPi)
            if clamped < 0 {
                clamped += twoPi
            }

            let quarterTurn = CGFloat.pi / 2
            let quarterTurns = Int(round(clamped / quarterTurn)) % 4  // 0,1,2,3

            if rotation.isFinite {
                   let twoPi = CGFloat.pi * 2
                   var clamped = rotation.truncatingRemainder(dividingBy: twoPi)

                   if clamped < 0 {
                       clamped += twoPi
                   }

                   let quarterTurn = CGFloat.pi / 2
                   let quarterTurns = Int(round(clamped / quarterTurn)) % 4

                   switch (inputOrientation, quarterTurns) {
                       case (.portrait, 0):
                           outputOrientation = .portrait

                       case (.portrait, 1):
                           outputOrientation = .landscapeLeft

                       case (.portrait, 2):
                           outputOrientation = .portraitUpsideDown

                       case (.portrait, 3):
                           outputOrientation = .landscapeRight

                       case (.portraitUpsideDown, 0):
                           outputOrientation = .portraitUpsideDown

                       case (.portraitUpsideDown, 1):
                           outputOrientation = .landscapeRight

                       case (.portraitUpsideDown, 2):
                           outputOrientation = .portrait

                       case (.portraitUpsideDown, 3):
                           outputOrientation = .landscapeLeft

                       case (.landscapeLeft, 0):
                           outputOrientation = .landscapeLeft

                       case (.landscapeLeft, 1):
                           outputOrientation = .portraitUpsideDown

                       case (.landscapeLeft, 2):
                           outputOrientation = .landscapeRight

                       case (.landscapeLeft, 3):
                           outputOrientation = .portrait

                       case (.landscapeRight, 0):
                           outputOrientation = .landscapeRight

                       case (.landscapeRight, 1):
                           outputOrientation = .portrait

                       case (.landscapeRight, 2):
                           outputOrientation = .landscapeLeft

                       case (.landscapeRight, 3):
                           outputOrientation = .portraitUpsideDown

                       default:
                           outputOrientation = inputOrientation
                   }
               }
               else {
                   outputOrientation = inputOrientation
               }
        }
        else {
            outputOrientation = inputOrientation
        }
        
        let outputWidth: Int
        let outputHeight: Int
        
        if inputOrientation.rotationNeeded(for: outputOrientation).flipsDimensions() {
            outputWidth = bufferHeight
            outputHeight = bufferWidth
        } else {
            outputWidth = bufferWidth
            outputHeight = bufferHeight
        }

        if let concreteLuminanceTextureRef = luminanceTextureRef,
            let concreteChrominanceTextureRef = chrominanceTextureRef,
            let luminanceTexture = CVMetalTextureGetTexture(concreteLuminanceTextureRef),
            let chrominanceTexture = CVMetalTextureGetTexture(concreteChrominanceTextureRef)
        {
            let outputTexture = Texture(
                device: sharedMetalRenderingDevice.device, orientation: outputOrientation,
                width: outputWidth, height: outputHeight,
                timingStyle: .videoFrame(timestamp: Timestamp(sampleTime)))

            convertYUVToRGB(
                pipelineState: self.yuvConversionRenderPipelineState,
                lookupTable: self.yuvLookupTable, bufferSize: self.yuvBufferSize,
                luminanceTexture: Texture(orientation: inputOrientation, texture: luminanceTexture),
                chrominanceTexture: Texture(orientation: inputOrientation, texture: chrominanceTexture),
                resultTexture: outputTexture, colorConversionMatrix: conversionMatrix)
            texture = outputTexture
        } else {
            texture = nil
        }

        if texture != nil {
            self.updateTargetsWithTexture(texture!)
        }

        CVPixelBufferUnlockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
    }
}
