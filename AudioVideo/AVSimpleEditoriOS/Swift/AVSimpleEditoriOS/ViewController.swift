//
// Created by Bq Lin on 2021/8/12.
// Copyright © 2021 Bq. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
    @IBOutlet weak var playerView: PlayerView!
    @IBOutlet weak var timeSlider: UISlider!
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var timelabel: UILabel!
    @IBOutlet weak var loadingSpinner: UIActivityIndicatorView!
    
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var trimButton: UIButton!
    @IBOutlet weak var rotateButton: UIButton!
    @IBOutlet weak var cropButton: UIButton!
    @IBOutlet weak var addMusicButton: UIButton!
    @IBOutlet weak var addWatermarkButton: UIButton!
    @IBOutlet weak var exportButton: UIButton!
    @IBOutlet weak var resetButton: UIButton!
    
    let player = AVPlayer()
    var inputAsset: AVAsset!
    var notificationObservers = [NSObjectProtocol]()
    var kvObservations = [NSKeyValueObservation]()
    var timeObservation: Any?
    
    var composition: AVMutableComposition?
    var videoComposition: AVMutableVideoComposition?
    var audioMix: AVMutableAudioMix?
    var watermarkLayer: CALayer? {
        willSet {
            watermarkLayer?.removeFromSuperlayer()
        }
    }
    
    let exportCommand = ExportCommand()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        setupUI()
        loadAsset()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if let watermarkLayer = watermarkLayer, watermarkLayer.superlayer != nil {
            let videoRect = playerView.videoRect
            var t = CGAffineTransform.identity
            t = t.translatedBy(x: videoRect.minX, y: videoRect.minY)
            let scale = playerView.videoScale
            t = t.scaledBy(x: 1 / scale.width, y: 1 / scale.height)
            watermarkLayer.setAffineTransform(t)
        }
    }

    deinit {
        notificationObservers.forEach { (observer) in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers = []
        kvObservations.forEach { (observation) in
            observation.invalidate()
        }
        kvObservations = []
    }
}

