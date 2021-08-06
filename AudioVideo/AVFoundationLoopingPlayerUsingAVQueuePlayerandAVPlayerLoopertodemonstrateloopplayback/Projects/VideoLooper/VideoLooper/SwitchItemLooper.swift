//
// Created by Bq Lin on 2021/8/6.
// Copyright © 2021 Apple IMG Media Systems. All rights reserved.
//
// 使用AVPlayer切换item实现循环播放

import Foundation
import AVFoundation

class SwitchItemLooper: NSObject, Looper {
    // MARK: Types
    
    private struct ObserverContexts {
        static var urlAssetDurationKey = "duration"
        static var urlAssetPlayableKey = "playable"
    }
    
    // MARK: Properties
    
    private var player: AVPlayer?
    
    private var playerLayer: AVPlayerLayer?
    
    private var kvObservations = [NSKeyValueObservation]()
    private var notificationObservers = [NSObjectProtocol]()
    
    private var numberOfTimesPlayed = 0
    private let numberOfTimesToPlay: Int
    
    private let videoURL: URL
    
    // MARK: Looper
    
    deinit {
        print("\(self) - \(#function)")
    }
    
    required init(videoURL: URL, loopCount: Int) {
        self.videoURL = videoURL
        self.numberOfTimesToPlay = loopCount
        
        super.init()
    }
    
    func start(in parentLayer: CALayer) {
        stop()
        
        player = AVQueuePlayer()
        player?.actionAtItemEnd = .none // 关键！
        playerLayer = AVPlayerLayer(player: player)
        
        guard let playerLayer = playerLayer else { fatalError("Error creating player layer") }
        playerLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(playerLayer)
        
        let videoAsset = AVURLAsset(url: videoURL)
        
        videoAsset.loadValuesAsynchronously(forKeys: [ObserverContexts.urlAssetDurationKey, ObserverContexts.urlAssetPlayableKey]) {
            /*
             The asset invokes its completion handler on an arbitrary queue
             when loading is complete. Because we want to access our AVQueuePlayer
             in our ensuing set-up, we must dispatch our handler to the main
             queue.
             */
            DispatchQueue.main.async(execute: {
                var durationError: NSError?
                let durationStatus = videoAsset.statusOfValue(forKey: ObserverContexts.urlAssetDurationKey, error: &durationError)
                guard durationStatus == .loaded else { fatalError("Failed to load duration property with error: \(durationError!)") }
                
                var playableError: NSError?
                let playableStatus = videoAsset.statusOfValue(forKey: ObserverContexts.urlAssetPlayableKey, error: &playableError)
                guard playableStatus == .loaded else { fatalError("Failed to read playable duration property with error: \(playableError!)") }
                
                guard videoAsset.isPlayable else {
                    print("Can't loop since asset is not playable")
                    return
                }
                
                guard CMTimeCompare(videoAsset.duration, CMTime(value:1, timescale:100)) >= 0 else {
                    print("Can't loop since asset duration too short. Duration is(\(CMTimeGetSeconds(videoAsset.duration)) seconds")
                    return
                }
                
                self.player?.replaceCurrentItem(with: AVPlayerItem(asset: videoAsset))
                
                self.startObserving()
                self.numberOfTimesPlayed = 0
                self.player?.play()
            })
        }
    }
    
    func stop() {
        player?.pause()
        stopObserving()
        
        player?.replaceCurrentItem(with: nil)
        player = nil
        
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }
    
    // MARK: Convenience
    
    private func startObserving() {
        guard let player = player, kvObservations.isEmpty, notificationObservers.isEmpty else { return }
        
        kvObservations.append(player.observe(\.status, options: .new) { (player, change) in
            let newPlayerStatus = player.status
            print("newPlayerStatus: \(newPlayerStatus.description)")
            
            if newPlayerStatus == AVPlayer.Status.failed {
                print("End looping since player has failed with error: \(player.error!)")
                self.stop()
            }
        })
        kvObservations.append(player.observe(\.currentItem?.status, options: .new) { (player, change) in
            guard let newPlayerItemStatus = player.currentItem?.status else { return }
            print("newPlayerItemStatus: \(newPlayerItemStatus.description)")
            
            if newPlayerItemStatus == .failed {
                print("End looping since player item has failed with error: \(player.currentItem!.error!)")
                self.stop()
            }
        })
        
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { (notification) in
            if self.numberOfTimesToPlay > 0 {
                self.numberOfTimesPlayed = self.numberOfTimesPlayed + 1
                
                if self.numberOfTimesPlayed >= self.numberOfTimesToPlay {
                    print("Looped \(self.numberOfTimesToPlay) times. Stopping.");
                    self.stop()
                }
            }
            
            if let oldItem = self.player?.currentItem {
                oldItem.seek(to: .zero)
                //player.replaceCurrentItem(with: oldItem)
            }
        })
    }
    
    private func stopObserving() {
        kvObservations.forEach { (observation) in
            observation.invalidate()
        }
        kvObservations = []
        
        notificationObservers.forEach { (observer) in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers = []
    }
}

extension AVPlayer.Status {
    var description: String {
        switch self {
            case .failed:
                return "failed"
            case .readyToPlay:
                return "readyToPlay"
            case .unknown:
                return "unknown"
            @unknown default:
                fatalError()
        }
    }
}

extension AVPlayerItem.Status {
    var description: String {
        switch self {
            case .failed:
                return "failed"
            case .readyToPlay:
                return "readyToPlay"
            case .unknown:
                return "unknown"
            @unknown default:
                fatalError()
        }
    }
}
