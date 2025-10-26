//
//  CheckerboardFirstViewController.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit

/// The initial view controller for the Custom Presentation demo.
class CheckerboardFirstViewController: DemoInitialViewController, UINavigationControllerDelegate {
    
    var originalNavigationDelegate: UINavigationControllerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Checkerboard"
        button.setTitle("Push with Custom Transition", for: .normal)
        
        originalNavigationDelegate = navigationController?.delegate
        navigationController?.delegate = self
    }
    
    override func buttonAction(_ sender: AnyObject) {
        navigationController?.pushViewController(DemoPresentedViewController(), animated: true)
    }
    
    // MARK: - UINavigationControllerDelegate
    
    //| ----------------------------------------------------------------------------
    //  The navigation controller tries to invoke this method on its delegate to
    //  retrieve an animator object to be used for animating the transition to the
    //  incoming view controller.  Your implementation is expected to return an
    //  object that conforms to the UIViewControllerAnimatedTransitioning protocol,
    //  or nil if the transition should use the navigation controller's default
    //  push/pop animation.
    //
    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        // 让过渡效果仅在下一级页面生效
        if fromVC == self, operation == .pop {
            navigationController.delegate = originalNavigationDelegate
            return originalNavigationDelegate?.navigationController?(navigationController, animationControllerFor: operation, from: fromVC, to: toVC)
        }
        return CheckerboardTransitionAnimator()
    }
}
