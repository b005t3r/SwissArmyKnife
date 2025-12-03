//
//  DeviceRotationTracker.swift
//  GPUImageTest
//
//  Created by Łukasz Łazarecki on 24/10/2025.
//

import CoreMotion
import AVFoundation
import simd

public struct GyroData {
    public let attitude:CMAttitude
    public let timestamp:TimeInterval
    
    public func relativeTo(_ other:GyroData) -> GyroData {
        let rel = attitude.copy() as! CMAttitude
        rel.multiply(byInverseOf: other.attitude)
        
        return GyroData(attitude: rel, timestamp: timestamp)
    }
    
    public var simfQuaternion: simd_quatf {
        var q = attitude.simfQuaternion
        q.vector.x *= -1.0
        q.vector.y *= -1.0

        return q
    }
}

public extension CMAttitude {
    public var simfQuaternion: simd_quatf {
        let q = quaternion
        
        if abs(q.x) < 0.00001 && abs(q.y) < 0.00001 && abs(q.z) < 0.00001 && abs(q.w) < 0.00001 {
            return simd_quatf(real: 1.0, imag: .zero)
        }
        
        return simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
    }
}

public class DeviceRotationTracker {
    private var motionManager:CMMotionManager? = nil
    
    private var reference:GyroData? = nil
    public private(set) var gyroData:[GyroData] = []
    
    private var gyroDataQueue = DispatchQueue(label: "device-rotation-tracker-queue")
    
    public init() {
    }
    
    deinit {
        stopTracking()
    }
    
    public func startTracking(updateInterval:TimeInterval = 1.0 / 120.0, gyroDataMaxCount:Int = 1000) {
        guard motionManager == nil else { return }
        
        motionManager = CMMotionManager()
        
        motionManager?.deviceMotionUpdateInterval = updateInterval
        motionManager?.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: OperationQueue()) { motion, error in
            guard error == nil, let motion = motion else {
                print(error as Any)
                return
            }
            
            let data = GyroData(
                attitude: motion.attitude.copy() as! CMAttitude,
                timestamp: motion.timestamp)
            
            self.gyroDataQueue.async(flags: .barrier) {
                self.gyroData.append(data)
                
                if self.gyroData.count > gyroDataMaxCount {
                    self.gyroData.removeFirst(self.gyroData.count - gyroDataMaxCount)
                }
            }
        }
    }
    
    public func stopTracking() {
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
    }
    
    public func clearCachedData() {
        self.gyroDataQueue.async {
            self.gyroData.removeAll()
        }
    }

    public func getCachedData() -> [(q: simd_quatf, t: TimeInterval)] {
        self.gyroDataQueue.sync {
            return self.gyroData.map { (data) -> (q: simd_quatf, t: TimeInterval) in
                return (q: data.simfQuaternion, t: data.timestamp)
            }
        }
    }
    
    public func setReferenceTime(timestamp:CMTime) {
        if !timestamp.isValid {
            reference = nil
            
            return
        }
        
        reference = findClosestFrame(timestamp: timestamp)
    }
    
    public func getRelativeRotation(timestamp:CMTime) -> GyroData? {
        guard let reference = reference else { return nil }
        guard let currentData = findClosestFrame(timestamp: timestamp) else { return nil }
        
        return currentData.relativeTo(reference)
    }
    
    private func findClosestFrame(timestamp:CMTime) -> GyroData? {
        return findClosestFrame(seconds: timestamp.seconds)
    }
    
    private func findClosestFrame(seconds:TimeInterval) -> GyroData? {
        gyroDataQueue.sync {
            return !self.gyroData.isEmpty ? self.gyroData.min { left, right in abs(left.timestamp - seconds) < abs(right.timestamp - seconds) } : nil
        }
    }
}
