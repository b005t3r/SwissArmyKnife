//
//  File.swift
//  GolfBallTracker
//
//  Created by Łukasz Łazarecki on 25/11/2025.
//

import simd
import Foundation

@inline(__always)
func rotateVector(_ v: simd_float3, by q: simd_quatf) -> simd_float3 {
    // simd_quatf stores the quaternion as (imag.xyz, real)
    let qv = q.imag               // simd_float3
    let qw = q.real               // scalar

    // Same rotation formula as the shader:
    // v' = v + 2*qv × (qv × v + qw*v)
    return v + 2.0 * simd_cross(qv, simd_cross(qv, v) + qw * v)
}

@inline(__always)
func makeCameraRay(pixel: simd_float2,
                    frameSize: simd_float2,
                    verticalFOV: Float) -> simd_float3 {

    let aspect = frameSize.x / frameSize.y
    let halfH  = tan(verticalFOV * 0.5)
    let halfW  = halfH * aspect

    // pixel → NDC (-1..1)
    let ndc = simd_float2(
        (pixel.x / frameSize.x) * 2 - 1,
        (pixel.y / frameSize.y) * 2 - 1
    )

    // NDC → camera ray (note the Y flip)
    let pCam = simd_float3(
        ndc.x * halfW,
       -ndc.y * halfH,
        1.0
    )

    return simd_normalize(pCam)
}

// MARK: - Project world-space ray back to screen-space pixel
@inline(__always)
func projectToScreen(ray dir: simd_float3,
                     frameSize: simd_float2,
                     verticalFOV: Float) -> simd_float2 {

    let aspect = frameSize.x / frameSize.y
    let halfH  = tan(verticalFOV * 0.5)
    let halfW  = halfH * aspect

    let dz = dir.z
    if abs(dz) < 1e-6 {
        return simd_float2(frameSize.x * 0.5, frameSize.y * 0.5) // fallback
    }

    // intersect with plane z=1
    let t = 1.0 / dz
    let hit = dir * t
    let xPlane = hit.x
    let yPlane = hit.y

    // plane → NDC
    let ndcOut = simd_float2(
        xPlane / halfW,
        yPlane / halfH
    )

    // NDC → pixel (re-flip Y)
    return simd_float2(
        (ndcOut.x * 0.5 + 0.5) * frameSize.x,
        (-ndcOut.y * 0.5 + 0.5) * frameSize.y
    )
}

public func flipRoll(_ q: simd_quatf) -> simd_quatf {
    // Camera forward axis (Z+)
    let axis = simd_float3(0, 0, 1)

    let qv = q.imag
    let qw = q.real

    // Project quaternion vector part onto Z axis → twist
    let proj = axis * simd_dot(qv, axis)

    var twist = simd_quatf(real: qw, imag: proj)
    twist = simd_normalize(twist)

    // twist inverse
    let twistInv = simd_quatf(real: twist.real,
                              imag: -twist.imag)

    // swing = q * twistInv
    let swing = q * twistInv

    // Flipped twist is simply twistInv (inverse of twist)
    let twistFlipped = twistInv

    // Recompose
    let result = swing * twistFlipped

    return simd_normalize(result)
}

public func rotatedPixelPosition(pixel neutralPixel: CGPoint,
                                 frameSize: CGSize,
                                 verticalFOV: Float,
                                 rotation q: simd_quatf) -> CGPoint {

    // Convert to simd types for internal math
    let neutralSimd = simd_float2(Float(neutralPixel.x), Float(neutralPixel.y))
    let sizeSimd = simd_float2(Float(frameSize.width), Float(frameSize.height))

    // Use existing SIMD-based pipeline
    let rayCam = makeCameraRay(pixel: neutralSimd,
                               frameSize: sizeSimd,
                               verticalFOV: verticalFOV)

    let rayWorld = rotateVector(rayCam, by: q)

    let projected = projectToScreen(ray: rayWorld,
                                    frameSize: sizeSimd,
                                    verticalFOV: verticalFOV)

    // Back to CGPoint
    return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
}


public func neutralPixelPosition(pixel rotatedPixel: CGPoint,
                                 frameSize: CGSize,
                                 verticalFOV: Float,
                                 rotation q: simd_quatf) -> CGPoint {

    // Convert to simd types
    let rotatedSimd = simd_float2(Float(rotatedPixel.x), Float(rotatedPixel.y))
    let sizeSimd = simd_float2(Float(frameSize.width), Float(frameSize.height))

    let qInv = q.inverse

    // SIMD math as before
    let rayRotated = makeCameraRay(pixel: rotatedSimd,
                                   frameSize: sizeSimd,
                                   verticalFOV: verticalFOV)

    let rayNeutral = rotateVector(rayRotated, by: qInv)

    let projected = projectToScreen(ray: rayNeutral,
                                    frameSize: sizeSimd,
                                    verticalFOV: verticalFOV)

    // Convert back to CGPoint
    return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
}

