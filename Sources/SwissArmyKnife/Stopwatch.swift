//
//  Stopwatch.swift
//  GPUImageTest
//
//  Created by Łukasz Łazarecki on 19/11/2025.
//

import Foundation

public final class Stopwatch {
    private var startTime: DispatchTime = .distantFuture

    private var tickCount:Int
    
    public private(set) var lastTickDuration: UInt64 = 0
    
    private var totalTickDuration: UInt64 = 0
    private var totalTicks: UInt64 = 0
    public private(set) var averageTickDuration: UInt64 = 0
    
    public init(tickCount:Int) {
        self.tickCount = tickCount
    }

    public func start() {
        startTime = DispatchTime.now()
    }
    
    public func stop() {
        let now = DispatchTime.now()
        lastTickDuration = now.uptimeNanoseconds - startTime.uptimeNanoseconds
        
        totalTickDuration += lastTickDuration
        totalTicks += 1
        
        if totalTicks == tickCount {
            averageTickDuration = totalTickDuration / totalTicks
            
            totalTicks = 0
            totalTickDuration = 0
        }
    }
}
