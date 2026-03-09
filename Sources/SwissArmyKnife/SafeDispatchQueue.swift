//
//  SafeDispatchQueue.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 06/03/2026.
//

import Foundation

public final class SafeDispatchQueue {
    private let queue: DispatchQueue
    private let key = DispatchSpecificKey<Void>()

    public init(label: String, qos: DispatchQoS = .default, attributes: DispatchQueue.Attributes = []) {
        queue = DispatchQueue(label: label, qos: qos, attributes: attributes)
        queue.setSpecific(key: key, value: ())
    }

    public var isOnQueue: Bool {
        DispatchQueue.getSpecific(key: key) != nil
    }

    @discardableResult
    public func sync<T>(_ block: () throws -> T) rethrows -> T {
        if isOnQueue {
            return try block()
        }
        return try queue.sync(execute: block)
    }

    public func async(flags: DispatchWorkItemFlags = [], _ block: @escaping () -> Void) {
        queue.async(flags: flags, execute: block)
    }
}
