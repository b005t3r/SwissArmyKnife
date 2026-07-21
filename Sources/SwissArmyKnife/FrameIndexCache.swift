//
//  FrameIndexCache.swift
//  SwissArmyKnife
//

import Foundation
import CoreMedia

/// Persists a media file's sample presentation-timestamp index to a sidecar file, so the
/// full-track scan that produces it only ever runs once per file.
///
/// The index is stored as `(value, timescale)` rather than seconds. `CMTime.==` compares via
/// `CMTimeCompare`, which normalises across timescales, so that round trip is numerically
/// exact - which matters because `VideoReader.shouldUseCachedReader` compares stored
/// timestamps against freshly decoded sample timestamps with `==`.
public enum FrameIndexCache {
    /// When true, `load` always returns nil so the caller performs its real scan, and the
    /// scanned result is compared against whatever was cached. Use it to validate the cache
    /// after changing this file, then turn it back off.
    static let verifyAgainstScan = false

    private static let version = 1
    private static let fileExtension = "ptsindex"

    /// Tolerance when comparing the source's modification date, since a `Date` round-tripped
    /// through a JSON `Double` need not compare bit-equal.
    private static let modificationTolerance: TimeInterval = 0.001

    private struct Payload: Codable {
        let version: Int
        let sourceModified: TimeInterval
        let sourceSize: Int64
        let timescale: Int32
        let values: [Int64]
    }

    /// Deliberately not `.json`: a stray json sidecar next to a recording would be picked up
    /// by callers that discover media by matching json stems.
    static func cacheURL(for mediaURL: URL) -> URL {
        mediaURL.deletingPathExtension().appendingPathExtension(fileExtension)
    }

    /// Cheap "is there probably a usable cache" check: two stats, no `AVAsset`, no decode.
    ///
    /// Only ever used to skip redundant warm-up work. `load` stays the authority on whether
    /// a cache is actually usable, so a wrong answer here costs a scan or a wasted warm,
    /// never correctness.
    public static func isProbablyCached(for mediaURL: URL) -> Bool {
        guard !verifyAgainstScan else { return false }

        guard let cacheModified = modificationDate(of: cacheURL(for: mediaURL)),
              let sourceModified = modificationDate(of: mediaURL)
        else { return false }

        return cacheModified >= sourceModified
    }

    /// Returns the cached index, or nil if absent, stale, unreadable or implausible.
    /// `duration`, when valid, is used as a sanity bound on the last timestamp.
    static func load(for mediaURL: URL, duration: CMTime = .invalid) -> [CMTime]? {
        guard !verifyAgainstScan else { return nil }

        return loadIgnoringVerifyFlag(for: mediaURL, duration: duration)
    }

    static func save(_ timestamps: [CMTime], for mediaURL: URL) {
        guard !timestamps.isEmpty else { return }

        guard let timescale = sharedTimescale(of: timestamps) else {
            print("FrameIndexCache: mixed timescales for \(mediaURL.lastPathComponent), not caching")
            return
        }

        guard let attributes = sourceAttributes(of: mediaURL) else { return }

        let payload = Payload(
            version: version,
            sourceModified: attributes.modified,
            sourceSize: attributes.size,
            timescale: timescale,
            values: timestamps.map { $0.value }
        )

        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: cacheURL(for: mediaURL), options: .atomic)
        }
        catch {
            // the cache is an optimisation, never a correctness dependency
            print("FrameIndexCache: could not write \(mediaURL.lastPathComponent): \(error)")
        }
    }

    /// Reads back what was just written and compares it against the freshly scanned index,
    /// reporting any divergence. Call immediately after `save`, so a single run exercises the
    /// whole write-then-read round trip rather than testing against a previous run's file.
    /// Only does anything when `verifyAgainstScan` is on.
    static func verify(_ scanned: [CMTime], for mediaURL: URL) {
        guard verifyAgainstScan else { return }

        let name = mediaURL.lastPathComponent

        guard let cached = loadIgnoringVerifyFlag(for: mediaURL, duration: .invalid) else {
            print("FrameIndexCache.verify FAILED to read back \(name), scanned=\(scanned.count)")
            return
        }

        guard cached == scanned else {
            let firstMismatch = zip(cached, scanned).enumerated().first { $0.element.0 != $0.element.1 }?.offset

            print("FrameIndexCache.verify MISMATCH \(name):"
                  + " cached=\(cached.count) scanned=\(scanned.count)"
                  + " firstDifferingIndex=\(firstMismatch.map(String.init) ?? "none")")
            return
        }

        print("FrameIndexCache.verify ok \(name) count=\(scanned.count)")
    }

    // MARK: - Internals

    private static func loadIgnoringVerifyFlag(for mediaURL: URL, duration: CMTime) -> [CMTime]? {
        let url = cacheURL(for: mediaURL)

        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }

        guard payload.version == version, payload.timescale > 0, !payload.values.isEmpty else {
            return nil
        }

        guard let attributes = sourceAttributes(of: mediaURL),
              attributes.size == payload.sourceSize,
              abs(attributes.modified - payload.sourceModified) <= modificationTolerance
        else { return nil }

        let timestamps = payload.values.map { CMTime(value: $0, timescale: payload.timescale) }

        // cheap corruption check: the index must be sorted and lie inside the asset
        guard isSortedAscending(timestamps) else { return nil }

        if duration.isValid, let last = timestamps.last, last > duration {
            return nil
        }

        return timestamps
    }

    private static func sharedTimescale(of timestamps: [CMTime]) -> CMTimeScale? {
        guard let first = timestamps.first?.timescale, first > 0 else { return nil }

        return timestamps.allSatisfy { $0.timescale == first } ? first : nil
    }

    private static func isSortedAscending(_ timestamps: [CMTime]) -> Bool {
        guard timestamps.count > 1 else { return true }

        for i in 1..<timestamps.count where timestamps[i] <= timestamps[i - 1] {
            return false
        }

        return true
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func sourceAttributes(of url: URL) -> (modified: TimeInterval, size: Int64)? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate,
              let size = values.fileSize
        else { return nil }

        return (modified.timeIntervalSince1970, Int64(size))
    }
}
