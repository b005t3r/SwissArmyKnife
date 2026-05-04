//
//  File.swift
//  GolfBallTracker
//
//  Created by Łukasz Łazarecki on 26/06/2025.
//

import Foundation

import Vision

public protocol Vector2D {
    associatedtype Scalar: BinaryFloatingPoint
    var x: Scalar { get set }
    var y: Scalar { get set }
    
    init(x: Scalar, y: Scalar)
}

extension CGPoint: Vector2D {
    public typealias Scalar = CGFloat
}

public extension Vector2D where Scalar: CustomStringConvertible {
    var description: String {
        return "(x: \(x), y: \(y))"
    }
}

public extension Vector2D {
    static func == (left: Self, right: Self) -> Bool {
        return (left.x == right.x) && (left.y == right.y)
    }
}

public extension Vector2D {
    // Vector addition
    static func + (left: Self, right: Self) -> Self {
        return Self(x: left.x + right.x, y: left.y + right.y)
    }

    // Vector subtraction
    static func - (left: Self, right: Self) -> Self {
        return Self(x: left.x - right.x, y: left.y - right.y)
    }

    // Vector addition assignment
    static func += (left: inout Self, right: Self) {
        left = left + right
    }

    // Vector subtraction assignment
    static func -= (left: inout Self, right: Self) {
        left = left - right
    }
}

public extension Vector2D {
    // Vector negation
    static prefix func - (vector: Self) -> Self {
        return Self(x: -vector.x, y: -vector.y)
    }
}

infix operator * : MultiplicationPrecedence
infix operator / : MultiplicationPrecedence
infix operator • : MultiplicationPrecedence

public extension Vector2D {
    static var invalid: Self {
        return Self(x: .nan, y: .nan)
    }
    
    var isValid:Bool {
        return self.x.isFinite && self.y.isFinite
    }
    
    // Scalar-vector multiplication
    static func * (left: Scalar, right: Self) -> Self {
        return Self(x: right.x * left, y: right.y * left)
    }
    
    static func * (left: Self, right: Scalar) -> Self {
        return Self(x: left.x * right, y: left.y * right)
    }
    
    // Vector-scalar division
    static func / (left: Self, right: Scalar) -> Self {
        guard right != 0 else { fatalError("Division by zero") }
        return Self(x: left.x / right, y: left.y / right)
    }
    
    // Vector-scalar division assignment
    static func /= (left: inout Self, right: Scalar) -> Self {
        guard right != 0 else { fatalError("Division by zero") }
        return Self(x: left.x / right, y: left.y / right)
    }
    
    // Scalar-vector multiplication assignment
    static func *= (left: inout Self, right: Scalar) {
        left = left * right
    }

    // Vector magnitude (length)
    var magnitude: Scalar {
        return sqrt(x*x + y*y)
    }
    
    var magnitudeSquared: Scalar {
        return x*x + y*y
    }
    
    // Distance between two vectors
    func distance(to vector: Self) -> Scalar {
        return (self - vector).magnitude
    }
    
    func distanceSquared(to vector: Self) -> Scalar {
        return (self - vector).magnitudeSquared
    }
    
    func distance(toSegment a: Self, b: Self) -> Scalar {
        let ab = Self(x: b.x - a.x, y: b.y - a.y)
        let ap = Self(x: self.x - a.x, y: self.y - a.y)
        
        let abLengthSquared = ab.x * ab.x + ab.y * ab.y
        if abLengthSquared == 0 {
            // a and b are the same point
            return Scalar(hypot(Double(self.x - a.x), Double(self.y - a.y)))
        }
        
        let t = max(0.0, min(1.0, (ap.x * ab.x + ap.y * ab.y) / abLengthSquared))
        let projection = Self(x: a.x + t * ab.x, y: a.y + t * ab.y)
        
        return Scalar(hypot(Double(self.x - projection.x), Double(self.y - projection.y)))
    }
    
    // Vector normalization
    var normalized: Self {
        return magnitude != 0 ? Self(x: x / magnitude, y: y / magnitude) : Self(x: 0.0, y: 0.0)
    }
    
    // Dot product of two vectors
    static func • (left: Self, right: Self) -> Scalar {
        return left.x * right.x + left.y * right.y
    }
    
    func rotated(by angle: Scalar, around point: Self = Self(x: 0.0, y:0.0)) -> Self {
        let dx = self.x - point.x
        let dy = self.y - point.y
        let cosA = Scalar(cos(Double(angle)))
        let sinA = Scalar(sin(Double(angle)))
        
        let rotatedX = dx * cosA - dy * sinA + point.x
        let rotatedY = dx * sinA + dy * cosA + point.y
        
        return Self(x: rotatedX, y: rotatedY)
    }
}

public extension Vector2D {
    // 1.0 = aligned, -1.0 - opposite, 0.0 perpendicular
    func alignment(with vector:Self) -> Scalar {
        return self.normalized • vector.normalized
    }

    // Angle between two vectors
    // θ = acos(AB)
    func angle(to vector: Self) -> Scalar {
        let dot = self.normalized • vector.normalized
        let clampedDot = clamp(dot, minValue: Scalar(-1), maxValue: Scalar(1))

        // Convert to Double safely using Double.init(_:) that takes a generic FloatingPoint
        let angleInRadians = acos(Double(clampedDot))
        return Scalar(angleInRadians)
    }
    
    static func linesIntersect(_ p1: Self, _ p2: Self, _ p3: Self, _ p4: Self) -> Bool {
        func ccw(_ a: Self, _ b: Self, _ c: Self) -> Bool {
            return (c.y - a.y) * (b.x - a.x) > (b.y - a.y) * (c.x - a.x)
        }
        
        return (ccw(p1, p3, p4) != ccw(p2, p3, p4)) && (ccw(p1, p2, p3) != ccw(p1, p2, p4))
    }
}

public extension Vector2D {
    func fromNormalizedToView<Size2DType: Size2D>(parentSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        let p = VNImagePointForNormalizedPoint(
            CGPoint(x: CGFloat(self.x), y: CGFloat(self.y)),
            Int(parentSize.width),
            Int(parentSize.height)
        )
        
        return Self(x: Scalar(p.x), y: Scalar(parentSize.height) - Scalar(p.y))
    }
    
    func fromNormalizedToImage<Size2DType: Size2D>(imageSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        let p = VNImagePointForNormalizedPoint(
            CGPoint(x: CGFloat(self.x), y: CGFloat(self.y)),
            Int(imageSize.width),
            Int(imageSize.height)
        )
        
        return Self(x: Scalar(p.x), y: Scalar(p.y))
    }
    
    func fromViewToNormalized<Size2DType: Size2D>(parentSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        let p = VNNormalizedPointForImagePoint(
            CGPoint(x: CGFloat(self.x), y: CGFloat(Scalar(parentSize.height) - self.y)),
            Int(parentSize.width),
            Int(parentSize.height)
        )

        return Self(x: Scalar(p.x), y: Scalar(p.y))
    }
    
    func fromImageToNormalized<Size2DType: Size2D>(imageSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        let p = VNNormalizedPointForImagePoint(
            CGPoint(x: CGFloat(self.x), y: CGFloat(self.y)),
            Int(imageSize.width),
            Int(imageSize.height)
        )
        
        return Self(x: Scalar(p.x), y: Scalar(p.y))
    }
}


public extension Vector2D {
    static func lerp(_ a: Self, _ b: Self, _ t: Scalar) -> Self {
        return a + (b - a) * t
    }
    
    func lerp(_ p: Self, _ t: Scalar) -> Self {
        return Self.lerp(self, p, t)
    }
}
