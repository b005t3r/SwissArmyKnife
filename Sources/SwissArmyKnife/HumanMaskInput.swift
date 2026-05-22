//
//  HumanMaskInput.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 18/05/2026.
//

import Foundation
import Vision
import CoreVideo
import CoreMedia
import MetalKit

import GPUImage

public final class HumanMaskInput: ImageSource {
    public let targets = TargetContainer()

    private let maskGenerator: HumanMaskGenerator
    private let textureCache: CVMetalTextureCache
    private let processingQueue = DispatchQueue(label: "MaskInput.processingQueue")

    private var internalTexture: Texture?
    private var internalCVTexture: CVMetalTexture?
    private var hasProcessedImage = false

    public init(qualityLevel: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced) {
        self.maskGenerator = HumanMaskGenerator(
            qualityLevel: qualityLevel,
            outputPixelFormat: kCVPixelFormatType_OneComponent8
        )

        var textureCache: CVMetalTextureCache?

        CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            sharedMetalRenderingDevice.device,
            nil,
            &textureCache
        )

        guard let textureCache else {
            fatalError("Failed creating CVMetalTextureCache")
        }

        self.textureCache = textureCache
    }

    public func processImage(
        _ sampleBuffer: CMSampleBuffer,
        orientation: FrameOrientation = .none,
        synchronously: Bool = false
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            fatalError("Missing pixel buffer")
        }

        processImage(pixelBuffer, orientation: orientation, synchronously: synchronously)
    }

    public func processImage(
        _ pixelBuffer: CVPixelBuffer,
        orientation: FrameOrientation = .none,
        synchronously: Bool = false
    ) {
        if synchronously {
            processPixelBuffer(pixelBuffer, orientation: orientation)
        } else {
            processingQueue.async {
                self.processPixelBuffer(pixelBuffer, orientation: orientation)
            }
        }
    }

    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        if hasProcessedImage, let internalTexture {
            target.newTextureAvailable(internalTexture, fromSourceIndex: atIndex)
        }
    }

    private func processPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        orientation: FrameOrientation
    ) {
        do {
            let maskPixelBuffer = try maskGenerator.mask(
                from: pixelBuffer,
                orientation: orientation
            )

            let texture = try makeTexture(
                from: maskPixelBuffer,
                orientation: orientation.imageOrientation
            )

            self.internalTexture = texture
            self.hasProcessedImage = true
            self.updateTargetsWithTexture(texture)
        } catch {
            fatalError("Failed generating mask texture: \(error)")
        }
    }

    private func makeTexture(
        from pixelBuffer: CVPixelBuffer,
        orientation: ImageOrientation
    ) throws -> Texture {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?

        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTexture else {
            throw MaskInputError.failedCreatingTexture
        }

        guard let metalTexture = CVMetalTextureGetTexture(cvTexture) else {
            throw MaskInputError.missingMetalTexture
        }

        self.internalCVTexture = cvTexture

        return Texture(
            orientation: orientation,
            texture: metalTexture
        )
    }
}

private enum MaskInputError: Error {
    case failedCreatingTexture
    case missingMetalTexture
}
