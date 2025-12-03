//
//  CameraControl.swift
//  StabilizedVideoRecorder
//
//  Created by Łukasz Łazarecki on 01/12/2025.
//

import AVFoundation

public final class CameraControl {
    public private(set) var fixedShutter: CMTime = .invalid

    private let device: AVCaptureDevice
    private var isoTimer: DispatchSourceTimer?

    public init(device: AVCaptureDevice) {
        self.device = device
    }

    public func setShutterWithAutoExposure(_ seconds: Double) {
        fixedShutter = CMTimeMakeWithSeconds(seconds, preferredTimescale: 1_000_000_000)

        do {
            try device.lockForConfiguration()
            device.setExposureModeCustom(duration: fixedShutter,
                                         iso: (device.activeFormat.maxISO + device.activeFormat.minISO) * 0.5,
                                         completionHandler: nil)
            device.unlockForConfiguration()
        } catch { print("Failed initial exposure set: \(error)") }

        startAutoISOAdjustment()
    }

    public func resetToAutoExposure() {
        stopAutoISOAdjustment()

        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed resetting exposure: \(error)")
        }
    }

    private func startAutoISOAdjustment() {
        stopAutoISOAdjustment()
        guard fixedShutter != .invalid else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 0.03) // ~30 Hz
        timer.setEventHandler { [weak self] in
            self?.updateISO()
        }
        timer.resume()
        isoTimer = timer
    }

    private func stopAutoISOAdjustment() {
        isoTimer?.cancel()
        isoTimer = nil
    }

    private func updateISO() {
        guard fixedShutter != .invalid else { return }

        let offset = device.exposureTargetOffset   // EV difference

        // Deadzone to prevent flicker
        if abs(offset) < 0.03 { return }

        let oldISO = device.iso

        // exposureTargetOffset is in EV units:
        // +1 EV = twice too bright → halve ISO
        // -1 EV = too dark → increase ISO
        let isoFactor = pow(2.0, -Float(offset))

        var newISO = oldISO * isoFactor

        // Clamp within allowed range
        let minISO = device.activeFormat.minISO
        let maxISO = device.activeFormat.maxISO
        newISO = min(max(newISO, minISO), maxISO)

        //print(newISO)
        
        do {
            try device.lockForConfiguration()
            device.setExposureModeCustom(
                duration: fixedShutter,
                iso: newISO,
                completionHandler: nil
            )
            device.unlockForConfiguration()
        } catch {
            print("ISO update failed: \(error)")
        }
    }
}
