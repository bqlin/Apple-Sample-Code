//
// Created by Bq Lin on 2021/8/16.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import AVFoundation

class TrimCommand: Command {
    override func perform(asset: AVAsset) {
        // 每次保留后半段
        if let composition = composition {
            let duration = CMTime(seconds: composition.duration.seconds / 2, preferredTimescale: asset.duration.timescale)
            composition.removeTimeRange(CMTimeRange(start: .zero, end: duration))
        } else {
            let duration = CMTime(seconds: asset.duration.seconds / 2, preferredTimescale: asset.duration.timescale)
            let start = asset.duration - duration
            let composition = AVMutableComposition()
            if let assetTrack = asset.tracks(withMediaType: .video).first {
                let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                do {
                    try track?.insertTimeRange(CMTimeRange(start: start, duration: duration), of: assetTrack, at: .zero)
                } catch {
                    fatalError("error: \(error)")
                }
            }
            
            if let assetTrack = asset.tracks(withMediaType: .audio).first {
                let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCFMessagePortReceiveTimeout)
                do {
                    try track?.insertTimeRange(CMTimeRange(start: start, duration: duration), of: assetTrack, at: .zero)
                } catch {
                    fatalError("error: \(error)")
                }
            }
            self.composition = composition
        }
        
        NotificationCenter.default.post(name: .editCommandCompletionNotification, object: self, userInfo: nil)
    }
}
