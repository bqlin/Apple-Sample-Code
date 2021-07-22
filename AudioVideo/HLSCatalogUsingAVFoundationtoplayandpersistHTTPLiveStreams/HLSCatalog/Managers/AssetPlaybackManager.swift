/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `AssetPlaybackManager` is the class that manages the playback of Assets in this sample using Key-value observing on various AVFoundation classes.
AssetPlaybackManager 是同时键值监听管理资产的播放
 */

import UIKit
import AVFoundation

class AssetPlaybackManager: NSObject {
    // MARK: Properties
    
    /// Singleton for AssetPlaybackManager.
    static let sharedManager = AssetPlaybackManager()
    
    private var observerContext = 0
    
    weak var delegate: AssetPlaybackDelegate?
    
    /// The instance of AVPlayer that will be used for playback of AssetPlaybackManager.playerItem.
    private let player = AVPlayer()
    
    /// A Bool tracking if the AVPlayerItem.status has changed to .readyToPlay for the current AssetPlaybackManager.playerItem.
	/// 当前播放项是否可以播放
    private var readyForPlayback = false
    
    /// The AVPlayerItem associated with AssetPlaybackManager.asset.urlAsset
	/// 与 AssetPlaybackManager.asset.urlAsset 关联的 AVPlayerItem
    private var playerItem: AVPlayerItem? {
        willSet {
            playerItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), context: &observerContext)
        }
        
        didSet {
            playerItem?.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.initial, .new], context: &observerContext)
        }
    }
    
    /// The Asset that is currently being loaded for playback.
    private var asset: Asset? {
        willSet {
            asset?.urlAsset.removeObserver(self, forKeyPath: #keyPath(AVURLAsset.isPlayable), context: &observerContext)
        }
        
        didSet {
            if let asset = asset {
                asset.urlAsset.addObserver(self, forKeyPath: #keyPath(AVURLAsset.isPlayable), options: [.initial, .new], context: &observerContext)
            }
            else {
                playerItem = nil
                player.replaceCurrentItem(with: nil)
                readyForPlayback = false
            }
        }
    }
    
    // MARK: Intitialization
    
    override private init() {
        super.init()
        player.addObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem), options: [.new], context: &observerContext)
    }
    
    deinit {
        player.removeObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem))
    }
    
    /**
     Replaces the currently playing `Asset`, if any, with a new `Asset`. If nil
     is passed, `AssetPlaybackManager` will handle unloading the existing `Asset`
     and handle KVO cleanup.
     */
    func setAssetForPlayback(_ asset: Asset?) {
        self.asset = asset
    }
    
     // MARK: KVO
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &observerContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        guard let keyPath = keyPath else {
            return
        }
        
        switch keyPath {
        case #keyPath(AVURLAsset.isPlayable):
            guard let asset = asset , asset.urlAsset.isPlayable == true else { return }
            
            playerItem = AVPlayerItem(asset: asset.urlAsset)
            player.replaceCurrentItem(with: playerItem)
        case #keyPath(AVPlayerItem.status):
            guard let playerItem = playerItem , playerItem.status == .readyToPlay else { return }
            
            if !readyForPlayback {
                readyForPlayback = true
                delegate?.streamPlaybackManager(self, playerReadyToPlay: player)
            }
        case #keyPath(AVPlayer.currentItem):
            delegate?.streamPlaybackManager(self, playerCurrentItemDidChange: player)
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
}

/// AssetPlaybackDelegate provides a common interface for AssetPlaybackManager to provide callbacks to its delegate.
protocol AssetPlaybackDelegate: class {
    
    /// This is called when the internal AVPlayer in AssetPlaybackManager is ready to start playback.
    func streamPlaybackManager(_ streamPlaybackManager: AssetPlaybackManager, playerReadyToPlay player: AVPlayer)
    
    /// This is called when the internal AVPlayer's currentItem has changed.
    func streamPlaybackManager(_ streamPlaybackManager: AssetPlaybackManager, playerCurrentItemDidChange player: AVPlayer)
}

