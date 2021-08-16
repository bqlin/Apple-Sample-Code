//
// Created by Bq Lin on 2021/8/16.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import AVFoundation

class Command: NSObject {
    static let editCommandCompletionNotification = ""
    static let exportCommandCompletionNotification = ""
    
    var composition: AVMutableComposition
    var videoComposition: AVMutableVideoComposition
    var audioMix: AVMutableAudioMix
    var watermarkLayer: CALayer?
    
    init(composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, audioMix: AVMutableAudioMix) {
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        super.init()
    }
    
    func perform(asset: AVAsset) {
        doesNotRecognizeSelector(#function)
    }
}
