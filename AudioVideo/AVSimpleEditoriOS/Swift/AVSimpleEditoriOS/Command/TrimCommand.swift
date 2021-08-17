//
// Created by Bq Lin on 2021/8/16.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import AVFoundation

class TrimCommand: Command {
    override func perform(asset: AVAsset) {
        let halfDuration = asset.duration.seconds / 2
        let trimmedDuration = CMTime(seconds: halfDuration, preferredTimescale: asset.duration.timescale)
        
        if let composition = composition {
            composition.removeTimeRange(CMTimeRange(start: trimmedDuration, end: composition.duration))
        } else {
            let composition = AVMutableComposition()
            if let assetTrack = asset.tracks(withMediaType: .video).first {
                let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                do {
                    try track?.insertTimeRange(CMTimeRange(start: .zero, duration: trimmedDuration), of: assetTrack, at: .zero)
                } catch {
                    fatalError("error: \(error)")
                }
            }
            
            if let assetTrack = asset.tracks(withMediaType: .audio).first {
                let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCFMessagePortReceiveTimeout)
                do {
                    try track?.insertTimeRange(CMTimeRange(start: .zero, duration: trimmedDuration), of: assetTrack, at: .zero)
                } catch {
                    fatalError("error: \(error)")
                }
            }
            self.composition = composition
        }
        
        NotificationCenter.default.post(name: .editCommandCompletionNotification, object: self, userInfo: nil)
    }
}
