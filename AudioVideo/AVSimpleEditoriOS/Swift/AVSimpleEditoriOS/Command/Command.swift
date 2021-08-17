//
// Created by Bq Lin on 2021/8/16.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import AVFoundation

class Command: NSObject {
    var composition: AVMutableComposition?
    var videoComposition: AVMutableVideoComposition?
    var audioMix: AVMutableAudioMix?
    var watermarkLayer: CALayer?
    
    func perform(asset: AVAsset) {
        doesNotRecognizeSelector(#function)
    }
       
}

extension Command {
    static func makeCompostion(asset: AVAsset) -> AVMutableComposition {
        let composition = AVMutableComposition()
        if let assetTrack = asset.tracks(withMediaType: .video).first {
            let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            do {
                try track?.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: assetTrack, at: .zero)
            } catch {
                fatalError("error: \(error)")
            }
        }
        
        if let assetTrack = asset.tracks(withMediaType: .audio).first {
            let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCFMessagePortReceiveTimeout)
            do {
                try track?.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: assetTrack, at: .zero)
            } catch {
                fatalError("error: \(error)")
            }
        }
        
        return composition
    }
    
    static func makeVideoComposition(compostion: AVComposition) -> AVMutableVideoComposition {
        let videoTrack = compostion.tracks(withMediaType: .video).first!
        let videoCompositon = AVMutableVideoComposition()
        videoCompositon.frameDuration = CMTime(value: 1, timescale: 30)
        videoCompositon.renderSize = videoTrack.naturalSize
        
        let passThroughInstruction = AVMutableVideoCompositionInstruction()
        passThroughInstruction.timeRange = CMTimeRange(start: .zero, duration: compostion.duration)
        
        let passThroughLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        passThroughInstruction.layerInstructions = [passThroughLayer]
        videoCompositon.instructions = [passThroughInstruction]
        
        return videoCompositon
    }
    
    static func makeAudioMix() -> AVMutableAudioMix {
        AVMutableAudioMix()
    }
}

extension Notification.Name {
    static let editCommandCompletionNotification = Self(rawValue: "editCommandCompletionNotification")
    static let exportCommandCompletionNotification = Self(rawValue: "exportCommandCompletionNotification")
}
