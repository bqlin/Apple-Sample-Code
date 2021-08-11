//
// Created by Bq Lin on 2021/8/10.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import UIKit
import AudioToolbox
import AVFoundation

class CALevelMeter: UIView {
    var updateTimer: CADisplayLink?
    var showsPeaks: Bool = true
    var isVertical: Bool = false
    var useGL: Bool = true
    var channelNumbers: [Int] = [0] {
        didSet {
            layoutSubLevelMeters()
        }
    }
    
    var player: AVAudioPlayer! {
        didSet {
            guard let player = player else {
                subLevelMeters.forEach{ $0.setNeedsDisplay() }
                return
            }
            if oldValue == nil {
                updateTimer?.invalidate()
                updateTimer = CADisplayLink(target: self, selector: #selector(self.refresh))
                updateTimer?.add(to: .current, forMode: .default)
            } else {
                peakFalloffLastFire = CFAbsoluteTimeGetCurrent()
            }
            
            player.isMeteringEnabled = true
            let numberOfChannels = player.numberOfChannels
            if numberOfChannels != channelNumbers.count {
                channelNumbers = Array(0 ..< min(numberOfChannels, 2))
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    deinit {
        updateTimer?.invalidate()
        notificationObservers.forEach{ NotificationCenter.default.removeObserver($0) }
        notificationObservers = []
    }
    
    func pauseTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    func resumeTimer() {
        guard player != nil else { return }
        updateTimer?.invalidate()
        updateTimer = CADisplayLink(target: self, selector: #selector(self.refresh))
        updateTimer?.add(to: .current, forMode: .default)
    }
    
    let meterTable = MeterTable()
    func commonInit() {
        isVertical = frame.width < frame.height
        layoutSubLevelMeters()
        registerForBackgroundNotifications()
    }
    
    var subLevelMeters: [LevelMeter] = []
    func layoutSubLevelMeters() {
        subLevelMeters.forEach { $0.removeFromSuperview() }
        subLevelMeters = []
        
        var totalRect: CGRect
        var meters = [LevelMeter]()
        if isVertical {
            totalRect = CGRect(x: 0, y: 0, width: frame.width + 2, height: frame.height)
        } else {
            totalRect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height + 2)
        }
        
        for i in 0 ..< channelNumbers.count {
            var fr: CGRect
            
            if isVertical {
                fr = CGRect(x: totalRect.minX + (CGFloat(i) / CGFloat(channelNumbers.count)) * totalRect.width, y: totalRect.minY, width: totalRect.width / CGFloat(channelNumbers.count) - 2, height: totalRect.height)
            } else {
                fr = CGRect(x: totalRect.minX, y: totalRect.minY + CGFloat(i) / CGFloat(channelNumbers.count) * totalRect.height, width: totalRect.width, height: totalRect.height / CGFloat(channelNumbers.count) - 2)
            }
            
            let meter: LevelMeter = useGL ? GLLevelMeter(frame: fr) : LevelMeter(frame: fr)
            meter.numLights = 30
            meter.isVertical = isVertical
            meters.append(meter)
            addSubview(meter)
        }
        subLevelMeters = meters
    }
    
    let PeakFalloffPerSec: CGFloat = 0.7
    let LevelFalloffPerSec: CGFloat = 0.8
    var peakFalloffLastFire: CFAbsoluteTime = 0
    @objc func refresh() {
        if player == nil {
            var maxLvl: CGFloat = -1;
            let thisFire = CFAbsoluteTimeGetCurrent()
            let timePassed = thisFire - peakFalloffLastFire
            for meter in subLevelMeters {
                var newPeak, newLevel: CGFloat
                newLevel = meter.level - CGFloat(timePassed) * LevelFalloffPerSec
                newLevel = max(newLevel, 0)
                meter.level = newLevel
                
                if showsPeaks {
                    newPeak = meter.peakLevel - CGFloat(timePassed) * LevelFalloffPerSec
                    newPeak = max(newPeak, 0)
                    meter.peakLevel = newPeak
                    maxLvl = max(maxLvl, newPeak)
                } else {
                    maxLvl = max(maxLvl, newLevel)
                }
                meter.setNeedsDisplay()
            }
            
            if maxLvl <= 0 {
                updateTimer?.invalidate()
                updateTimer = nil
            }
            
            peakFalloffLastFire = thisFire
        } else {
            player.updateMeters()
            for i in 0 ..< channelNumbers.count {
                let channelIdx = channelNumbers[i]
                let channelMeter = subLevelMeters[channelIdx]
                
                assert(channelIdx < channelNumbers.count)
                assert(channelIdx < 128)
                
                channelMeter.level = CGFloat(meterTable.value(at: Double(player.averagePower(forChannel: i))))
                if showsPeaks {
                    channelMeter.peakLevel = CGFloat(meterTable.value(at: Double(player.peakPower(forChannel: i))))
                } else {
                    channelMeter.peakLevel = 0
                }
                channelMeter.setNeedsDisplay()
            }
        }
    }
    
    var notificationObservers = [NSObjectProtocol]()
    func registerForBackgroundNotifications() {
        notificationObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { (notification) in
            
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { (notification) in
            
        })
    }
}
