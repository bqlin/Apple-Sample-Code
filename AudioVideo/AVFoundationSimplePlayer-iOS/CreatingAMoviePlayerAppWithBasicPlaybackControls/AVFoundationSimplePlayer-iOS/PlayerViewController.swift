/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller containing a player view and some basic playback controls.
*/

import Foundation
import AVFoundation
import UIKit

class PlayerViewController: UIViewController {
    
    // MARK: Properties
    
    let player = AVPlayer()
    
    /**
     A formatter that provides a user-readable string for the start time and
     duration media time values displayed in the app's UI.
     */
    let timeRemainingFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.minute, .second]
        return formatter
    }()
    
    /**
     A token obtained from the player's
     `addPeriodicTimeObserverForInterval(_:queue:usingBlock:)` method.
     */
    private var timeObserverToken: Any?
    
    /**
     The `NSKeyValueObservation` for the KVO on `\AVPlayer.currentItem?.status`.
     */
    private var playerItemStatusObserver: NSKeyValueObservation?
    
    /**
     The `NSKeyValueObservation` for the KVO on
     `\AVPlayer.currentItem?.canPlayFastForward`.
     */
    private var playerItemFastForwardObserver: NSKeyValueObservation?
    
    /**
     The `NSKeyValueObservation` for the KVO on
     `\AVPlayer.currentItem?.canPlayReverse`.
     */
    private var playerItemReverseObserver: NSKeyValueObservation?
    
    /**
     The `NSKeyValueObservation` for the KVO on
     `\AVPlayer.currentItem?.canPlayFastReverse`.
     */
    private var playerItemFastReverseObserver: NSKeyValueObservation?
    
    /**
     The `NSKeyValueObservation` for the KVO on `\AVPlayer.timeControlStatus`.
     */
    private var playerTimeControlStatusObserver: NSKeyValueObservation?
    
    static let pauseButtonImageName = "PauseButton"
    static let playButtonImageName = "PlayButton"
    
    // MARK: - IBOutlet properties
    @IBOutlet weak var playerView: PlayerView!
    @IBOutlet weak var timeSlider: UISlider!
    @IBOutlet weak var startTimeLabel: UILabel!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var rewindButton: UIButton!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var fastForwardButton: UIButton!
    @IBOutlet weak var errorText: UILabel!
    
    // MARK: - View Controller
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let movieURL =
            Bundle.main.url(forResource: "video", withExtension: "m4v") else {
                return
        }
        // Create an asset instance to represent the media file.
        let asset = AVURLAsset(url: movieURL)
        
        loadPropertyValues(forAsset: asset)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        player.pause()
        
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        
        super.viewWillDisappear(animated)
    }
    
    // MARK: - Asset Property Handling
    
    /**
     Load the values of the specified asset keys (property names) before
     attempting playback.
     
     Asset initialization does not guarantee the availability of all the asset
     keys. Use the `AVAsynchronousKeyValueLoading` protocol to ask for values and
     get an answer back later through a completion handler rather than blocking
     the current thread while calculating a value.
     */
    func loadPropertyValues(forAsset newAsset: AVURLAsset) {
        /// Load and test the following asset keys before playback begins.
        let assetKeysRequiredToPlay = [
            /*
             You can initialize an instance of the player item with the asset
             if the `playable` property value equals `true`.
             
             If the `hasProtectedContent` property value equals `true`, the
             asset contains protected content and can't be played.
             */
            "playable",
            "hasProtectedContent"
        ]
        
        /*
         Using an `AVAsset` runs the risk of blocking the current thread (the
         main UI thread) while the system populates the properties. Defer such
         work until the system loads the properties you need.
         */
        newAsset.loadValuesAsynchronously(forKeys: assetKeysRequiredToPlay) {
            /*
             The asset invokes its completion handler on an arbitrary queue.
             Dispatch the handler to the main queue to avoid multiple threads
             using the internal state at the same time.
             */
            DispatchQueue.main.async {
                
                /*
                 Confirm the loading of all the assets keys and verify their
                 values.
                 */
                if self.validateValues(forKeys: assetKeysRequiredToPlay, forAsset: newAsset) {
                    
                    /*
                     Setup some key-value observers on the player to update the
                     app's user interface elements.
                     */
                    self.setupPlayerObservers()
                    
                    /*
                     Set the player for which the player view displays its
                     visual output.
                     
                     `AVPlayer` and `AVPlayerItem` are nonvisual objects,
                     meaning that on their own they can't present an asset’s
                     video onscreen. Use an `AVPlayerLayer` object to manage a
                     player's visual output. This example uses an
                     `AVPlayerLayer` for the view’s backing layer.
                     */
                    self.playerView.player = self.player
                    
                    /*
                     `AVPlayer` can't perform playback given just an `AVAsset`.
                     `AVAsset` only models the static aspects of the media, such
                     as its duration. To play an asset, you create an instance
                     of an `AVPlayerItem` and make it the player's current
                     item. This object models the timing and presentation state
                     of an asset played by an instance of `AVPlayer`.
                     */
                    self.player.replaceCurrentItem(with: AVPlayerItem(asset: newAsset))
                }
            }
        }
    }
    
    /**
     Confirm the successfull loading of all the asset's keys and verify their
     values.
     */
    func validateValues(forKeys keys: [String], forAsset newAsset: AVAsset) -> Bool {
        for key in keys {
            var error: NSError?
            if newAsset.statusOfValue(forKey: key, error: &error) == .failed {
                let stringFormat = NSLocalizedString("The media failed to load the key \"%@\"",
                                                     comment: "You can't use this AVAsset because one of it's keys failed to load.")
                
                let message = String.localizedStringWithFormat(stringFormat, key)
                handleErrorWithMessage(message, error: error)
                
                return false
            }
        }
        
        if !newAsset.isPlayable || newAsset.hasProtectedContent {
            /*
             You can't play the asset. Either the asset can't initialize a
             player item, or it contains protected content.
             */
            let message = NSLocalizedString("The media isn't playable or it contains protected content.",
                                            comment: "You can't use this AVAsset because it isn't playable or it contains protected content.")
            handleErrorWithMessage(message)
            return false
        }
        
        return true
    }
    
    // MARK: - Key-Value Observing
    
    /**
     Setup some key-value observers on the various player and player item
     properties required by the app such as the ability to play fast forward,
     reverse, and so on.
     
     The observers adjust the state of the sample's user interface elements
     based on the values of the observed properties.
     */
    /// - Tag: PeriodicTimeObserver
    func setupPlayerObservers() {
        /*
         Create an observer to toggle the play/pause button control icon to
         reflect the playback state of the player's `timeControStatus` property.
         */
        playerTimeControlStatusObserver = player.observe(\AVPlayer.timeControlStatus,
                                                         options: [.initial, .new]) { [unowned self] _, _ in
            DispatchQueue.main.async {
                self.setPlayPauseButtonImage()
            }
        }
        
        /*
         Create a periodic observer to update the movie player time slider
         during playback.
         */
        let interval = CMTime(value: 1, timescale: 2)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval,
                                                           queue: .main) { [unowned self] time in
            let timeElapsed = Float(time.seconds)
            self.timeSlider.value = timeElapsed
            self.startTimeLabel.text = self.createTimeString(time: timeElapsed)
        }
        
        /*
         Create an observer on the player's `canPlayFastForward` property to
         set the fast forward button enabled state.
         */
        playerItemFastForwardObserver = player.observe(\AVPlayer.currentItem?.canPlayFastForward,
                                                       options: [.new, .initial]) { [unowned self] player, _ in
            DispatchQueue.main.async {
                self.fastForwardButton.isEnabled = player.currentItem?.canPlayFastForward ?? false
            }
        }
        
        playerItemReverseObserver = player.observe(\AVPlayer.currentItem?.canPlayReverse,
                                                   options: [.new, .initial]) { [unowned self] player, _ in
            DispatchQueue.main.async {
                self.rewindButton.isEnabled = player.currentItem?.canPlayReverse ?? false
            }
        }
        
        playerItemFastReverseObserver = player.observe(\AVPlayer.currentItem?.canPlayFastReverse,
                                                       options: [.new, .initial]) { [unowned self] player, _ in
            DispatchQueue.main.async {
                self.rewindButton.isEnabled = player.currentItem?.canPlayFastReverse ?? false
            }
        }
        
        /*
         Create an observer on the player item `status` property to observe
         state changes as they occur. The `status` property indicates the
         playback readiness of the player item. Associating a player item with
         a player immediately begins enqueuing the item’s media and preparing it
         for playback, but you must wait until its status changes to
         `.readyToPlay` before it’s ready for use.
         */
        playerItemStatusObserver = player.observe(\AVPlayer.currentItem?.status, options: [.new, .initial]) { [unowned self] _, _ in
            DispatchQueue.main.async {
                /*
                 Configure the user interface elements for playback when the
                 player item's `status` changes to `readyToPlay`.
                 */
                self.updateUIforPlayerItemStatus()
            }
        }
    }
    
    // MARK: - IBActions
    @IBAction func togglePlay(_ sender: UIButton) {
        switch player.timeControlStatus {
        case .playing:
            // If the player is currently playing, pause it.
            player.pause()
        case .paused:
            /*
             If the player item already played to its end time, seek back to
             the beginning.
             */
            let currentItem = player.currentItem
            if currentItem?.currentTime() == currentItem?.duration {
                currentItem?.seek(to: .zero)
            }
            // The player is currently paused. Begin playback.
            player.play()
        default:
            player.pause()
        }
    }
    
    /// - Tag: SetReversePlayback
    @IBAction func playBackwards(_ sender: UIButton) {
        /*
         If the player item current time equals its beginning time, seek to the
         end.
         */
        if player.currentItem?.currentTime() == .zero {
            if let itemDuration = player.currentItem?.duration {
                player.currentItem?.seek(to: itemDuration)
            }
        }
        // Reverse no faster than -2.0.
        player.rate = max(player.rate - 2.0, -2.0)
    }
    
    /// - Tag: FastForwardPlayback
    @IBAction func playFastForward(_ sender: UIButton) {
        /*
         If the player item current time equals its end time, seek back to the
         beginning.
         */
        if player.currentItem?.currentTime() == player.currentItem?.duration {
            player.currentItem?.seek(to: .zero)
        }
        
        // Play fast forward no faster than 2.0.
        player.rate = min(player.rate + 2.0, 2.0)
    }
    
    /// - Tag: TimeSliderDidChange
    @IBAction func timeSliderDidChange(_ sender: UISlider) {
        let newTime = CMTime(seconds: Double(sender.value), preferredTimescale: 600)
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    // MARK: - Error Handling
    func handleErrorWithMessage(_ message: String, error: Error? = nil) {
        if let err = error {
            print("Error occurred with message: \(message), error: \(err).")
        }
        let alertTitle = NSLocalizedString("Error", comment: "Alert title for errors")
        
        let alert = UIAlertController(title: alertTitle, message: message,
                                      preferredStyle: UIAlertController.Style.alert)
        let alertActionTitle = NSLocalizedString("OK", comment: "OK on error alert")
        let alertAction = UIAlertAction(title: alertActionTitle, style: .default, handler: nil)
        alert.addAction(alertAction)
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: - Utilities
    func createTimeString(time: Float) -> String {
        let components = NSDateComponents()
        components.second = Int(max(0.0, time))
        return timeRemainingFormatter.string(from: components as DateComponents)!
    }
    
    /// Adjust the play/pause button image to reflect the current play state.
    func setPlayPauseButtonImage() {
        var buttonImage: UIImage?
        
        switch self.player.timeControlStatus {
        case .playing:
            buttonImage = UIImage(named: PlayerViewController.pauseButtonImageName)
        case .paused, .waitingToPlayAtSpecifiedRate:
            buttonImage = UIImage(named: PlayerViewController.playButtonImageName)
        @unknown default:
            buttonImage = UIImage(named: PlayerViewController.pauseButtonImageName)
        }
        guard let image = buttonImage else { return }
        self.playPauseButton.setImage(image, for: .normal)
    }
    
    func updateUIforPlayerItemStatus() {
        guard let currentItem = player.currentItem else { return }
        
        switch currentItem.status {
        case .failed:
            /*
             Display an error if the player item status property equals
             `.failed`.
             */
            playPauseButton.isEnabled = false
            timeSlider.isEnabled = false
            startTimeLabel.isEnabled = false
            durationLabel.isEnabled = false
            handleErrorWithMessage(currentItem.error?.localizedDescription ?? "", error: currentItem.error)
            
        case .readyToPlay:
            /*
             The player item status equals `readyToPlay`. Enable the play/pause
             button.
             */
            playPauseButton.isEnabled = true
            
            /*
             Update the time slider control, start time and duration labels for
             the player duration.
             */
            let newDurationSeconds = Float(currentItem.duration.seconds)
            
            let currentTime = Float(CMTimeGetSeconds(player.currentTime()))
            
            timeSlider.maximumValue = newDurationSeconds
            timeSlider.value = currentTime
            timeSlider.isEnabled = true
            startTimeLabel.isEnabled = true
            startTimeLabel.text = createTimeString(time: currentTime)
            durationLabel.isEnabled = true
            durationLabel.text = createTimeString(time: newDurationSeconds)
            
        default:
            playPauseButton.isEnabled = false
            timeSlider.isEnabled = false
            startTimeLabel.isEnabled = false
            durationLabel.isEnabled = false
        }
    }
}
