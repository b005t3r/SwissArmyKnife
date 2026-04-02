//
//  AsyncBufferProcessor.swift
//  LiveTrackerDemo
//
//  Created by Łukasz Łazarecki on 22/01/2026.
//

import Foundation

public final class AsyncProcessor<T> {
    private let dataQueue:SafeDispatchQueue
    private let workQueue:SafeDispatchQueue

    private let semaphore = DispatchSemaphore(value: 0)

    public private(set) var dataBufferSize:Int
    private var data:[T] = []
    private var isRunning = false

    public init(dataBufferSize:Int, qos: DispatchQoS = .userInitiated, tag:String? = nil) {
        self.dataBufferSize = dataBufferSize
        
        if let tag {
            dataQueue = SafeDispatchQueue(label: "AsyncProcessor.dataQueue.\(tag)", qos: qos)
            workQueue = SafeDispatchQueue(label: "AsyncProcessor.workQueue.\(tag)", qos: qos)
        }
        else {
            dataQueue = SafeDispatchQueue(label: "AsyncProcessor.dataQueue", qos: qos)
            workQueue = SafeDispatchQueue(label: "AsyncProcessor.workQueue", qos: qos)
        }
    }

    public func startProcessing(_ worker: @escaping (_ data: T) -> Void) {
        dataQueue.sync {
            guard !isRunning else { fatalError("processing already started") }
            isRunning = true
        }

        workQueue.async { [weak self] in
            while true {
                guard let self else { return }
                
                let runningBefore = self.dataQueue.sync { self.isRunning }
                guard runningBefore else { break }

                self.semaphore.wait()

                let runningAfter = self.dataQueue.sync { self.isRunning }
                guard runningAfter else { break }

                let dataToProcess: T? = self.dataQueue.sync { !self.data.isEmpty ? self.data.removeFirst() : nil }

                guard let dataToProcess else { continue }
                worker(dataToProcess)
            }
        }
    }

    public func stopProcessing() {
        dataQueue.sync {
            isRunning = false
            data.removeAll()
        }

        semaphore.signal()
    }

    public func addData(_ data: T) {
        dataQueue.async(flags: .barrier) {
            self.data.append(data)
            
            if self.data.count > self.dataBufferSize {
                self.data.removeFirst()
            }
            
            self.semaphore.signal()
        }
    }
}

