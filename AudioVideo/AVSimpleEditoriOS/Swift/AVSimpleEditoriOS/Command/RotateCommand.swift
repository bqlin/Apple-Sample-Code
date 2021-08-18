//
// Created by Bq Lin on 2021/8/16.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import AVFoundation
import CoreGraphics

class RotateCommand: Command {
    func degreesToRadians(_ degrees: CGFloat) -> CGFloat { degrees / 180 * .pi }
    override func perform(asset: AVAsset) {
        if composition == nil {
            composition = Command.makeCompostion(asset: asset)
        }
        guard let composition = composition else { return }
        guard let videoTrack = composition.tracks(withMediaType: .video).first else { return }
        
        var instruction: AVMutableVideoCompositionInstruction
        var layerInstruction: AVMutableVideoCompositionLayerInstruction
        
        // 每次顺时针旋转90度
        if let videoComposition = videoComposition {
            let size = videoComposition.renderSize
            let renderSize = size.swap
            
            // Translate the composition to compensate the movement caused by rotation (since rotation would cause it to move out of frame)
            // Rotate transformation
            let t = CGAffineTransform(translationX: size.height, y: 0).rotated(by: degreesToRadians(90))
            
            videoComposition.renderSize = renderSize
            
            instruction = videoComposition.instructions.first! as! AVMutableVideoCompositionInstruction
            layerInstruction = instruction.layerInstructions.first! as! AVMutableVideoCompositionLayerInstruction
            
            var exitingTransform = CGAffineTransform.identity
            _ = layerInstruction.getTransformRamp(for: composition.duration, start: &exitingTransform, end: nil, timeRange: nil)
            layerInstruction.setTransform(exitingTransform.concatenating(t), at: .zero)
        } else {
            let size = videoTrack.naturalSize
            let renderSize = size.swap
            
            // Translate the composition to compensate the movement caused by rotation (since rotation would cause it to move out of frame)
            // Rotate transformation
            let t = CGAffineTransform(translationX: size.height, y: 0).rotated(by: degreesToRadians(90))
            
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = renderSize
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            
            instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, end: composition.duration)
            layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(t, at: .zero)
            
            self.videoComposition = videoComposition
        }
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition!.instructions = [instruction]
        
        NotificationCenter.default.post(name: .editCommandCompletionNotification, object: self, userInfo: nil)
    }
}

extension CGSize {
    var swap: CGSize { .init(width: height, height: width) }
}
