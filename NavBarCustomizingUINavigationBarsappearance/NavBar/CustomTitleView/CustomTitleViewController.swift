/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Demonstrates configuring the navigation bar to use a UIView
  as the title.
 */

import UIKit

class CustomTitleViewController: UIViewController {
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let segmentTextContent = [
            NSLocalizedString("Image", comment: ""),
            NSLocalizedString("Text", comment: ""),
            NSLocalizedString("Video", comment: "")
        ]
        
        // Segmented control as the custom title view
        let segmentedControl = UISegmentedControl(items: segmentTextContent)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.autoresizingMask = .flexibleWidth
        segmentedControl.frame = CGRect(x: 0, y: 0, width: 400, height: 30)
        segmentedControl.addTarget(self, action: #selector(action(_:)), for: .valueChanged)
        
        self.navigationItem.titleView = segmentedControl
    }
    
    // MARK: - Actions
    
    /**
     *  IBAction for the segmented control.
     */
    @IBAction func action(_ sender: AnyObject) {
        print("CustomTitleViewController IBAction invoked!")
    }
}
