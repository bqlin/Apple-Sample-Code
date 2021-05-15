//
// Created by Bq Lin on 2021/5/14.
// Copyright (c) 2021 Bq. All rights reserved.
//

import Foundation
import ImageIO
import UIKit

class TGAImage {
    struct Header {
        var IDSize: UInt8
    }
    
    init(fileURL: URL) {
        let fileData = try! Data(contentsOf: fileURL)
        
        var prefixBytes = [UInt8](repeating: 0, count: 5) // 一定要初始化
        fileData.copyBytes(to: &prefixBytes, count: 5)
        
        // 会有警告，也不知道怎么解决
        // let prefixBytes: [UInt8] = fileData.withUnsafeBytes {
        //     [UInt8](UnsafeBufferPointer(start: $0, count: 5))
        // }
        
        // 00 00 02 00 00
        let targetPrefix: [UInt8] = [0x00, 0x00, 0x02, 0x00, 0x00]
        guard prefixBytes == targetPrefix else {
            print("not tga file, data prefix: \(prefixBytes)")
            return
        }
        guard let source = CGImageSourceCreateWithData(fileData as CFData, nil) else {
            return
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return
        }
        
        width = image.width
        height = image.height
        var imageBytes = [UInt8](repeating: 0, count: image.bytesPerRow * height)
        let rect = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
        print(image.imageDebugInfo)
        // BGRA
        // let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let bitmapInfo = image.bitmapInfo.rawValue
        
        let context = CGContext(data: &imageBytes, width: width, height: height, bitsPerComponent: image.bitsPerComponent, bytesPerRow: image.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo)
        // context?.setFillColor(UIColor.white.cgColor)
        // context?.fill(rect)
        context?.draw(image, in: rect)
        
        //let newImage = context?.makeImage()
        
        data = Data(imageBytes)
    }
    
    private(set) var width: Int!
    private(set) var height: Int!
    private(set) var data: Data!
    
}

extension CGImage {
    var imageDebugInfo: String {
        var info = ""
        info += "size in pixel: \(width)×\(height)\n"
        info += "bits per component: \(bitsPerComponent), bits per pixel: \(bitsPerPixel)\n"
        let infoValue = bitmapInfo.rawValue
        
        if infoValue & CGBitmapInfo.floatComponents.rawValue != 0 {
            info += "has floatComponents\n"
        } else {
            info += "has no floatComponents\n"
        }
        
        if infoValue & CGBitmapInfo.byteOrderMask.rawValue != 0 {
            info += "has byteOrder: "
            if infoValue & CGBitmapInfo.byteOrder16Big.rawValue == CGBitmapInfo.byteOrder16Big.rawValue {
                info += "16Big"
            }
            if infoValue & CGBitmapInfo.byteOrder16Little.rawValue == CGBitmapInfo.byteOrder16Little.rawValue {
                info += "16Little"
            }
            if infoValue & CGBitmapInfo.byteOrder32Big.rawValue == CGBitmapInfo.byteOrder32Big.rawValue {
                info += "32Big"
            }
            if infoValue & CGBitmapInfo.byteOrder32Little.rawValue == CGBitmapInfo.byteOrder32Little.rawValue {
                info += "32Little"
            }
            info += "\n"
        } else {
            info += "has no byteOrder\n"
        }
        
        if infoValue & CGBitmapInfo.alphaInfoMask.rawValue != 0 {
            info += "has alphaInfo: "
            switch alphaInfo {
                case .none:
                    info += "none"
                case .premultipliedLast:
                    info += "premultipliedLast"
                case .premultipliedFirst:
                    info += "premultipliedFirst"
                case .last:
                    info += "last"
                case .first:
                    info += "first"
                case .noneSkipLast:
                    info += "noneSkipLast"
                case .noneSkipFirst:
                    info += "noneSkipFirst"
                case .alphaOnly:
                    info += "alphaOnly"
                @unknown default:
                    info += "unknown \(alphaInfo)"
            }
            info += "\n"
        } else {
            info += "has no alphaInfo\n"
        }
        
        return info
    }
}

