//
// Created by Bq Lin on 2021/8/10.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

class avTouchController: UIViewController {
    @IBOutlet weak var fileNameLabel: UILabel!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var ffwButton: UIButton!
    @IBOutlet weak var rewButton: UIButton!
    @IBOutlet weak var volumeSlider: UISlider!
    @IBOutlet weak var progressBar: UISlider!
    @IBOutlet weak var currentTimeLabel: UILabel!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var levelMeterView: CALevelMeter!
    
    var updateTimer: Timer?
    var player: AVAudioPlayer?
    var inBackground: Bool = false
    
    let SkipTime: TimeInterval = 1
    let SkipInterval: TimeInterval = 0.2
    
    var rewTimer: Timer?
    var ffwTimer: Timer?
    
    var notificationObservers = [NSObjectProtocol]()
    
    deinit {
        notificationObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
}

extension avTouchController {
    func makeTimeString(_ time: TimeInterval) -> String {
        String(format: "%d:%02d", Int(time / 60), Int(time) % 60)
    }
    
    func updateCurrentTimeForPlayer(_ player: AVAudioPlayer) {
        currentTimeLabel.text = makeTimeString(player.currentTime)
        progressBar.value = Float(player.currentTime)
    }
    
    func updateView(for player: AVAudioPlayer) {
        updateCurrentTimeForPlayer(player)
        
        updateTimer?.invalidate()
        playButton.isSelected = player.isPlaying
        if player.isPlaying {
            levelMeterView.player = player
            Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true, block: { [weak self] (timer) in
                guard let self = self else { return }
                guard let player = self.player else { return }
                self.updateCurrentTimeForPlayer(player)
            })
        } else {
            levelMeterView.player = nil
            updateTimer = nil
        }
    }
    
    func updateViewInBackground(for player: AVAudioPlayer) {
        updateCurrentTimeForPlayer(player)
        playButton.isSelected = player.isPlaying
    }
    
    func updateViewInfo(for player: AVAudioPlayer) {
        durationLabel.text = makeTimeString(player.duration)
        progressBar.maximumValue = Float(player.duration)
        volumeSlider.value = player.volume
    }
    
    func setup() {
        registerNotifications()
        playButton.addTarget(self, action: #selector(self.playPause), for: .touchUpInside)
        ffwButton.addTarget(self, action: #selector(self.ffwButtonPressed), for: .touchDown)
        ffwButton.addTarget(self, action: #selector(self.ffwButtonReleased), for: [.touchUpInside, .touchUpOutside, .touchDragOutside])
        rewButton.addTarget(self, action: #selector(self.rewButtonPressed), for: .touchDown)
        rewButton.addTarget(self, action: #selector(self.rewButtonReleased), for: [.touchUpInside, .touchUpOutside, .touchDragOutside])
        volumeSlider.addTarget(self, action: #selector(self.volumeSlideMoved(_:)), for: .valueChanged)
        progressBar.addTarget(self, action: #selector(self.progressSliderMoved(_:)), for: .valueChanged)
        
        let fileURL = Bundle.main.url(forResource: "sample", withExtension: "m4a")!
        
        let player = try! AVAudioPlayer(contentsOf: fileURL)
        self.player = player
        
        fileNameLabel.text = fileURL.lastPathComponent
        updateViewInfo(for: player)
        updateView(for: player)
        player.numberOfLoops = 1
        player.delegate = self
    }
}

extension avTouchController {
    @objc func rewind() {
        guard let player = player else { return }
        player.currentTime -= SkipTime
        updateCurrentTimeForPlayer(player)
    }
    
    @objc func rewButtonPressed() {
        rewTimer?.invalidate()
        rewTimer = Timer.scheduledTimer(withTimeInterval: SkipInterval, repeats: true, block: { [weak self] (_) in
            self?.rewind()
        })
    }
    
    @objc func rewButtonReleased() {
        rewTimer?.invalidate()
        rewTimer = nil
    }
    
    @objc func ffwd() {
        guard let player = player else { return }
        player.currentTime += SkipTime
        updateCurrentTimeForPlayer(player)
    }
    
    @objc func ffwButtonPressed() {
        ffwTimer?.invalidate()
        ffwTimer = Timer.scheduledTimer(withTimeInterval: SkipInterval, repeats: true, block: { [weak self] (_) in
            self?.ffwd()
        })
    }
    
    @objc func ffwButtonReleased() {
        ffwTimer?.invalidate()
        ffwTimer = nil
    }
    
    @objc func playPause() {
        guard let player = player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        updateView(for: player)
    }
    
    @objc func volumeSlideMoved(_ sender: UISlider) {
        player?.volume = sender.value
    }
    
    @objc func progressSliderMoved(_ sender: UISlider) {
        guard let player = player else { return }
        player.currentTime = TimeInterval(sender.value)
        updateCurrentTimeForPlayer(player)
    }
}

extension avTouchController {
    func registerNotifications() {
        notificationObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] (notificaiton) in
            guard let self = self else { return }
            self.inBackground = true
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] (notificaiton) in
            guard let self = self else { return }
            self.inBackground = false
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] (notificaiton) in
            guard let self = self else { return }
            
            print("routeChangeNotification: \(notificaiton)")
            guard let player = self.player else { return }
            if self.inBackground {
                self.updateViewInBackground(for: player)
            } else {
                self.updateView(for: player)
            }
        })
        //notificationObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] (notificaiton) in
        //    guard let self = self else { return }
        //
        //
        //})
    }
    
}

extension avTouchController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        player.currentTime = 0
        if inBackground {
            updateViewInBackground(for: player)
        } else {
            updateView(for: player)
        }
    }
}
