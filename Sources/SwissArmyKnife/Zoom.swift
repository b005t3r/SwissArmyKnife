//
//  Zoom.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 14/07/2026.
//

import CoreGraphics
import CoreMedia
import Foundation

public final class Zoom {
    public struct State: Equatable {
        public let location: CGPoint
        public let level: CGFloat

        public init(location: CGPoint, level: CGFloat) {
            self.location = location
            self.level = level
        }
    }

    public struct Change: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
        public let timestamp: CMTime
        public let state: State

        public init(timestamp: CMTime, location: CGPoint, level: CGFloat) {
            self.timestamp = timestamp
            self.state = State(location: location, level: level)
        }

        public init(timestamp: CMTime, state: State) {
            self.timestamp = timestamp
            self.state = state
        }
        
        public var description: String {
            String(
                format: "%.3f[%.2f,%.2f]x%.2f",
                timestamp.seconds,
                state.location.x,
                state.location.y,
                state.level
            )
        }

        public var debugDescription: String {
            description
        }
    }
    
    private let lock = NSLock()
    private var changes: [Change]

    public init(
        initialLocation: CGPoint = CGPoint(x: 0.5, y: 0.5),
        initialLevel: CGFloat = 1.0,
        timestamp: CMTime = .zero
    ) {
        changes = [
            Change(
                timestamp: timestamp,
                location: initialLocation,
                level: initialLevel
            )
        ]
    }

    public init(timeline: [Change]) {
        precondition(!timeline.isEmpty)
        changes = Self.sortedTimeline(timeline)
    }

    public func get(at timestamp: CMTime) -> State {
        lock.lock()
        let changes = self.changes
        lock.unlock()

        guard changes.count > 1 else {
            return changes[0].state
        }

        if CMTimeCompare(timestamp, changes[0].timestamp) <= 0 {
            return changes[0].state
        }

        if CMTimeCompare(timestamp, changes[changes.count - 1].timestamp) >= 0 {
            return changes[changes.count - 1].state
        }

        let nextIndex = changes.partitioningIndex {
            CMTimeCompare($0.timestamp, timestamp) >= 0
        }
        let previous = changes[nextIndex - 1]
        let next = changes[nextIndex]
        let duration = CMTimeGetSeconds(CMTimeSubtract(next.timestamp, previous.timestamp))

        guard duration > 0 else {
            return next.state
        }

        let elapsed = CMTimeGetSeconds(CMTimeSubtract(timestamp, previous.timestamp))
        let progress = min(max(elapsed / duration, 0.0), 1.0)
        let easedProgress = CGFloat(progress * progress * (3.0 - 2.0 * progress))

        return State(
            location: CGPoint(
                x: previous.state.location.x + (next.state.location.x - previous.state.location.x) * easedProgress,
                y: previous.state.location.y + (next.state.location.y - previous.state.location.y) * easedProgress
            ),
            level: previous.state.level + (next.state.level - previous.state.level) * easedProgress
        )
    }

    public func set(location: CGPoint, level: CGFloat, at timestamp: CMTime) {
        let change = Change(timestamp: timestamp, location: location, level: level)

        lock.lock()
        defer { lock.unlock() }

        let index = changes.partitioningIndex {
            CMTimeCompare($0.timestamp, timestamp) >= 0
        }

        if index < changes.count && CMTimeCompare(changes[index].timestamp, timestamp) == 0 {
            changes[index] = change
        } else {
            changes.insert(change, at: index)
        }
    }

    public func exportTimeline(mergingChangesWithin duration: TimeInterval) -> [Change] {
        lock.lock()
        let changes = self.changes
        lock.unlock()

        guard changes.count > 2, duration > 0 else {
            return changes
        }

        var result: [Change] = []
        var sequenceStart = 0

        while sequenceStart < changes.count {
            var sequenceEnd = sequenceStart

            while sequenceEnd + 1 < changes.count {
                let interval = CMTimeGetSeconds(
                    CMTimeSubtract(
                        changes[sequenceEnd + 1].timestamp,
                        changes[sequenceEnd].timestamp
                    )
                )

                guard interval <= duration else {
                    break
                }

                sequenceEnd += 1
            }

            result.append(changes[sequenceStart])

            if sequenceEnd > sequenceStart {
                result.append(changes[sequenceEnd])
            }

            sequenceStart = sequenceEnd + 1
        }

        return result
    }

    private static func sortedTimeline(_ timeline: [Change]) -> [Change] {
        let sorted = timeline.sorted {
            CMTimeCompare($0.timestamp, $1.timestamp) < 0
        }
        var result: [Change] = []

        for change in sorted {
            if let last = result.last,
               CMTimeCompare(last.timestamp, change.timestamp) == 0 {
                result[result.count - 1] = change
            } else {
                result.append(change)
            }
        }

        return result
    }
}

private extension Array {
    func partitioningIndex(where predicate: (Element) -> Bool) -> Int {
        var lowerBound = 0
        var upperBound = count

        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2

            if predicate(self[middle]) {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }

        return lowerBound
    }
}
