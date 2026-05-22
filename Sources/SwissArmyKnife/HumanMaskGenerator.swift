//
//  HumanMaskGenerator.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 18/05/2026.
//

import Foundation
import Vision
import CoreVideo
import CoreMedia

final class HumanMaskGenerator {
    enum Error: Swift.Error {
        case missingPixelBuffer
        case noResult
    }

    private let request: VNGeneratePersonSegmentationRequest
    private let sequenceHandler = VNSequenceRequestHandler()

    init(qualityLevel: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced, outputPixelFormat: OSType = kCVPixelFormatType_OneComponent8) {
        self.request = VNGeneratePersonSegmentationRequest()
        self.request.qualityLevel = qualityLevel
        self.request.outputPixelFormat = outputPixelFormat
    }

    func mask(from sampleBuffer: CMSampleBuffer, orientation: FrameOrientation = .none) throws -> CVPixelBuffer {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw Error.missingPixelBuffer
        }

        return try mask(from: pixelBuffer, orientation: orientation)
    }

    func mask(from pixelBuffer: CVPixelBuffer, orientation: FrameOrientation = .none) throws -> CVPixelBuffer {
        try sequenceHandler.perform([request], on: pixelBuffer, orientation: orientation.orientation)

        guard let result = request.results?.first else {
            throw Error.noResult
        }

        return result.pixelBuffer
    }
}
