//
//  AdaptivePresentationFirstViewController.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit

/// The initial view controller for the Adaptive Presentation demo.
class AdaptivePresentationFirstViewController: DemoInitialViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Adaptive Presentation"
    }
    
    override func buttonAction(_ sender: AnyObject) {
        let sourceViewController = self
        let destinationViewController = AdaptivePresentationSecondViewController()
        
        // For presentations which will use a custom presentation controller,
        // it is possible for that presentation controller to also be the
        // transitioningDelegate.
        //
        // transitioningDelegate does not hold a strong reference to its
        // destination object.  To prevent presentationController from being
        // released prior to calling -presentViewController:animated:completion:
        // the NS_VALID_UNTIL_END_OF_SCOPE attribute is appended to the declaration.
        let presentationController = AdaptivePresentationController(presentedViewController: destinationViewController, presenting: sourceViewController)
        destinationViewController.transitioningDelegate = presentationController
        sourceViewController.present(destinationViewController, animated: true)
    }
}
