//
//  CrossDissolveFirstViewController.swift
//  
//  Created by Bq on 2025/10/24.
//

import Foundation
import UIKit

/// The initial view controller for the Cross Dissolve demo.
class CrossDissolveFirstViewController: DemoInitialViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Cross Dissolve"
    }
    
    @objc override func buttonAction(_ sender: AnyObject) {
        // CrossDissolveTransitionAnimator 虽然定义简单，但代码量转嫁给了调用方。
        // For the sake of example, this demo implements the presentation and
        // dismissal logic completely in code.  Take a look at the later demos
        // to learn how to integrate custom transitions with segues.
        let secondViewController = DemoPresentedViewController()
        
        // Setting the modalPresentationStyle to FullScreen enables the
        // <ContextTransitioning> to provide more accurate initial and final frames
        // of the participating view controllers
        secondViewController.modalPresentationStyle = .fullScreen
        // secondViewController.modalPresentationStyle = .overFullScreen
        
        // The transitioning delegate can supply a custom animation controller
        // that will be used to animate the incoming view controller.
        secondViewController.transitioningDelegate = self
        present(secondViewController, animated: true)
    }
}

extension CrossDissolveFirstViewController: UIViewControllerTransitioningDelegate {
    //| ----------------------------------------------------------------------------
    //  The system calls this method on the presented view controller's
    //  transitioningDelegate to retrieve the animator object used for animating
    //  the presentation of the incoming view controller.  Your implementation is
    //  expected to return an object that conforms to the
    //  UIViewControllerAnimatedTransitioning protocol, or nil if the default
    //  presentation animation should be used.
    //
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        CrossDissolveTransitionAnimator()
    }
    
    //| ----------------------------------------------------------------------------
    //  The system calls this method on the presented view controller's
    //  transitioningDelegate to retrieve the animator object used for animating
    //  the dismissal of the presented view controller.  Your implementation is
    //  expected to return an object that conforms to the
    //  UIViewControllerAnimatedTransitioning protocol, or nil if the default
    //  dismissal animation should be used.
    //
    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        CrossDissolveTransitionAnimator()
    }
}
