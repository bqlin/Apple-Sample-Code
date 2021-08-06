/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A player view that presents an AVPlayer object's output in an AVPlayerLayer.
*/

import UIKit
import AVFoundation

/// A simple `UIView` subclass backed by an `AVPlayerLayer` layer.
class PlayerView: UIView {
    
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
}
