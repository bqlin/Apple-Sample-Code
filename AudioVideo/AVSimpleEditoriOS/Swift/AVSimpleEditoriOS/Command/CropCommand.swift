//
// Created by Bq Lin on 2021/8/16.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

class CropCommand: Command {
    override func perform(asset: AVAsset) {
        if composition == nil {
            composition = Command.makeCompostion(asset: asset)
        }
        guard let composition = composition else { return }
        guard let videoTrack = composition.tracks(withMediaType: .video).first else { return }
        
        var instruction: AVMutableVideoCompositionInstruction
        var layerInstruction: AVMutableVideoCompositionLayerInstruction
        if let videoComposition = videoComposition {
            var renderSize = videoComposition.renderSize
            renderSize.width /= 2
            renderSize.height /= 2
            videoComposition.renderSize = renderSize
            
            instruction = videoComposition.instructions.first! as! AVMutableVideoCompositionInstruction
            layerInstruction = instruction.layerInstructions.first! as! AVMutableVideoCompositionLayerInstruction
            
            var exitingTransform: CGAffineTransform = .identity
            let size = videoTrack.naturalSize
            let t = CGAffineTransform(translationX: -1 * size.width / 2, y: -1 * size.height / 2)
            if layerInstruction.getTransformRamp(for: composition.duration, start: &exitingTransform, end: nil, timeRange: nil) {
                layerInstruction.setTransform(exitingTransform.concatenating(t), at: .zero)
            } else {
                layerInstruction.setTransform(t, at: .zero)
            }
        } else {
            let videoComposition = AVMutableVideoComposition()
            var renderSize = videoTrack.naturalSize
            renderSize.width /= 2
            renderSize.height /= 2
            videoComposition.renderSize = renderSize
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            
            instruction = .init()
            instruction.timeRange = CMTimeRange(start: .zero, end: composition.duration)
            
            layerInstruction = .init(assetTrack: videoTrack)
            let size = videoTrack.naturalSize
            let t = CGAffineTransform(translationX: -1 * size.width / 2, y: -1 * size.height / 2)
            layerInstruction.setTransform(t, at: .zero)
            self.videoComposition = videoComposition
        }
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition!.instructions = [instruction]
        
        NotificationCenter.default.post(name: .editCommandCompletionNotification, object: self, userInfo: nil)
    }
}
