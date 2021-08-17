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
        let naturalSize = videoTrack.naturalSize
        
        // Translate the composition to compensate the movement caused by rotation (since rotation would cause it to move out of frame)
        let translate = CGAffineTransform(translationX: naturalSize.height, y: 0)
        // Rotate transformation
        let translateRotate = translate.rotated(by: degreesToRadians(90))
        
        if let videoComposition = videoComposition {
            var renderSize = videoComposition.renderSize
            let tmp = renderSize.width
            renderSize.width = renderSize.height
            renderSize.height = tmp
            videoComposition.renderSize = renderSize
            
            instruction = videoComposition.instructions.first! as! AVMutableVideoCompositionInstruction
            layerInstruction = instruction.layerInstructions.first! as! AVMutableVideoCompositionLayerInstruction
            
            var exitingTransform = CGAffineTransform.identity
            if layerInstruction.getTransformRamp(for: composition.duration, start: &exitingTransform, end: nil, timeRange: nil) {
                let t = translateRotate.translatedBy(x: -1 * naturalSize.height / 2, y: 0)
                layerInstruction.setTransform(t, at: .zero)
            } else {
                layerInstruction.setTransform(translateRotate, at: .zero)
            }
        } else {
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CGSize(width: naturalSize.height, height: naturalSize.width)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            
            instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, end: composition.duration)
            layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(translateRotate, at: .zero)
            
            self.videoComposition = videoComposition
        }
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition!.instructions = [instruction]
        
        NotificationCenter.default.post(name: .editCommandCompletionNotification, object: self, userInfo: nil)
    }
}
