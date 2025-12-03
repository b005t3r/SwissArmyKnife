//
//  File.swift
//  GolfBallTracker
//
//  Created by Łukasz Łazarecki on 26/06/2025.
//

import Foundation

import Vision

public protocol Size2D {
    associatedtype Scalar: BinaryFloatingPoint
    var width: Scalar { get set }
    var height: Scalar { get set }
    
    init(width: Scalar, height: Scalar)
}

extension CGSize: Size2D {
    public typealias Scalar = CGFloat
}

public extension Size2D where Scalar: CustomStringConvertible {
    var description: String {
        return "(width: \(width), height: \(height))"
    }
}

public extension Size2D {
    static func == (left: Self, right: Self) -> Bool {
        return (left.width == right.width) && (left.height == right.height)
    }
}

public extension Size2D {
    static func + (left: Self, right: Self) -> Self {
        return Self(width: left.width + right.width, height: left.height + right.height)
    }

    static func - (left: Self, right: Self) -> Self {
        return Self(width: left.width - right.width, height: left.height - right.height)
    }

    static func += (left: inout Self, right: Self) {
        left = left + right
    }

    static func -= (left: inout Self, right: Self) {
        left = left - right
    }
}

public extension Size2D {
    static prefix func - (size: Self) -> Self {
        return Self(width: -size.width, height: -size.height)
    }
}

infix operator * : MultiplicationPrecedence
infix operator / : MultiplicationPrecedence
infix operator • : MultiplicationPrecedence

public extension Size2D {
    static var invalid: Self {
        return Self(width: .nan, height: .nan)
    }
    
    var isValid:Bool {
        return self.width.isFinite && self.height.isFinite
    }
    
    static func * (left: Scalar, right: Self) -> Self {
        return Self(width: right.width * left, height: right.height * left)
    }
    
    static func * (left: Self, right: Scalar) -> Self {
        return Self(width: left.width * right, height: left.height * right)
    }
    
    static func / (left: Self, right: Scalar) -> Self {
        guard right != 0 else { fatalError("Division by zero") }
        return Self(width: left.width / right, height: left.height / right)
    }
    
    static func /= (left: inout Self, right: Scalar) -> Self {
        guard right != 0 else { fatalError("Division by zero") }
        return Self(width: left.width / right, height: left.height / right)
    }
    
    static func *= (left: inout Self, right: Scalar) {
        left = left * right
    }
    
    var area: Scalar {
        return width * height
    }
}

public extension Size2D {
    func fromNormalizedToView<Size2DType: Size2D>(parentSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        return fromNormalizedToImage(imageSize: parentSize)
    }
    
    func fromNormalizedToImage<Size2DType: Size2D>(imageSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
//        let p = VNImagePointForNormalizedPoint(
//            CGPoint(x: CGFloat(self.width), y: CGFloat(self.height)),
//            Int(imageSize.width),
//            Int(imageSize.height)
//        )
//        
//        return Self(width: Scalar(p.x), height: Scalar(imageSize.height) - Scalar(p.y))

        return Self(width: width * Scalar(imageSize.width), height: height * Scalar(imageSize.height))
    }
    
    func fromViewToNormalized<Size2DType: Size2D>(parentSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        return fromImageToNormalized(imageSize: parentSize)
    }
    
    func fromImageToNormalized<Size2DType: Size2D>(imageSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
//        let p = VNNormalizedPointForImagePoint(
//            CGPoint(x: CGFloat(self.width), y: CGFloat(self.height)),
//            Int(imageSize.width),
//            Int(imageSize.height)
//        )
//        
//        return Self(width: Scalar(p.x), height: Scalar(p.y))

        return Self(width: width / Scalar(imageSize.width), height: height / Scalar(imageSize.height))
    }
}
