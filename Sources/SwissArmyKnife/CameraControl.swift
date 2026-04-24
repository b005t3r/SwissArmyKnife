//
//  CameraControl.swift
//  StabilizedVideoRecorder
//
//  Created by Łukasz Łazarecki on 01/12/2025.
//

import AVFoundation
import GPUImage

private func FourCharCodeToString(_ value: FourCharCode) -> String {
    let bytes: [CChar] = [
        CChar((value >> 24) & 0xff),
        CChar((value >> 16) & 0xff),
        CChar((value >> 8) & 0xff),
        CChar(value & 0xff),
        0
    ]
    return String(cString: bytes)
}


#if os(iOS)
public enum CameraMode: String {
    case res1080p30fps = "FullHD@30"
    case res1080p60fps = "FullHD@60"
    case res4k30fps = "4K@30"
    case res4k60fps = "4K@60"

    public var fps: Double {
        switch self {
        case .res1080p30fps, .res4k30fps:
            30
        case .res1080p60fps, .res4k60fps:
            60
        }
    }

    public var frameDuration: CMTime {
        CMTime(seconds: 1.0 / fps, preferredTimescale: 100000)
    }

    public var resolution: CGSize {
        switch self {
        case .res1080p30fps, .res1080p60fps:
            CGSize(width: 1920, height: 1080)
        case .res4k30fps, .res4k60fps:
            CGSize(width: 3840, height: 2160)
        }
    }
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
    
    public init(camera: Camera, mode:CameraMode/*, prefferedPixelFormat:OSType? = nil*/) {
        self.camera = camera
        
        let device = camera.inputCamera!
        
        var formatMap = [CameraMode : AVCaptureDevice.Format]()
        
        for format in camera.inputCamera!.formats {
            let desc = format.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
            let pixelFormat = CMFormatDescriptionGetMediaSubType(desc)
            let maxFPS = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            
            let is1080p = dimensions.width == 1920 && dimensions.height == 1080
            let is4k = dimensions.width == 3840 && dimensions.height == 2160
            let is420f = pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            //let is420v = pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            let is30or60 = maxFPS == 30 || maxFPS == 60
            let isHdrSupported = format.isVideoHDRSupported

            print("-----")
            print("dimensions:", dimensions.width, "x", dimensions.height)
            print("pixel format:", FourCharCodeToString(pixelFormat))
            print("max fps:", maxFPS)
            print("fov:", format.videoFieldOfView)
            print("max zoom:", format.videoMaxZoomFactor)
            print("upscale threshold:", format.videoZoomFactorUpscaleThreshold)
            print("hdr:", isHdrSupported)
            print("photo dims high res:", format.highResolutionStillImageDimensions)
            print("color spaces:", format.supportedColorSpaces.map(String.init(describing:)))
            print("frame rate ranges:")
            for range in format.videoSupportedFrameRateRanges {
                print("  min fps:", range.minFrameRate,
                      "max fps:", range.maxFrameRate,
                      "min duration:", range.minFrameDuration,
                      "max duration:", range.maxFrameDuration)
            }

            // hdr supported means just better quality, only one 60fps 1080p format doesn't support that
            guard (is1080p || is4k) && is420f && is30or60 && isHdrSupported else { continue }

            if (dimensions.width != 1920 || dimensions.height != 1080)
                && (dimensions.width != 3840 || dimensions.height != 2160) {
                continue
            }
            
            if dimensions.width == 1920 || dimensions.height == 1080 {
                formatMap[maxFPS == 60 ? .res1080p60fps : .res1080p30fps] = format
            }
            else {
                formatMap[maxFPS == 60 ? .res4k60fps : .res4k30fps] = format
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
        
        let targetFPS = newMode.fps
        
        guard let frameRate = format.videoSupportedFrameRateRanges.min(by: {
            abs($0.maxFrameRate - targetFPS) < abs($1.maxFrameRate - targetFPS)
        }) else {
            debugPrint("no frame rate range for: \(newMode)")
            return
        }
        
        camera.videoFrameDelay = Int(round(videoInputDelay.seconds * frameRate.maxFrameRate))
        
        do {
            let device = camera.inputCamera!
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMaxFrameDuration = frameRate.minFrameDuration
            device.activeVideoMinFrameDuration = frameRate.minFrameDuration
            device.unlockForConfiguration()
        } catch {
            debugPrint(error)
        }

        // make sure audio is properly reconfigured
        camera.audioEncodingTarget = camera.audioEncodingTarget
    }
}
#endif
