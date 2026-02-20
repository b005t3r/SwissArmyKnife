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

public class VideoData: Codable {
    public static func loadFromJSON(url: URL) -> VideoData {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                positiveInfinity: "inf",
                negativeInfinity: "-inf",
                nan: "nan"
            )
            return try decoder.decode(VideoData.self, from: data)
        } catch {
            fatalError("VideoData.loadFromJSON failed for \(url): \(error)")
        }
    }

    public func saveAsJSON(url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.nonConformingFloatEncodingStrategy = .convertToString(
                positiveInfinity: "inf",
                negativeInfinity: "-inf",
                nan: "nan"
            )
            let data = try encoder.encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            fatalError("VideoData.saveAsJSON failed for \(url): \(error)")
        }
    }
    
    public let videoTimestamps: [CMTime]
    public let skippedTimestamps:[CMTime]
    public let gyro: [simd_quatf]
    public let gyroTimestamps: [TimeInterval]
    public let horizontalFOV: Float
    public let verticalFOV: Float
    public let shutterSpeed: Float

    public init(videoTimestamps: [CMTime],
                skippedTimestamps:[CMTime] = [],
         gyro: [simd_quatf],
         gyroTimestamps: [TimeInterval],
         horizontalFOV: Float,
         verticalFOV: Float,
         shutterSpeed: Float) {
        
        self.videoTimestamps = videoTimestamps
        self.skippedTimestamps = skippedTimestamps
        self.gyro = gyro
        self.gyroTimestamps = gyroTimestamps
        self.horizontalFOV = horizontalFOV
        self.verticalFOV = verticalFOV
        self.shutterSpeed = shutterSpeed
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case videoTimestamps
        case skippedTimestamps
        case gyro
        case gyroTimestamps
        case horizontalFOV
        case verticalFOV
        case shutterSpeed
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // CMTime -> [Double seconds]
        let timestampSeconds = try container.decode([Double].self, forKey: .videoTimestamps)
        self.videoTimestamps = timestampSeconds.map {
            CMTime(seconds: $0, preferredTimescale: 600)
        }

        // NEW: skippedTimestamps is optional for backwards compatibility
        let skippedSeconds = try container.decodeIfPresent([Double].self, forKey: .skippedTimestamps) ?? []
        self.skippedTimestamps = skippedSeconds.map {
            CMTime(seconds: $0, preferredTimescale: 600)
        }

        // simd_quatf -> [[Float]] as [x, y, z, w]
        let gyroComponents = try container.decode([[Float]].self, forKey: .gyro)
        self.gyro = gyroComponents.map { comps in
            precondition(comps.count == 4, "Invalid gyro quaternion component count")
            return simd_quatf(ix: comps[0], iy: comps[1], iz: comps[2], r: comps[3])
        }

        self.gyroTimestamps = try container.decode([TimeInterval].self, forKey: .gyroTimestamps)
        self.horizontalFOV = try container.decode(Float.self, forKey: .horizontalFOV)
        self.verticalFOV = try container.decode(Float.self, forKey: .verticalFOV)
        self.shutterSpeed = try container.decode(Float.self, forKey: .shutterSpeed)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // CMTime -> seconds
        try container.encode(videoTimestamps.map { $0.seconds }, forKey: .videoTimestamps)

        // NEW: skippedTimestamps -> seconds
        try container.encode(skippedTimestamps.map { $0.seconds }, forKey: .skippedTimestamps)

        // simd_quatf -> [x, y, z, w]
        let gyroComponents: [[Float]] = gyro.map { q in
            let imag = q.imag
            return [imag.x, imag.y, imag.z, q.real]
        }
        try container.encode(gyroComponents, forKey: .gyro)

        try container.encode(gyroTimestamps, forKey: .gyroTimestamps)
        try container.encode(horizontalFOV, forKey: .horizontalFOV)
        try container.encode(verticalFOV, forKey: .verticalFOV)
        try container.encode(shutterSpeed, forKey: .shutterSpeed)
    }
}

public class DeviceRotationTracker {
    #if os(iOS)
    private var motionManager:CMMotionManager? = nil
    #elseif os(macOS)
    private var data:VideoData? = nil
    #endif
    
    private var reference:simd_quatf = .init(real: 1.0, imag: .zero)
    private var gyroData:[GyroData] = []
    