extension ViewController {
    @objc func playPauseAction() {
        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }
    }
    
    @objc func editAction(_ sender: UIButton) {
        var command: Command?
        switch sender {
            case trimButton:
                command = TrimCommand()
            case rotateButton:
                command = RotateCommand()
            case cropButton:
                command = CropCommand()
            case addMusicButton:
                command = AddMusicCommand()
            case addWatermarkButton:
                command = AddWatermarkCommand()
            default:break
        }
        if let command = command {
            command.composition = composition
            command.videoComposition = videoComposition
            command.audioMix = audioMix
            command.perform(asset: inputAsset)
        }
    }
    
    @objc func exportAction(_ sender: UIButton) {
        exportWillBegin()
        
        exportCommand.perform(asset: inputAsset)
    }
    
    @objc func timeChangeAction(_ sender: UISlider) {
        guard let item = player.currentItem else { return }
        let duration = item.duration
        player.seek(to: CMTime(seconds: duration.seconds * Double(sender.value), preferredTimescale: duration.timescale), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    @objc func resetAction(_ sender: UIButton) {
        composition = nil
        videoComposition = nil
        audioMix = nil
        let url = Bundle.main.url(forResource: "Movie", withExtension: "m4v")!
        inputAsset = AVURLAsset(url: url)
        infoLabel.text = nil
        reloadPlayerView()
    }
}

extension ViewController {
    func setupUI() {
        loadingSpinner.isHidden = true
        exportButton.isEnabled = false
        timeSlider.isEnabled = false
        
        playPauseButton.addTarget(self, action: #selector(self.playPauseAction), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(self.exportAction(_:)), for: .touchUpInside)
        resetButton.addTarget(self, action: #selector(self.resetAction(_:)), for: .touchUpInside)
        [trimButton, rotateButton, cropButton, addMusicButton, addWatermarkButton].forEach {
            $0?.addTarget(self, action: #selector(self.editAction(_:)), for: .touchUpInside)
        }
        timeSlider.addTarget(self, action: #selector(self.timeChangeAction(_:)), for: .valueChanged)
    }
    
    func loadAsset() {
        let url = Bundle.main.url(forResource: "Movie", withExtension: "m4v")!
        let asset = AVURLAsset(url: url)
        let loadKeys = ["playable", "composable", "tracks", "duration"]
        asset.loadValuesAsynchronously(forKeys: loadKeys) {
            DispatchQueue.main.async {
                for key in loadKeys {
                    var error: NSError? = nil
                    asset.statusOfValue(forKey: key, error: &error)
                    if let error = error {
                        self.handleError(error)
                        return
                    }
                }
                self.setupPlayback(asset: asset)
            }
        }
        inputAsset = asset
        kvObservations.append(player.observe(\.currentItem?.status, options: [.initial, .new]) { (player, change) in
            var enable = false
            if let item = player.currentItem {
                switch item.status {
                    case .failed:
                        self.handleError(item.error!)
                    case .readyToPlay:
                        enable = true
                    default: break
                }
            }
            DispatchQueue.main.async {
                self.playPauseButton.isSelected = player.rate != 0
                self.playPauseButton.isEnabled = enable
                self.timeSlider.isEnabled = enable
            }
        })
        kvObservations.append(player.observe(\.rate, options: [.initial, .new]) { (player, change) in
            DispatchQueue.main.async {
                self.playPauseButton.isSelected = player.rate != 0
            }
        })
        timeObservation = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main, using: { [weak self](time) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let item = self.player.currentItem else { return }
                self.timeSlider.value = Float(time.seconds / item.duration.seconds)
                self.timelabel.text = "\(time.seconds) / \(item.duration.seconds)"
            }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main, using: { (notification) in
            self.player.seek(to: .zero)
        }))
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .editCommandCompletionNotification, object: nil, queue: .main) { [weak self] (notification) in
            guard let self = self else { return }
            guard let command = notification.object as? Command else { return }
            self.composition = command.composition
            self.videoComposition = command.videoComposition
            self.audioMix = command.audioMix
            self.watermarkLayer = command.watermarkLayer
            self.reloadPlayerView()
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .exportCommandCompletionNotification, object: nil, queue: .main) { [weak self] (notification) in
            guard let self = self else { return }
            let url = self.exportCommand.exportSession.outputURL!
            self.inputAsset = AVURLAsset(url: url)
            self.watermarkLayer = nil
            self.composition = nil
            self.videoComposition = nil
            self.audioMix = nil
            UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
            self.reloadPlayerView()
        })
    }
    
    func setupPlayback(asset: AVAsset) {
        guard asset.isPlayable, asset.isComposable, !asset.tracks(withMediaType: .video).isEmpty else {
            fatalError("asset不合法")
        }
        
        playerView.playerLayer.player = player
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
    }
    
    func reloadPlayerView() {
        videoComposition?.animationTool = nil
        let playerItem = AVPlayerItem(asset: self.composition ?? inputAsset)
        playerItem.videoComposition = videoComposition
        playerItem.audioMix = audioMix
        if let watermarkLayer = watermarkLayer {
            print("水印：\(watermarkLayer.frame)")
            // 添加图层后，后续不能再复用改layer，而是需要重新创建
            //playerView.layer.addSublayer(watermarkLayer)
            view.setNeedsLayout()
        }
        player.replaceCurrentItem(with: playerItem)
        
        exportButton.isEnabled = true
    }
    
    func exportWillBegin() {
        exportCommand.composition = composition
        exportCommand.videoComposition = videoComposition
        exportCommand.audioMix = audioMix
        
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] (timer) in
            guard let self = self else { return }
            
            let progress = self.exportCommand.exportSession.progress
            self.infoLabel.text = "导出进度：\(progress)"
            if progress == 1 {
                self.infoLabel.text = "导出成功"
                timer.invalidate()
            }
        }
        
        if let watermarkLayer = watermarkLayer, let videoComposition = videoComposition {
            watermarkLayer.removeFromSuperlayer()
            let parentLayer = CALayer()
            let videoLayer = CALayer()
            parentLayer.frame = CGRect(origin: .zero, size: videoComposition.renderSize)
            videoLayer.frame = parentLayer.frame
            parentLayer.addSublayer(videoLayer)
            //watermarkLayer.position = CGPoint(x: videoComposition.renderSize.width / 2, y: videoComposition.renderSize.height / 4)
            watermarkLayer.setAffineTransform(.identity)
            parentLayer.addSublayer(watermarkLayer)
            print("导出水印：\(watermarkLayer.frame)")
            parentLayer.isGeometryFlipped = true
            
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
        }
    }
    
    func handleError(_ error: Error) {
        let message = (error as NSError).localizedDescription
        DispatchQueue.main.async {
            self.infoLabel.text = "错误：\(message)"
        }
    }
}

