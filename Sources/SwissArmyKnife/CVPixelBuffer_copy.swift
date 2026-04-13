//
//  CVPixelBuffer_copy.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 13/04/2026.
//

import CoreVideo

public enum PixelBufferCopyError: Error {
    case allocationFailed
    case baseAddressUnavailable
    case invalidDestinationLayout
}

extension PixelBufferCopyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .allocationFailed:
            return "failed to allocate pixel buffer"
        case .baseAddressUnavailable:
            return "pixel buffer base address unavailable"
        case .invalidDestinationLayout:
            return "destination pixel buffer layout incompatible with source"
        }
    }
}

public extension CVPixelBuffer {
    func copy(using pool: CVPixelBufferPool? = nil) throws -> CVPixelBuffer {
        let copiedBuffer = try makeCopyDestination(using: pool)

        if let attachments = CVBufferGetAttachments(self, .shouldPropagate) {
            CVBufferSetAttachments(copiedBuffer, attachments, .shouldPropagate)
        }

        CVPixelBufferLockBaseAddress(self, .readOnly)
        CVPixelBufferLockBaseAddress(copiedBuffer, [])

        defer {
            CVPixelBufferUnlockBaseAddress(copiedBuffer, [])
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
        }

        let planeCount = CVPixelBufferGetPlaneCount(self)
        guard planeCount == CVPixelBufferGetPlaneCount(copiedBuffer) else {
            throw PixelBufferCopyError.invalidDestinationLayout
        }

        if planeCount == 0 {
            guard
                let source = CVPixelBufferGetBaseAddress(self),
                let dest = CVPixelBufferGetBaseAddress(copiedBuffer)
            else {
                throw PixelBufferCopyError.baseAddressUnavailable
            }

            try copyRows(
                from: source,
                to: dest,
                height: CVPixelBufferGetHeight(self),
                bytesPerRowSrc: CVPixelBufferGetBytesPerRow(self),
                bytesPerRowDest: CVPixelBufferGetBytesPerRow(copiedBuffer)
            )
        } else {
            for plane in 0..<planeCount {
                guard
                    let source = CVPixelBufferGetBaseAddressOfPlane(self, plane),
                    let dest = CVPixelBufferGetBaseAddressOfPlane(copiedBuffer, plane)
                else {
                    throw PixelBufferCopyError.baseAddressUnavailable
                }

                guard
                    CVPixelBufferGetWidthOfPlane(self, plane) == CVPixelBufferGetWidthOfPlane(copiedBuffer, plane),
                    CVPixelBufferGetHeightOfPlane(self, plane) == CVPixelBufferGetHeightOfPlane(copiedBuffer, plane)
                else {
                    throw PixelBufferCopyError.invalidDestinationLayout
                }

                try copyRows(
                    from: source,
                    to: dest,
                    height: CVPixelBufferGetHeightOfPlane(self, plane),
                    bytesPerRowSrc: CVPixelBufferGetBytesPerRowOfPlane(self, plane),
                    bytesPerRowDest: CVPixelBufferGetBytesPerRowOfPlane(copiedBuffer, plane)
                )
            }
        }

        return copiedBuffer
    }

    private func makeCopyDestination(using pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?

        if let pool {
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard status == kCVReturnSuccess, let buffer else {
                throw PixelBufferCopyError.allocationFailed
            }
            return buffer
        } else {
            let width = CVPixelBufferGetWidth(self)
            let height = CVPixelBufferGetHeight(self)
            let formatType = CVPixelBufferGetPixelFormatType(self)

            let status = CVPixelBufferCreate(nil, width, height, formatType, nil, &buffer)
            guard status == kCVReturnSuccess, let buffer else {
                throw PixelBufferCopyError.allocationFailed
            }
            return buffer
        }
    }

    private func copyRows(
        from source: UnsafeMutableRawPointer,
        to dest: UnsafeMutableRawPointer,
        height: Int,
        bytesPerRowSrc: Int,
        bytesPerRowDest: Int
    ) throws {
        guard bytesPerRowDest >= bytesPerRowSrc else {
            throw PixelBufferCopyError.invalidDestinationLayout
        }

        var sourceRow = source
        var destRow = dest

        for _ in 0..<height {
            memcpy(destRow, sourceRow, bytesPerRowSrc)
            sourceRow = sourceRow.advanced(by: bytesPerRowSrc)
            destRow = destRow.advanced(by: bytesPerRowDest)
        }
    }
}

public extension CVPixelBufferPool {
    static func makePool(
        from buffer: CVPixelBuffer,
        minimumBufferCount: Int = 8
    ) -> CVPixelBufferPool? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)

        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: minimumBufferCount
        ]

        var pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        if let propagated = CVBufferGetAttachments(buffer, .shouldPropagate) as? [String: Any] {
            for (key, value) in propagated {
                pixelBufferAttributes[key] = value
            }
        }

        var pool: CVPixelBufferPool?

        let status = CVPixelBufferPoolCreate(
            nil,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )

        guard status == kCVReturnSuccess else {
            return nil
        }

        return pool
    }
}

public struct CVPixelBufferPoolState {
    public var pool: CVPixelBufferPool
    public var width: Int
    public var height: Int
    public var pixelFormat: OSType
    public var planeCount: Int

    public static func make(from buffer: CVPixelBuffer, minimumBufferCount: Int = 8) -> CVPixelBufferPoolState? {
        guard let pool = CVPixelBufferPool.makePool(from: buffer, minimumBufferCount: minimumBufferCount) else {
            return nil
        }

        return CVPixelBufferPoolState(
            pool: pool,
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            pixelFormat: CVPixelBufferGetPixelFormatType(buffer),
            planeCount: CVPixelBufferGetPlaneCount(buffer)
        )
    }

    public func isCompatible(with buffer: CVPixelBuffer) -> Bool {
        width == CVPixelBufferGetWidth(buffer) &&
        height == CVPixelBufferGetHeight(buffer) &&
        pixelFormat == CVPixelBufferGetPixelFormatType(buffer) &&
        planeCount == CVPixelBufferGetPlaneCount(buffer)
    }
}