    private var gyroDataQueue = DispatchQueue(label: "device-rotation-tracker-queue")
    
    public init() {
    }
    
    deinit {
        #if os(iOS)
        stopTracking()
        #endif
    }
    
#if os(iOS)
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
            
//            let now = CMClockGetTime(CMClockGetHostTimeClock())
//
//            print("delay: \((now.seconds - motion.timestamp) * 1000)ms")
            
            self.gyroDataQueue.sync {
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
#endif

#if os(macOS)
    public func loadTrackingData(data:VideoData) {
        self.data = data
    }
#endif
    
    public func clearCachedData() {
        self.gyroDataQueue.sync {
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
            reference = .init(real: 1.0, imag: .zero)
            
            return
        }
        
        reference = findClosestFrame(timestamp: timestamp)
    }
    
    public func getRelativeRotation(timestamp:CMTime) -> simd_quatf {
        let reference = reference
        let current = findClosestFrame(timestamp: timestamp)
        
        return reference.inverse * current
    }
    
    public func getAbsoluteRotation(timestamp:CMTime) -> simd_quatf {
        return findClosestFrame(timestamp: timestamp)
    }
    
    public func hasRotation(timestamp:CMTime) -> Bool {
        return hasRotation(seconds: timestamp.seconds)
    }
    
    public func hasRotation(seconds:TimeInterval) -> Bool {
        #if os(iOS)
        guard !self.gyroData.isEmpty else { return false }
        
        if let nextIndex = self.gyroData.firstIndex { d in d.timestamp >= seconds } {
            return true
        }
        else {
            return false
        }
        #else
        guard let data = data else { return false }

        if let nextIndex = data.gyroTimestamps.firstIndex { t in t >= seconds } {
            return true
        }
        else {
            return false
        }
        #endif
    }
    
    private func findClosestFrame(timestamp:CMTime) -> simd_quatf {
        return findClosestFrame(seconds: timestamp.seconds)
    }
    
    private func findClosestFrame(seconds:TimeInterval) -> simd_quatf {
        gyroDataQueue.sync {
            guard hasRotation(seconds: seconds) else { return .init(real: 1.0, imag: .zero) }

            #if os(iOS)
            if let nextIndex = self.gyroData.firstIndex { d in d.timestamp >= seconds } {
                let prevIndex = max(0, nextIndex - 1)

                let prevTimestamp = self.gyroData[prevIndex].timestamp
                let nextTimestamp = self.gyroData[nextIndex].timestamp
                let delta = nextTimestamp - prevTimestamp
                let alpha = delta > 0 ? seconds - prevTimestamp : 0
                
                let prev = self.gyroData[prevIndex].simfQuaternion
                let next = self.gyroData[prevIndex].simfQuaternion
                
                return alpha == 0 || delta == 0 ? prev : simd_slerp(prev, next, Float(alpha / delta))
            }
            else {
                fatalError("no gyroData, but hasRotation() returned true")
            }

            return !self.gyroData.isEmpty
                ? self.gyroData.min { left, right in abs(left.timestamp - seconds) < abs(right.timestamp - seconds) }?.simfQuaternion ?? .init(real: 1.0, imag: .zero)
                : .init(real: 1.0, imag: .zero)
            #else
            guard let data = data else { return .init(real: 1.0, imag: .zero) }
            
            if let nextIndex = data.gyroTimestamps.firstIndex { t in t >= seconds } {
                let prevIndex = max(0, nextIndex - 1)

                let prevTimestamp = data.gyroTimestamps[prevIndex]
                let nextTimestamp = data.gyroTimestamps[nextIndex]
                let delta = nextTimestamp - prevTimestamp
                let alpha = delta > 0 ? seconds - prevTimestamp : 0
                
                let prev = data.gyro[prevIndex]
                let next = data.gyro[nextIndex]
                
                return alpha == 0 || delta == 0 ? prev : simd_slerp(prev, next, Float(alpha / delta))
            }
            else {
                fatalError("no gyroData, but hasRotation() returned true")
            }
            
            //let closestIndex = self.data?.gyroTimestamps.enumerated().min { left, right in abs(left.element - seconds) < abs(right.element - seconds) }?.offset ?? -1
            //return data?.gyro[closestIndex] ?? .init(real: 1.0, imag: .zero)
            #endif
        }
    }
}
