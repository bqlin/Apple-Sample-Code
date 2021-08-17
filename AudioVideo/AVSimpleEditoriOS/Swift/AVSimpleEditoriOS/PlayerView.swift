//
// Created by Bq Lin on 2021/8/16.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer}
    
    var videoRect: CGRect {
        if let videoSize = playerLayer.player?.currentItem?.presentationSize {
            switch playerLayer.videoGravity {
                case .resizeAspect:
                    return fitCenter(src: videoSize, dst: bounds)
                case .resizeAspectFill:
                    return centerCrop(src: videoSize, dst: bounds)
                default: break
            }
        }
        
        return bounds
    }
    
    var videoScale: CGSize {
        if let videoSize = playerLayer.player?.currentItem?.asset.tracks(withMediaType: .video).first?.naturalSize {
            return CGSize(width: videoSize.width / videoRect.width, height: videoSize.height / videoRect.height)
        }
        return .zero
    }
}

func centerCrop(src: CGSize, dst: CGRect) -> CGRect {
    let srcAspectRatio = src.width / src.height
    let dstAspectRatio = dst.width / dst.height
    
    var rect = dst
    
    if srcAspectRatio > dstAspectRatio {
        // use full height of the video image, and center crop the width
        // src.h = dst.h；纵向无需修改，修改横向
        rect.size.width = dst.height * srcAspectRatio
        rect.origin.x += (dst.width - rect.width) / 2
    } else {
        // use full width of the video image, and center crop the height
        // src.w = dst.w；横向无需修改，修改纵向
        rect.size.height = dst.width / srcAspectRatio
        rect.origin.y += (dst.height - rect.height) / 2
    }
    
    return rect
}

func fitCenter(src: CGSize, dst: CGRect) -> CGRect {
    let srcAspectRatio = src.width / src.height
    let dstAspectRatio = dst.width / dst.height
    
    var rect = dst
    
    if srcAspectRatio > dstAspectRatio {
        // src.w = dst.w；横向无需修改，修改纵向
        rect.size.height = dst.width / srcAspectRatio
        rect.origin.y += (dst.height - rect.height) / 2
    } else {
        // src.h = dst.h；纵向无需修改，修改横向
        rect.size.width = dst.height * srcAspectRatio
        rect.origin.x += (dst.width - rect.width) / 2
    }
    
    return rect
}
