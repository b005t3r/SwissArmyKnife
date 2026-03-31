//
//  File.swift
//  GolfBallTracker
//
//  Created by Łukasz Łazarecki on 26/06/2025.
//

import Foundation

@inlinable
public func clamp<T>(_ value: T, minValue: T, maxValue: T) -> T where T : Comparable {
    return min(max(value, minValue), maxValue)
}

@inlinable
public func lerp<T>(ratio: T, startValue: T, endValue: T) -> T where T : BinaryFloatingPoint {
    return startValue + (endValue - startValue) * ratio
}

@inlinable
public func easeIn<T>(value: T, startValue: T = 0, endValue: T = 1, clampResult: Bool = false) -> T where T: BinaryFloatingPoint {
    let range = endValue - startValue
    guard range != 0 else { return startValue }
    
    var t = (value - startValue) / range
    if clampResult {
        t = clamp(t, minValue: 0, maxValue: 1)
    }
    
    let eased = t * t
    var result = startValue + eased * range
    
    if clampResult {
        result = clamp(result, minValue: startValue, maxValue: endValue)
    }

    return result
}

@inlinable
public func easeOut<T>(value: T, startValue: T = 0, endValue: T = 1, clampResult: Bool = false) -> T where T: BinaryFloatingPoint {
    let range = endValue - startValue
    guard range != 0 else { return startValue }
    
    var t = (value - startValue) / range
    if clampResult {
        t = clamp(t, minValue: 0, maxValue: 1)
    }
    
    let eased = 1 - (1 - t) * (1 - t)
    var result = startValue + eased * range
    
    if clampResult {
        result = clamp(result, minValue: startValue, maxValue: endValue)
    }

    return result
}

@inlinable
public func easeInOut<T>(value: T, startValue: T = 0, endValue: T = 1, clampResult: Bool = false) -> T where T: BinaryFloatingPoint {
    let range = endValue - startValue
    guard range != 0 else { return startValue }
    
    var t = (value - startValue) / range
    if clampResult {
        t = clamp(t, minValue: 0, maxValue: 1)
    }
    
    let eased: T
    if t < 0.5 {
        eased = 2 * t * t
    } else {
        eased = 1 - 2 * (1 - t) * (1 - t)
    }
    
    var result = startValue + eased * range
    
    if clampResult {
        result = clamp(result, minValue: startValue, maxValue: endValue)
    }
    
    return result
}

@inlinable
public func easeOutIn<T>(value: T, startValue: T = 0, endValue: T = 1, clampResult: Bool = false) -> T where T: BinaryFloatingPoint {
    let range = endValue - startValue
    guard range != 0 else { return startValue }

    var t = (value - startValue) / range
    if clampResult {
        t = clamp(t, minValue: 0, maxValue: 1)
    }

    let eased: T
    if t < 0.5 {
        let u = t * 2
        eased = (1 - (1 - u) * (1 - u)) / 2
    } else {
        let u = (t - 0.5) * 2
        eased = 0.5 + (u * u) / 2
    }

    var result = startValue + eased * range

    if clampResult {
        result = clamp(result, minValue: startValue, maxValue: endValue)
    }

    return result
}
