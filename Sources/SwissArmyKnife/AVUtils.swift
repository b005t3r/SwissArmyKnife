//
//  AVUtils.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 09/03/2026.
//

import AVFoundation

public enum RemuxError: Error {
    case noVideoTrack
    case noAudioTrack
    case cannotCreateExportSession
    case invalidAudioStartTime
    case exportFailed(Error?)
}

public func mux(videoInputURL: URL, audioInputURL: URL, outputURL: URL, audioStartTime: CMTime = .zero, completion: @escaping (Result<URL, Error>) -> Void) {
    let audioAsset = AVURLAsset(url: audioInputURL)
    let videoAsset = AVURLAsset(url: videoInputURL)

    guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
        completion(.failure(RemuxError.noVideoTrack))
        return
    }

    guard let audioTrack = audioAsset.tracks(withMediaType: .audio).first else {
        completion(.failure(RemuxError.noAudioTrack))
        return
    }

    guard audioStartTime >= .zero, audioStartTime < audioAsset.duration else {
        completion(.failure(RemuxError.invalidAudioStartTime))
        return
    }

    let composition = AVMutableComposition()

    guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        completion(.failure(RemuxError.noVideoTrack))
        return
    }

    guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        completion(.failure(RemuxError.noAudioTrack))
        return
    }

    do {
        let videoRange = CMTimeRange(start: .zero, duration: videoAsset.duration)
        try compositionVideoTrack.insertTimeRange(videoRange, of: videoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = videoTrack.preferredTransform

        let remainingAudio = audioAsset.duration - audioStartTime
        let audioDuration = min(remainingAudio, videoAsset.duration)
        let audioRange = CMTimeRange(start: audioStartTime, duration: audioDuration)

        try compositionAudioTrack.insertTimeRange(audioRange, of: audioTrack, at: .zero)
    } catch {
        completion(.failure(error))
        return
    }

    if FileManager.default.fileExists(atPath: outputURL.path) {
        try? FileManager.default.removeItem(at: outputURL)
    }

    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
        completion(.failure(RemuxError.cannotCreateExportSession))
        return
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mov

    exportSession.exportAsynchronously {
        switch exportSession.status {
        case .completed:
            completion(.success(outputURL))
        case .failed, .cancelled:
            completion(.failure(RemuxError.exportFailed(exportSession.error)))
        default:
            break
        }
    }
}
