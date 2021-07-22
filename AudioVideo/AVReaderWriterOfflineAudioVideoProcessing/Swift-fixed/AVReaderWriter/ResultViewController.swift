/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Defines the view controller for the result scene.
*/

import UIKit
import AVKit
import AVFoundation

class ResultViewController: UIViewController {
    // MARK: Properties
    
    private static let embedSegueName = "playerViewController"
    
    let player = AVPlayer()

	var outputURL: URL? {
		// Update `playerViewController` with new output movie.
		didSet {
			let playerItem: AVPlayerItem?
			
			if let outputURL = outputURL {
				playerItem = AVPlayerItem(url: outputURL)
			}
			else {
				playerItem = nil
			}
			
			player.replaceCurrentItem(with: playerItem)
		}
	}
	
    // MARK: Segue Handling
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == ResultViewController.embedSegueName {
			// This segue fires before `viewDidLoad()` is invoked.
			let playerViewController = segue.destination as! AVPlayerViewController
            
            playerViewController.player = player
		}
		else {
            // Stop playback when transitioning to next scene.
			player.pause()
		}
	}
}
