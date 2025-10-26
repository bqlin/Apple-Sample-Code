//
//  CustomPresentationFirstViewController.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit

/// The initial view controller for the Custom Presentation demo.
class CustomPresentationFirstViewController: DemoInitialViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Custom Presentation"
    }
    
    @objc override func buttonAction(_ sender: AnyObject) {
        let secondViewController = CustomPresentationSecondViewController()
        // For presentations which will use a custom presentation controller,
        // it is possible for that presentation controller to also be the
        // transitioningDelegate.  This avoids introducing another object
        // or implementing <UIViewControllerTransitioningDelegate> in the
        // source view controller.
        //
        // transitioningDelegate does not hold a strong reference to its
        // destination object.  To prevent presentationController from being
        // released prior to calling -presentViewController:animated:completion:
        // the NS_VALID_UNTIL_END_OF_SCOPE attribute is appended to the declaration.
        // 这里的好处是不用自身不用在额外持有过渡相关的变量
        let presentationController = CustomPresentationController(presentedViewController: secondViewController, presenting: self)
        secondViewController.transitioningDelegate = presentationController
        present(secondViewController, animated: true)
    }
}
