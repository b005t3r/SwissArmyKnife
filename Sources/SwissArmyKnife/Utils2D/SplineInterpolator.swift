//
//  SplineTweener.swift
//  GolfBallTracker
//
//  Created by Łukasz Łazarecki on 27/02/2026.
//

import Foundation
import CoreMedia
import SwissArmyKnife

private extension Array {
    func partitioningIndex(_ predicate: (Element) -> Bool) -> Int {
        var low = 0
        var high = count
        
        while low < high {
            let mid = (low + high) / 2
            if predicate(self[mid]) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        return low
    }
}

public class SplineInterpolator {
    public typealias SplineSegment = (a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint)
    
    private struct SplineData {
        let id: Int
        let timestamp: CMTime
        let spline: [SplineSegment]
        let points: [CGPoint]
    }
    
    private var interpolationDuration: TimeInterval
    private var sortedSplineData: [SplineData] = []
    private var lastAddedID: Int?
    
    public init(interpolationDuration: TimeInterval = 0.1) {
        self.interpolationDuration = interpolationDuration
    }
    
    public func addSpline(
        id: Int,
        timestamp: CMTime,
        spline: [SplineSegment],
        points: [CGPoint]
    ) {
        if lastAddedID == id {
            return
        }
        
        guard sortedSplineData.isEmpty || sortedSplineData.first!.spline.count == spline.count else {
            fatalError("all added splines must have the same number of segments, current: \(sortedSplineData.first!.spline.count), added: \(spline.count)")
        }
        
        lastAddedID = id
        
        let insertionIndex = sortedSplineData.partitioningIndex { $0.timestamp < timestamp }
        let data = SplineData(id: id, timestamp: timestamp, spline: spline, points: points)
        
        if insertionIndex < sortedSplineData.count && sortedSplineData[insertionIndex].timestamp == timestamp {
            sortedSplineData[insertionIndex] = data
        } else {
            sortedSplineData.insert(data, at: insertionIndex)
        }
    }
    
    public func removeAll() {
        sortedSplineData.removeAll()
        lastAddedID = nil
    }
    
    public func interpolatedSpline(
        timestamp: CMTime,
        removeOlder: Bool = false
    ) -> (spline: [SplineSegment], points: [CGPoint]) {
        guard !sortedSplineData.isEmpty else { return ([], []) }
        
        if sortedSplineData.count == 1 {
            let data = sortedSplineData[0]
            return (data.spline, data.points)
        }
        
        @inline(__always)
        func lerp(_ v0: CGFloat, _ v1: CGFloat, _ t: CGFloat) -> CGFloat {
            v0 + (v1 - v0) * t
        }
        
        @inline(__always)
        func lerp(_ p0: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
            p0 + (p1 - p0) * t
        }
        
        func lerpSpline(
            _ s0: [SplineSegment],
            _ s1: [SplineSegment],
            _ t: CGFloat
        ) -> [SplineSegment] {
            zip(s0, s1).map { seg0, seg1 in
                (
                    a: lerp(seg0.a, seg1.a, t),
                    b: lerp(seg0.b, seg1.b, t),
                    c: lerp(seg0.c, seg1.c, t),
                    d: lerp(seg0.d, seg1.d, t)
                )
            }
        }
        
        func resampledPoints(_ points: [CGPoint], count: Int) -> [CGPoint] {
            guard count > 0 else { return [] }
            guard !points.isEmpty else { return [] }
            guard points.count > 1 else { return Array(repeating: points[0], count: count) }
            guard count > 1 else { return [points[0]] }
            
            var result: [CGPoint] = []
            result.reserveCapacity(count)
            
            let sourceMaxIndex = CGFloat(points.count - 1)
            let targetMaxIndex = CGFloat(count - 1)
            
            for i in 0 ..< count {
                let sourcePosition = CGFloat(i) / targetMaxIndex * sourceMaxIndex
                let index0 = Int(floor(sourcePosition))
                let index1 = min(index0 + 1, points.count - 1)
                let t = sourcePosition - CGFloat(index0)
                
                result.append(lerp(points[index0], points[index1], t))
            }
            
            return result
        }
        
        func lerpPoints(_ p0: [CGPoint], _ p1: [CGPoint], _ t: CGFloat) -> [CGPoint] {
            let count0 = p0.count
            let count1 = p1.count
            
            guard count0 > 0 || count1 > 0 else { return [] }
            guard count0 > 0 else { return p1 }
            guard count1 > 0 else { return p0 }
            
            let interpolatedCount = max(
                1,
                Int(round(lerp(CGFloat(count0), CGFloat(count1), t)))
            )
            
            let r0 = resampledPoints(p0, count: interpolatedCount)
            let r1 = resampledPoints(p1, count: interpolatedCount)
            
            return zip(r0, r1).map { lerp($0, $1, t) }
        }
        
        func interpolated(
            at time: CMTime,
            upTo index: Int
        ) -> (spline: [SplineSegment], points: [CGPoint]) {
            if index <= 0 {
                let data = sortedSplineData[0]
                return (data.spline, data.points)
            }
            
            let to = sortedSplineData[index]
            let dt = (time - to.timestamp).seconds
            
            if dt >= interpolationDuration {
                return (to.spline, to.points)
            }
            
            let from = interpolated(at: to.timestamp, upTo: index - 1)
            let t = CGFloat(max(0.0, min(1.0, dt / interpolationDuration)))
            
            return (
                spline: lerpSpline(from.spline, to.spline, t),
                points: lerpPoints(from.points, to.points, t)
            )
        }
        
        let firstGreaterIndex = sortedSplineData.partitioningIndex { $0.timestamp <= timestamp }
        let k = max(0, min(sortedSplineData.count - 1, firstGreaterIndex - 1))
        
        if firstGreaterIndex == 0 && sortedSplineData[0].timestamp > timestamp {
            let data = sortedSplineData[0]
            return (data.spline, data.points)
        }
        
        let result = interpolated(at: timestamp, upTo: k)

        if removeOlder {
            let lastIndex = sortedSplineData.count - 1
            let last = sortedSplineData[lastIndex]

            if k == lastIndex && (timestamp - last.timestamp).seconds >= interpolationDuration {
                sortedSplineData.removeAll()
                sortedSplineData.append(last)
                return result
            }

            let timescale = timestamp.timescale == 0 ? CMTimeScale(600) : timestamp.timescale
            let cutoffTime = timestamp - CMTime(seconds: interpolationDuration, preferredTimescale: timescale)

            let firstKeepIndex = sortedSplineData.partitioningIndex { $0.timestamp < cutoffTime }

            if firstKeepIndex > 0 {
                let collapseIndex = min(firstKeepIndex, sortedSplineData.count - 1)
                let collapsed = interpolated(at: cutoffTime, upTo: collapseIndex)
                let collapsedID = sortedSplineData[collapseIndex].id

                sortedSplineData.removeFirst(firstKeepIndex)
                sortedSplineData.insert(
                    SplineData(
                        id: collapsedID,
                        timestamp: cutoffTime,
                        spline: collapsed.spline,
                        points: collapsed.points
                    ),
                    at: 0
                )
            }
        }

        return result
    }
}
