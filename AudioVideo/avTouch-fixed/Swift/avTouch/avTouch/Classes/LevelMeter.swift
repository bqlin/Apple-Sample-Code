//
// Created by Bq Lin on 2021/8/10.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import UIKit

extension LevelMeter {
    struct ColorThreshold: Comparable {
        /// A value from 0 - 1. The maximum value shown in this color
        var maxValue: CGFloat
        
        /// A UIColor to be used for this value range
        var color: UIColor
        
        static func < (lhs: ColorThreshold, rhs: ColorThreshold) -> Bool {
            lhs.maxValue < lhs.maxValue
        }
        
        static func == (lhs: ColorThreshold, rhs: ColorThreshold) -> Bool {
            lhs.maxValue == lhs.maxValue
        }
    }
}

class LevelMeter: UIView {
    var numLights: Int = 0
    var level, peakLevel: CGFloat!
    var colorThresholds = [ColorThreshold]()
    var isVertical: Bool = false
    var isVariableLightIntensity: Bool = true
    var bgColor, borderColor: UIColor?
    var scaleFactor: CGFloat = 2
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    let meterTable = MeterTable()
    func commonInit() {
        level = 0
        peakLevel = 0
        bgColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        borderColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        colorThresholds = [
            ColorThreshold(maxValue: 0.25, color: UIColor(red: 0, green: 1, blue: 0, alpha: 1)),
            ColorThreshold(maxValue: 0.8, color: UIColor(red: 1, green: 1, blue: 0, alpha:1)),
            ColorThreshold(maxValue: 1, color: UIColor(red: 1, green: 0, blue: 0, alpha: 1)),
        ]
        isVertical = frame.width < frame.height
    }
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cs = CGColorSpaceCreateDeviceRGB()
        var bds = self.bounds
        
        if (isVertical) {
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            bds = bounds
        } else {
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.rotate(by: -.pi / 2)
            bds = CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width)
        }
        
        ctx.setFillColorSpace(cs)
        ctx.setStrokeColorSpace(cs)
        
        if numLights == 0 {
            var currentTop: CGFloat = 0
            
            if let color = bgColor {
                color.set()
                ctx.fill(bds)
            }
            
            for thresh in colorThresholds {
                let val = min(thresh.maxValue, level)
                let rect = CGRect(x: 0, y: bds.height * currentTop, width: bds.width, height: bds.height * (val - currentTop))
                thresh.color.set()
                ctx.fill(rect)
                
                guard level >= thresh.maxValue else { break }
                currentTop = val
            }
            
            if let color = borderColor {
                color.set()
                ctx.stroke(bds.insetBy(dx: 0.5, dy: 0.5))
            }
        } else {
            var lightMinVal: CGFloat = 0
            var insetAmount, lightVSpace: CGFloat
            lightVSpace = bds.height / CGFloat(numLights)
            if lightVSpace < 4 {
                insetAmount = 0
            } else if lightVSpace < 8 {
                insetAmount = 0.5
            } else {
                insetAmount = 1
            }
            
            var peakLight = -1
            if peakLevel > 0 {
                peakLight = Int(peakLevel * CGFloat(numLights))
                if peakLight >= numLights {
                    peakLight = numLights - 1
                }
            }
            
            for light_i in 0 ..< numLights {
                let lightMaxVal = CGFloat(light_i + 1) / CGFloat(numLights)
                var lightIntensity: CGFloat
                
                if light_i == peakLight {
                    lightIntensity = 1
                } else {
                    lightIntensity = (level - lightMinVal) / (lightMaxVal - lightMinVal)
                    lightIntensity = min(max(lightIntensity, 0), 1)
                    if !isVariableLightIntensity && lightIntensity > 0 {
                        lightIntensity = 1
                    }
                }
                
                var lightColor = colorThresholds[0].color
                for color_i in 0 ..< colorThresholds.count - 1 {
                    let thisThresh = colorThresholds[color_i]
                    let nextThresh = colorThresholds[color_i + 1]
                    if thisThresh.maxValue <= lightMaxVal {
                        lightColor = nextThresh.color
                    }
                }
                
                var lightRect = CGRect(x: 0, y: bds.height * CGFloat(light_i) / CGFloat(numLights), width: bds.width, height: bds.height / CGFloat(numLights))
                lightRect = lightRect.insetBy(dx: insetAmount, dy: insetAmount)
                
                if let color = bgColor {
                    color.set()
                    ctx.fill(lightRect)
                }
                
                if lightIntensity == 1.0 {
                    lightColor.set()
                    ctx.fill(lightRect)
                } else if lightIntensity > 0 {
                    lightColor.withAlphaComponent(lightIntensity).setFill()
                    ctx.fill(lightRect)
                }
                
                if let color = borderColor {
                    color.set()
                    ctx.stroke(lightRect.insetBy(dx: 0.5, dy: 0.5))
                }
                lightMinVal = lightMaxVal
            }
        }
    }
}
