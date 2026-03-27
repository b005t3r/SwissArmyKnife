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
    // returns the first index where predicate is false
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
    private struct SplineData {
        let timestamp:CMTime
        let spline:[(a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint)]
    }
    
    private var interpolationDuration:TimeInterval
    private var sortedSplineData:[SplineData] = []
    
    public init(interpolationDuration: TimeInterval = 0.1) {
        self.interpolationDuration = interpolationDuration
    }
    
    public func addSpline(timestamp:CMTime, spline:[(a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint)]) {
        let spline = Array(spline)
        
        guard sortedSplineData.isEmpty || sortedSplineData.first!.spline.count == spline.count else {
            fatalError("all added splines must have the same number of segments, current: \(sortedSplineData.first!.spline.count), added: \(spline.count)")
        }
        
        // find first index where existing timestamp is >= new timestamp
        let insertionIndex = sortedSplineData.partitioningIndex { $0.timestamp < timestamp }
        
        // if equal timestamp exists at that position, overwrite; otherwise insert
        if insertionIndex < sortedSplineData.count && sortedSplineData[insertionIndex].timestamp == timestamp {
            sortedSplineData[insertionIndex] = SplineData(timestamp: timestamp, spline: spline)
        } else {
            sortedSplineData.insert(SplineData(timestamp: timestamp, spline: spline), at: insertionIndex)
        }
    }
    
    public func removeAll() {
        sortedSplineData.removeAll()
    }
    
    public func interpolatedSpline(timestamp: CMTime, removeOlder: Bool = false) -> [(a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint)] {
        guard !sortedSplineData.isEmpty else { return [] }
        if sortedSplineData.count == 1 { return sortedSplineData[0].spline }
        
        @inline(__always)
        func lerp(_ p0: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint { p0 + (p1 - p0) * t }
        
        @inline(__always)
        func lerpSpline(
            _ s0: [(a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint)],
            _ s1: [(a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint)],
            _ t: CGFloat
        ) -> [(a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint)] {
            zip(s0, s1).map { seg0, seg1 in
                (
                    a: lerp(seg0.a, seg1.a, t),
                    b: lerp(seg0.b, seg1.b, t),
                    c: lerp(seg0.c, seg1.c, t),
                    d: lerp(seg0.d, seg1.d, t)
                )
            }
        }
        
        // find the newest spline with timestamp <= now (ignore future splines)
        let firstGreaterIndex = sortedSplineData.partitioningIndex { $0.timestamp <= timestamp }
        let k = max(0, min(sortedSplineData.count - 1, firstGreaterIndex - 1))
        
        func interpolated(at time: CMTime, upTo index: Int) -> [(a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint)] {
            if index <= 0 { return sortedSplineData[0].spline }
            
            let to = sortedSplineData[index]
            let dt = (time - to.timestamp).seconds
            
            if dt >= interpolationDuration {
                return to.spline
            }
            
            let from = interpolated(at: to.timestamp, upTo: index - 1)
            let t = CGFloat(max(0.0, min(1.0, dt / interpolationDuration)))
            
            return lerpSpline(from, to.spline, t)
        }
        
        if firstGreaterIndex == 0 && sortedSplineData[0].timestamp > timestamp {
            return sortedSplineData[0].spline
        }
        
        let result = interpolated(at: timestamp, upTo: k)
        
        if removeOlder {
            let timescale = timestamp.timescale == 0 ? CMTimeScale(600) : timestamp.timescale
            let cutoffTime = timestamp - CMTime(seconds: interpolationDuration, preferredTimescale: timescale)
            
            let pruneCount = sortedSplineData.partitioningIndex { $0.timestamp < cutoffTime }
            if pruneCount > 0 { sortedSplineData.removeFirst(pruneCount) }
        }
        
        return Array(result)
    }
}
