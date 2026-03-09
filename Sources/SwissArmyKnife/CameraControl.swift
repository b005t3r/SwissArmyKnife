//
//  CameraControl.swift
//  StabilizedVideoRecorder
//
//  Created by Łukasz Łazarecki on 01/12/2025.
//

import AVFoundation
import GPUImage

#if os(iOS)
public enum CameraMode: String {
    case res1080p30fps = "FullHD@30"
    case res1080p60fps = "FullHD@60"
    case res4k30fps = "4K@30"
    case res4k60fps = "4K@60"
}

public final class CameraControl {
    public private(set) var fixedShutter: CMTime = .invalid

    private let camera: Camera
    private var isoTimer: DispatchSourceTimer?

    public let formats:[CameraMode : AVCaptureDevice.Format]
    
    public var mode:CameraMode {
        didSet {
            updateCameraMode(newMode: mode)
        }
    }
    
    public var videoInputDelay = CMTime(seconds: 0.04, preferredTimescale: 10000) {
        didSet {
            updateCameraMode(newMode: mode)
        }
    }
    
    public init(camera: Camera, mode:CameraMode) {
        self.camera = camera
        
        let device = camera.inputCamera!
        
        var formatMap = [CameraMode : AVCaptureDevice.Format]()
        
        for format in camera.inputCamera!.formats {
            let desc = format.formatDescription
            
            let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
            
            if mediaSubType == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange || // x420, 10bit
                mediaSubType == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange || // x422, 10bit
                mediaSubType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || // 420v, 8bit
                !format.isVideoHDRSupported {
                continue
            }
            
            let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
            let frameRates = format.videoSupportedFrameRateRanges
            let maxRate = frameRates.map { $0.maxFrameRate }.max() ?? 0
            
            if (dimensions.width != 1920 || dimensions.height != 1080)
                && (dimensions.width != 3840 || dimensions.height != 2160) {
                continue
            }
            
            if dimensions.width == 1920 || dimensions.height == 1080 {
                formatMap[maxRate == 60 ? .res1080p60fps : .res1080p30fps] = format
            }
            else {
                formatMap[maxRate == 60 ? .res4k60fps : .res4k30fps] = format
            }
        }
        
        self.formats = formatMap
        self.mode = mode
    }

    public func setShutterWithAutoExposure(_ seconds: Double) {
        fixedShutter = CMTimeMakeWithSeconds(seconds, preferredTimescale: 1_000_000_000)

        do {
            try camera.inputCamera!.lockForConfiguration()
            camera.inputCamera!.setExposureModeCustom(duration: fixedShutter,
                                         iso: (camera.inputCamera!.activeFormat.maxISO + camera.inputCamera!.activeFormat.minISO) * 0.5,
                                         completionHandler: nil)
            camera.inputCamera!.unlockForConfiguration()
        } catch { print("Failed initial exposure set: \(error)") }

        startAutoISOAdjustment()
    }

    public func resetToAutoExposure() {
        stopAutoISOAdjustment()

        do {
            try camera.inputCamera!.lockForConfiguration()
            if camera.inputCamera!.isExposureModeSupported(.continuousAutoExposure) {
                camera.inputCamera!.exposureMode = .continuousAutoExposure
            }
            camera.inputCamera!.unlockForConfiguration()
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

        let offset = camera.inputCamera!.exposureTargetOffset   // EV difference

        // Deadzone to prevent flicker
        if abs(offset) < 0.03 { return }

        let oldISO = camera.inputCamera!.iso

        // exposureTargetOffset is in EV units:
        // +1 EV = twice too bright → halve ISO
        // -1 EV = too dark → increase ISO
        let isoFactor = pow(2.0, -Float(offset))

        var newISO = oldISO * isoFactor

        // Clamp within allowed range
        let minISO = camera.inputCamera!.activeFormat.minISO
        let maxISO = camera.inputCamera!.activeFormat.maxISO
        newISO = min(max(newISO, minISO), maxISO)

        //print(newISO)
        
        do {
            try camera.inputCamera!.lockForConfiguration()
            camera.inputCamera!.setExposureModeCustom(
                duration: fixedShutter,
                iso: newISO,
                completionHandler: nil
            )
            camera.inputCamera!.unlockForConfiguration()
        } catch {
            print("ISO update failed: \(error)")
        }
    }
    
    private func updateCameraMode(newMode: CameraMode) {
        guard let format = formats[newMode] else {
            debugPrint("format not available for: \(newMode)")
            return
        }
        
        let maxRate = format.videoSupportedFrameRateRanges.map { frameRate in frameRate.maxFrameRate }.max() ?? 0

        camera.videoFrameDelay = maxRate > 0 ? Int(round(videoInputDelay.seconds * maxRate)) : 2
        
        do {
            try camera.inputCamera!.lockForConfiguration()
            camera.inputCamera!.activeFormat = format
            camera.inputCamera!.unlockForConfiguration()
        }
        catch {
            debugPrint(error)
        }
    }
}
#endif
