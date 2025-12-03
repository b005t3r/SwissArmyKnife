//
//  File.swift
//  GolfBallTracker
//
//  Created by Łukasz Łazarecki on 26/06/2025.
//

import Foundation

public func clamp<T>(_ value: T, minValue: T, maxValue: T) -> T where T : Comparable {
    return min(max(value, minValue), maxValue)
}

public func lerp<T>(ratio: T, startValue: T, endValue: T) -> T where T : BinaryFloatingPoint {
    return startValue + (endValue - startValue) * ratio
}