public extension Vector2D {
    func rotateViewInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(x: self.x, y: self.y) }
        
        let result = rotatedPixelPosition(
            pixel: CGPoint(x: CGFloat(self.x), y: CGFloat(self.y)),
            frameSize: CGSize(width: CGFloat(viewportSize.width), height: CGFloat(viewportSize.height)),
            verticalFOV: Float(verticalFOV),
            rotation: cameraRotation)
        
        return Self(x: Self.Scalar(result.x), y: Self.Scalar(result.y))
    }
    
    func unrotateViewInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(x: self.x, y: self.y) }

        let result = neutralPixelPosition(
            pixel: CGPoint(x: CGFloat(self.x), y: CGFloat(self.y)),
            frameSize: CGSize(width: CGFloat(viewportSize.width), height: CGFloat(viewportSize.height)),
            verticalFOV: Float(verticalFOV),
            rotation: cameraRotation)
        
        return Self(x: Self.Scalar(result.x), y: Self.Scalar(result.y))
    }
    
    func rotateNormalizedInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(x: self.x, y: self.y) }

        return self
            .fromNormalizedToView(parentSize: viewportSize)
            .rotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
    }
    
    func unrotateNormalizedInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(x: self.x, y: self.y) }

        return self
            .fromNormalizedToView(parentSize: viewportSize)
            .unrotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
    }
    
    func rotateImageInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(x: self.x, y: self.y) }

        return self
            .fromImageToNormalized(imageSize: viewportSize)
            .fromNormalizedToView(parentSize: viewportSize)
            .rotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
            .fromNormalizedToImage(imageSize: viewportSize)
    }

    func unrotateImageInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(x: self.x, y: self.y) }

        return self
            .fromImageToNormalized(imageSize: viewportSize)
            .fromNormalizedToView(parentSize: viewportSize)
            .unrotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
            .fromNormalizedToImage(imageSize: viewportSize)
    }
}

public extension Rect2D {
    func rotateViewInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(origin: self.origin, size: self.size) }

        let center = self.center.rotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
        
        return Self(origin: Point(x: center.x - self.width / 2.0, y: center.y - self.height / 2.0), size: self.size)
    }
    
    func unrotateViewInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(origin: self.origin, size: self.size) }

        let center = self.center.unrotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
        
        return Self(origin: Point(x: center.x - self.width / 2.0, y: center.y - self.height / 2.0), size: self.size)
    }
    
    func rotateNormalizedInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(origin: self.origin, size: self.size) }

        return self
            .fromNormalizedToView(parentSize: viewportSize)
            .rotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
    }
    
    func unrotateNormalizedInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(origin: self.origin, size: self.size) }

        return self
            .fromNormalizedToView(parentSize: viewportSize)
            .unrotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
    }
    
    func rotateImageInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(origin: self.origin, size: self.size) }

        return self
            .fromImageToNormalized(imageSize: viewportSize)
            .fromNormalizedToView(parentSize: viewportSize)
            .rotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
            .fromNormalizedToImage(imageSize: viewportSize)
    }

    func unrotateImageInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(origin: self.origin, size: self.size) }

        return self
            .fromImageToNormalized(imageSize: viewportSize)
            .fromNormalizedToView(parentSize: viewportSize)
            .unrotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
            .fromNormalizedToImage(imageSize: viewportSize)
    }
}

public extension Polygon2D {
    func rotateViewInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(points: self.points) }

        let points = self.points.map { p in p.rotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation) }
        
        return Self(points: points)
    }
    
    func unrotateViewInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(points: self.points) }

        let points = self.points.map { p in p.unrotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation) }
        
        return Self(points: points)
    }

    func rotateNormalizedInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(points: self.points) }

        return self
            .fromNormalizedToView(parentSize: viewportSize)
            .rotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
    }
    
    func unrotateNormalizedInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(points: self.points) }

        return self
            .fromNormalizedToView(parentSize: viewportSize)
            .unrotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
    }
    
    func rotateImageInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(points: self.points) }

        return self
            .fromImageToNormalized(imageSize: viewportSize)
            .fromNormalizedToView(parentSize: viewportSize)
            .rotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
            .fromNormalizedToImage(imageSize: viewportSize)
    }

    func unrotateImageInPerspective<Size2DType: Size2D>(viewportSize:Size2DType, verticalFOV:Scalar, cameraRotation:simd_quatf) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        guard verticalFOV.isFinite else { return Self(points: self.points) }

        return self
            .fromImageToNormalized(imageSize: viewportSize)
            .fromNormalizedToView(parentSize: viewportSize)
            .unrotateViewInPerspective(viewportSize: viewportSize, verticalFOV: verticalFOV, cameraRotation: cameraRotation)
            .fromViewToNormalized(parentSize: viewportSize)
            .fromNormalizedToImage(imageSize: viewportSize)
    }
}
