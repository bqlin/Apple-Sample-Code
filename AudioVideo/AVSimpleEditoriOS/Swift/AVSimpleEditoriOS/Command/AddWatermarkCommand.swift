//
// Created by Bq Lin on 2021/8/16.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

class AddWatermarkCommand: Command {
    override func perform(asset: AVAsset) {
        if composition == nil {
            composition = Command.makeCompostion(asset: asset)
        }
        guard let composition = composition else { return }
        
        // 创建水印图层
        if videoComposition == nil {
            videoComposition = Command.makeVideoComposition(compostion: composition)
        }
        guard let videoComposition = videoComposition else { return }
        let videoSize = videoComposition.renderSize
        watermarkLayer = makeWatermarkLayer(videoSize: videoSize)

        NotificationCenter.default.post(name: .editCommandCompletionNotification, object: self, userInfo: nil)
    }
    
    // 构建一个文字图层
    func makeWatermarkLayer(videoSize: CGSize) -> CALayer {
        let watermarkLayer = CALayer()
        watermarkLayer.borderColor = UIColor.yellow.cgColor
        watermarkLayer.borderWidth = 1
        
        // 文字图层
        let titleLayer = CATextLayer()
        titleLayer.string = "Simple Editor"
        titleLayer.foregroundColor = UIColor.white.cgColor
        titleLayer.shadowOpacity = 0.5
        titleLayer.alignmentMode = .center
        titleLayer.bounds = CGRect(x: 0, y: 0, width: videoSize.width / 2, height: videoSize.height / 2)
        titleLayer.borderColor = UIColor.red.cgColor
        titleLayer.borderWidth = 1
        
        watermarkLayer.addSublayer(titleLayer)
        return watermarkLayer
    }
}
