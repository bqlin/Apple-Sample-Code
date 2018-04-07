/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Demonstrates displaying text above the navigation bar.
 */

import UIKit

class NavigationPromptViewController: UIViewController {
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		// There is a bug in iOS 7.x (fixed in iOS 8) which causes the
        // topLayoutGuide to not be properly resized if the prompt is set before
        // -viewDidAppear: is called. This may result in the navigation bar
        // improperly overlapping your content.  For this reason, you should
        // avoid configuring the prompt in your storyboard and instead configure
        // it programmatically in -viewDidAppear: if your application deploys to iOS 7.
		//
        navigationItem.prompt = "Navigation prompts appear at the top."
    }
}
