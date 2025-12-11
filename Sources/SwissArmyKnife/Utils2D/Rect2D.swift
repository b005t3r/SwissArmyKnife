//
//  File.swift
//  GolfBallTracker
//
//  Created by Łukasz Łazarecki on 26/06/2025.
//

import Foundation

public protocol Rect2D {
    associatedtype Scalar: BinaryFloatingPoint
    associatedtype Point: Vector2D where Point.Scalar == Scalar
    associatedtype Size: Size2D where Size.Scalar == Scalar

    var origin: Point { get set }
    var size: Size { get set }
    
    var minX: Scalar { get }
    var midX: Scalar { get }
    var maxX: Scalar { get }
    var minY: Scalar { get }
    var midY: Scalar { get }
    var maxY: Scalar { get }
    var width: Scalar { get }
    var height: Scalar { get }
    
    init(origin: Point, size: Size)
}

extension CGRect: Rect2D {
    public typealias Scalar = CGFloat
}

public extension Rect2D where Scalar: CustomStringConvertible {
    var description: String {
        return "(x: \(origin.x), y: \(origin.y)), width: \(size.width), height: \(size.height)"
    }
}

public extension Rect2D {
    static func == (left: Self, right: Self) -> Bool {
        return (left.origin == right.origin) && (left.size == right.size)
    }
}

public extension Rect2D {
    static var invalid: Self {
        return Self(origin: Point.invalid, size: Size.invalid)
    }
    
    var isValid:Bool {
        return self.origin.isValid && self.size.isValid
    }
    
    var center:Point {
        Point(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }
    
    var corners:[Point] {
        return [
            Point(x: self.minX, y: self.minY),
            Point(x: self.maxX, y: self.minY),
            Point(x: self.maxX, y: self.maxY),
            Point(x: self.minX, y: self.maxY)
        ]
    }
}

public extension Rect2D {
    func fromNormalizedToView<Size2DType: Size2D>(parentSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        let imageRect = fromNormalizedToImage(imageSize: parentSize)
        let newOrigin = Point(x: imageRect.origin.x, y: Scalar(parentSize.height) - (imageRect.origin.y + imageRect.size.height))
                             
        return Self(origin: newOrigin, size: imageRect.size)
    }
    
    func fromNormalizedToImage<Size2DType: Size2D>(imageSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        return Self(origin: self.origin.fromNormalizedToImage(imageSize: imageSize), size: self.size.fromNormalizedToImage(imageSize: imageSize))
    }
    
    func fromViewToNormalized<Size2DType: Size2D>(parentSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        let newOrigin = Point(x: self.origin.x, y: Scalar(parentSize.height) - (self.origin.y + self.size.height))
        let imageRect = Self(origin: newOrigin, size: self.size)
        
        return imageRect.fromImageToNormalized(imageSize: parentSize)
    }
    
    func fromImageToNormalized<Size2DType: Size2D>(imageSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        return Self(origin: self.origin.fromImageToNormalized(imageSize: imageSize), size: self.size.fromImageToNormalized(imageSize: imageSize))
    }
}

public extension Rect2D {
    func resizedAroundCenter(by scale: Scalar) -> Self {
        return Self(
            origin: Point(x: self.origin.x - self.size.width * 0.5, y: self.origin.y - self.size.height * 0.5),
            size: self.size * 2.0)
    }
}
