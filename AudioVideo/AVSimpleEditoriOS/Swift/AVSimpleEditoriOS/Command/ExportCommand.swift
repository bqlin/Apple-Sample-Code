//
// Created by Bq Lin on 2021/8/16.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import AVFoundation

class ExportCommand: Command {
    var exportSession: AVAssetExportSession!
    
    override func perform(asset: AVAsset) {
        let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        let outputUrl = URL(fileURLWithPath: dir).appendingPathComponent("output.mp4")
        try? FileManager.default.removeItem(at: outputUrl)
        
        guard let composition = composition else { return }
        exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1280x720)
        exportSession.videoComposition = videoComposition
        exportSession.audioMix = audioMix
        exportSession.outputURL = outputUrl
        exportSession.outputFileType = .mov
        
        exportSession.exportAsynchronously { [weak self] in
            guard let self = self else { return }
            switch self.exportSession.status {
                case .completed:
                    print("导出成功：\(outputUrl)")
                    NotificationCenter.default.post(name: .exportCommandCompletionNotification, object: self, userInfo: nil)
                case .failed:
                    print("导出失败：\(self.exportSession.error)")
                case .cancelled:
                    print("导出取消: \(self.exportSession.error)")
                default: break
            }
        }
    }
}
