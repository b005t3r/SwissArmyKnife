//
//  File.swift
//  GolfBallTracker
//
//  Created by Łukasz Łazarecki on 31/10/2025.
//

import Foundation
import ImageIO

import GPUImage

public enum FrameOrientation {
    case none
    case counterClockwise
    case clockwise
    case upsideDown
    
    public static func with(orientation:ImageOrientation) -> FrameOrientation {
        switch orientation {
            case .portrait:
                return with(angle: .pi / 2)
            
            case .portraitUpsideDown:
                return with(angle: -.pi / 2)

            case .landscapeRight:
                return with(angle: 0)

            case .landscapeLeft:
                return with(angle:  .pi)
        }
    }
    
    public static func with(angle:CGFloat, epsilon:CGFloat = 0.01) -> FrameOrientation {
        var angle = angle.truncatingRemainder(dividingBy: .pi * 2.0)
        
        if angle < 0 {
            angle += .pi * 2.0
        }
        
        if angle < epsilon {
            return .none
        }
        
        if abs(angle - .pi * 0.5) < epsilon {
            return angle < 0 ? .counterClockwise : .clockwise
        }

        if abs(angle - .pi) < epsilon {
            return .upsideDown
        }

        if abs(angle - .pi * 1.5) < epsilon {
            return angle < 0 ? .clockwise : .counterClockwise
        }
        
        fatalError("invalid angle: \(angle)")
    }
    
    public var orientation: CGImagePropertyOrientation {
        switch self {
        case .none:
            return .up
        case .counterClockwise:
            return .left
        case .clockwise:
            return .right
        case .upsideDown:
            return .down
        }
    }
    
    public var up:SIMD3<Float> {
        switch self {
        case .none:
            return .init(-1, 0, 0)
        case .counterClockwise:
            return .init(0, 0, -1)
        case .clockwise:
            return .init(0, 0, 1)
        case .upsideDown:
            return .init(1, 0, 0)
        }
    }
    
    public var angle:Double {
        switch self {
            case .clockwise:
                return .pi / 2
            
            case .counterClockwise:
                return -.pi / 2

            case .none:
                return 0

            case .upsideDown:
                return .pi
        }
    }
}
