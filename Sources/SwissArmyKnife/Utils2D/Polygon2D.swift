//
//  File.swift
//  GolfBallTracker
//
//  Created by Łukasz Łazarecki on 04/08/2025.
//

import Foundation

public protocol Polygon2D {
    associatedtype Scalar: BinaryFloatingPoint
    associatedtype Point: Vector2D where Point.Scalar == Scalar
    associatedtype Size: Size2D where Size.Scalar == Scalar
    associatedtype Rect: Rect2D where Rect.Point == Point, Rect.Size == Size

    var points: [Point] { get set }
    
    init(points: [Point])
    init(rect: Rect)
    init(a: Point, b: Point, thickness: Scalar)
}

public struct CGPolygon {
    public init(rect: CGRect) {
        self.points = CGPolygon.convexHull(points: rect.corners)
    }
    
    public init(points: [CGPoint]) {
        self.points = CGPolygon.convexHull(points: points)
    }
    
    public init(a: CGPoint, b: CGPoint, thickness: CGFloat) {
        // Vector from a to b
        let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let length = d.magnitude
        
        guard length > 0 else {
            self.points = []
            return
        }
        
        // Perpendicular (normal) vector, normalized
        let n = CGPoint(x: -d.y, y: d.x).normalized
        
        // Half thickness offset
        let offsetX = n.x * thickness / 2
        let offsetY = n.y * thickness / 2
        
        // Construct the rectangle (4 points)
        let p1 = CGPoint(x: a.x + offsetX, y: a.y + offsetY)
        let p2 = CGPoint(x: a.x - offsetX, y: a.y - offsetY)
        let p3 = CGPoint(x: b.x - offsetX, y: b.y - offsetY)
        let p4 = CGPoint(x: b.x + offsetX, y: b.y + offsetY)
        
        self.points = CGPolygon.convexHull(points: [p1, p2, p3, p4])
    }
    
    public var points: [CGPoint]
}

extension CGPolygon: Polygon2D {
    public typealias Scalar = CGFloat
    public typealias Point = CGPoint
    public typealias Size = CGSize
    public typealias Rect = CGRect
}

public extension Polygon2D where Scalar: CustomStringConvertible {
    var description: String {
        return "(points: \(points)"
    }
}

public extension Polygon2D {
    func contains(point:Point) -> Bool {
        guard self.isValid else { return false }
        
        var inside = false
        var j = self.points.count - 1
        for i in 0..<self.points.count {
            let xi:Double = Double(self.points[i].x), yi:Double = Double(self.points[i].y)
            let xj:Double = Double(self.points[j].x), yj:Double = Double(self.points[j].y)
            
            let intersect = ((yi > Double(point.y)) != (yj > Double(point.y))) && (Double(point.x) < (xj - xi) * (Double(point.y) - yi) / (yj - yi + 0.0000001) + xi)
            
            if intersect { inside.toggle() }
            j = i
        }
        
        return inside
    }
    
    func contains(rect:Rect) -> Bool {
        for p in rect.corners {
            if !self.contains(point: p) {
                return false
            }
        }
        
        return true
    }
    
    func contains(polygon:Self) -> Bool {
        for p in polygon.points {
            if !self.contains(point: p) {
                return false
            }
        }
        
        return true
    }

    func intersects(rect:Rect) -> Bool {
        return intersects(polygon: Self(rect: rect))
    }
    
    func intersects(polygon:Self) -> Bool {
        guard self.isValid && polygon.isValid else { return false }
        
        // check if rect corner inside polygon
        for p in polygon.points {
            if contains(point: p) {
                return true
            }
        }
        
        let otherEdges = zip(polygon.points, polygon.points.dropFirst() + [polygon.points.first!])
        let selfEdges = zip(self.points, self.points.dropFirst() + [self.points.first!])
        
        // check if any edge intersects
        for (r1, r2) in otherEdges {
            for (p1, p2) in selfEdges {
                if Point.linesIntersect(r1, r2, p1, p2) {
                    return true
                }
            }
        }
        
        return false
    }
}

public extension Polygon2D {
    // convex hull using Graham Scan (returns points in CCW order)
    static func convexHull(points:[Point]) -> [Point] {
        guard points.count > 1 else { return points }
        
        let sortedPoints = points.sorted { p1, p2 in
            p1.x == p2.x ? p1.y < p2.y : p1.x < p2.x
        }
        
        func cross(_ o: Point, _ a: Point, _ b: Point) -> Scalar {
            return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        
        var lower: [Point] = []
        for p in sortedPoints {
            while lower.count >= 2 && cross(lower[lower.count-2], lower.last!, p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        
        var upper: [Point] = []
        for p in sortedPoints.reversed() {
            while upper.count >= 2 && cross(upper[upper.count-2], upper.last!, p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        
        // remove last because it's the starting point of the other half
        lower.removeLast()
        upper.removeLast()
        
        return lower + upper
    }
    
    static var empty: Self {
        return Self(points: [])
    }
    
    static var invalid: Self {
        return .empty
    }
    
    var isValid:Bool {
        return points.count >= 3
    }
}

public extension Polygon2D {
    func fromNormalizedToView<Size2DType: Size2D>(parentSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        return Self(points: self.points.map { p in p.fromNormalizedToView(parentSize: parentSize) })
    }
    
    func fromNormalizedToImage<Size2DType: Size2D>(imageSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        return Self(points: self.points.map { p in p.fromNormalizedToImage(imageSize: imageSize) })
    }
    
    func fromViewToNormalized<Size2DType: Size2D>(parentSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        return Self(points: self.points.map { p in p.fromViewToNormalized(parentSize: parentSize) })
    }
    
    func fromImageToNormalized<Size2DType: Size2D>(imageSize:Size2DType) -> Self where Size2DType.Scalar: BinaryFloatingPoint {
        return Self(points: self.points.map { p in p.fromImageToNormalized(imageSize: imageSize) })
    }
}
