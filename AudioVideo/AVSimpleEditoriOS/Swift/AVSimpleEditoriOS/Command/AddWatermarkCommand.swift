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
        // watermarkLayer.frame = CGRect(origin: .zero, size: videoSize)
        watermarkLayer.addSublayer(makeGuidelineLayer(videoSize: videoSize))
        
        // 文字图层
        watermarkLayer.addSublayer(makeTextLayer(videoSize: videoSize))
        return watermarkLayer
    }
    
    func makeGuidelineLayer(videoSize: CGSize) -> CALayer {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.yellow.withAlphaComponent(0.5).cgColor
        layer.fillColor = UIColor.clear.cgColor
        let lineWidth: CGFloat = 2
        layer.lineWidth = lineWidth
        layer.lineDashPhase = lineWidth
        layer.lineDashPattern = [10, 10]
        let path = UIBezierPath()
        path.append(.init(rect: CGRect(x: lineWidth / 2, y: lineWidth / 2, width: videoSize.width - lineWidth, height: videoSize.height - lineWidth)))
        path.move(to: .init(x: 0, y: videoSize.height / 2))
        path.addLine(to: .init(x: videoSize.width, y: videoSize.height / 2))
        path.move(to: .init(x: videoSize.width / 2, y: 0))
        path.addLine(to: .init(x: videoSize.width / 2, y: videoSize.height))
        layer.path = path.cgPath
        
        return layer
    }
    
    func makeTextLayer(videoSize: CGSize) -> CALayer {
        let titleLayer = CATextLayer()
        titleLayer.string = "Simple Editor"
        titleLayer.foregroundColor = UIColor.white.cgColor
        titleLayer.shadowOpacity = 0.5
        titleLayer.alignmentMode = .center
        titleLayer.frame = CGRect(x: 0, y: 0, width: videoSize.width / 2, height: videoSize.height / 2)
        titleLayer.position = CGPoint(x: videoSize.width / 2, y: videoSize.height / 2)
        titleLayer.borderColor = UIColor.red.cgColor
        titleLayer.borderWidth = 2
        
        return titleLayer
    }
    
    func makeTextLayer2(videoSize: CGSize) -> CALayer {
        let label = UILabel()
        label.text = "Simple Editor"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 20)
        label.sizeToFit()
        label.center = CGPoint(x: videoSize.width / 2, y: videoSize.height / 2)
        
        let titleLayer = label.layer
        titleLayer.shadowOpacity = 0.5
        titleLayer.borderColor = UIColor.red.cgColor
        titleLayer.borderWidth = 2
        
        return titleLayer
    }
}
