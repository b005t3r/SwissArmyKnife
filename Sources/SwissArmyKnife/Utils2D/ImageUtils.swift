//
//  ImageUtils.swift
//  GolfBallTracker
//
//  Created by Łukasz Łazarecki on 01/08/2025.
//

import CoreGraphics

public class ImageUtils {
    public static func scaled(image: CGImage, size:CGSize) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        
        guard let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        
        context.interpolationQuality = .high
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: Int(size.width), height: Int(size.height)))
        return context.makeImage()
    }
}
