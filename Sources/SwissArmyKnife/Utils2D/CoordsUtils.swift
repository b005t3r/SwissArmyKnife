//
//  CoordsUtils.swift
//  VisionaireTestUIKit
//
//  Created by Łukasz Łazarecki on 17/06/2025.
//

import Foundation

import Vision

class CoordsUtils {
    static func viewToImage(point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        return CGPoint(x: point.x / width, y: height - point.y)
    }
    
    static func viewToNormalized(point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        return VNNormalizedPointForImagePoint(viewToImage(point: point, width: width, height: height), Int(width), Int(height))
    }
    
    static func imageToView(point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        return CGPoint(x: point.x / width, y: height - point.y)
    }
    
    static func imageToNormalized(point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        return VNNormalizedPointForImagePoint(point, Int(width), Int(height))
    }
    
    static func normalizedToImage(point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        return VNImagePointForNormalizedPoint(point, Int(width), Int(height))
    }
    
    static func normalizedToView(point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        return imageToView(point: VNImagePointForNormalizedPoint(point, Int(width), Int(height)), width: width, height: height)
    }
    
    static func viewToImage(rect: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
    
    static func viewToNormalized(rect: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        return VNNormalizedRectForImageRect(viewToImage(rect: rect, width: width, height: height), Int(width), Int(height))
    }
    
    static func imageToView(rect: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
    
    static func imageToNormalized(rect: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        return VNNormalizedRectForImageRect(rect, Int(width), Int(height))
    }
    
    static func normalizedToView(rect: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
         return imageToView(rect: VNImageRectForNormalizedRect(rect, Int(width), Int(height)), width: width, height: height)
    }
    
    static func normalizedToImage(rect: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        return VNImageRectForNormalizedRect(rect, Int(width), Int(height))
    }
}
