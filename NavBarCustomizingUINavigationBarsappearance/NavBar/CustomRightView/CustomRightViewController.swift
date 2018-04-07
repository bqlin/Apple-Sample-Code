/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Demonstrates configuring various types of controls as the right
  bar item of the navigation bar.
 */

import UIKit

class CustomRightViewController: UIViewController {
    
    struct SegmentedControl {
        static let textButton = 0
        static let imageButton = 1
        static let controlButton = 2
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    /**
     *  IBAction for the segemented control.
     */
    @IBAction func changeRightBarItem(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case SegmentedControl.textButton:
            // Add a custom add button as the nav bar's custom right view
            let addButton = UIBarButtonItem(title: NSLocalizedString("AddTitle", comment: ""),
                                            style: .plain,
                                            target: self,
                                            action: #selector(action(_:)))
            navigationItem.rightBarButtonItem = addButton
            
        case SegmentedControl.imageButton:
            // add our custom image button as the nav bar's custom right view
            let emailButton = UIBarButtonItem(image: #imageLiteral(resourceName: "Email"),
                                              style: .plain,
                                              target: self,
                                              action: #selector(action(_:)))
            navigationItem.rightBarButtonItem = emailButton
            
        case SegmentedControl.controlButton:
            // "Segmented" control to the right
            let segmentedControl = UISegmentedControl(items: [
                #imageLiteral(resourceName: "UpArrow"),
                #imageLiteral(resourceName: "DownArrow")
            ])
            
            segmentedControl.addTarget(self, action: #selector(action), for: .valueChanged)
            segmentedControl.frame = CGRect(x: 0, y: 0, width: 90, height: 30)
            segmentedControl.isMomentary = true
            
            let segmentBarItem = UIBarButtonItem(customView: segmentedControl)
            navigationItem.rightBarButtonItem = segmentBarItem
            
        default:
            break
        }
    }
    
    // MARK: - Actions
    
    /**
     *  IBAction for the various bar button items shown in this example.
     */
    @IBAction func action(_ sender: AnyObject) {
        print("CustomRightViewController IBAction invoked!")
    }
}
