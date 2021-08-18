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
        
        let instruction: AVMutableVideoCompositionInstruction
        let layerInstruction: AVMutableVideoCompositionLayerInstruction
        
        // 每次顺时针旋转90度
        let naturalSize, renderSize: CGSize
        var t: CGAffineTransform = .identity
        if let videoComposition = videoComposition {
            naturalSize = videoComposition.renderSize
            instruction = videoComposition.instructions.first! as! AVMutableVideoCompositionInstruction
            layerInstruction = instruction.layerInstructions.first! as! AVMutableVideoCompositionLayerInstruction
            
            var exitingTransform = CGAffineTransform.identity
            _ = layerInstruction.getTransformRamp(for: composition.duration, start: &exitingTransform, end: nil, timeRange: nil)
            t = exitingTransform.concatenating(t)
        } else {
            naturalSize = videoTrack.naturalSize
            let videoComposition = AVMutableVideoComposition()
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            
            instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, end: composition.duration)
            layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            self.videoComposition = videoComposition
        }
        renderSize = naturalSize.swap
        videoComposition!.renderSize = renderSize
        
        // Translate the composition to compensate the movement caused by rotation (since rotation would cause it to move out of frame)
        // Rotate transformation
        // 由于矩阵不满足结合律，所以不能写成下面
        // t = t.translatedBy(x: naturalSize.height, y: 0).rotated(by: degreesToRadians(90))
        // 需写成这样：
        let transform = CGAffineTransform.identity.translatedBy(x: naturalSize.height, y: 0).rotated(by: degreesToRadians(90))
        t = t.concatenating(transform)
        layerInstruction.setTransform(t, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition!.instructions = [instruction]
        
        NotificationCenter.default.post(name: .editCommandCompletionNotification, object: self, userInfo: nil)
    }
}

extension CGSize {
    var swap: CGSize { .init(width: height, height: width) }
}
