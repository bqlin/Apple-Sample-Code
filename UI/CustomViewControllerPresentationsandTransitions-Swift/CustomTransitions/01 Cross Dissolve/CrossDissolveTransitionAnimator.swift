//
//  CrossDissolveTransitionAnimator.swift
//  
//  Created by Bq on 2025/10/24.
//

import Foundation
import UIKit

/// A transition animator that performs a cross dissolve transition between
///  two view controllers.
class CrossDissolveTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        0.35
    }
    
    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        let fromViewController = transitionContext.viewController(forKey: .from)!
        let toViewController = transitionContext.viewController(forKey: .to)!
        
        let containerView = transitionContext.containerView
        
        // For a Presentation:
        //      fromView = The presenting view.
        //      toView   = The presented view.
        // For a Dismissal:
        //      fromView = The presented view.
        //      toView   = The presenting view.
        var fromView: UIView?
        var toView: UIView?
        
        // In iOS 8, the viewForKey: method was introduced to get views that the
        // animator manipulates.  This method should be preferred over accessing
        // the view of the fromViewController/toViewController directly.
        // It may return nil whenever the animator should not touch the view
        // (based on the presentation style of the incoming view controller).
        // It may also return a different view for the animator to animate.
        //
        // Imagine that you are implementing a presentation similar to form sheet.
        // In this case you would want to add some shadow or decoration around the
        // presented view controller's view. The animator will animate the
        // decoration view instead and the presented view controller's view will
        // be a child of the decoration view.
        if transitionContext.responds(to: #selector(transitionContext.view(forKey:))) {
            fromView = transitionContext.view(forKey: .from)
            toView = transitionContext.view(forKey: .to)
        } else {
            fromView = fromViewController.view
            toView = toViewController.view
        }
        
        // 注意这里 fromView 配置的是初始 frame，toView 配置的结束 frame
        fromView?.frame = transitionContext.initialFrame(for: fromViewController)
        toView?.frame = transitionContext.finalFrame(for: toViewController)
        
        fromView?.alpha = 1
        toView?.alpha = 0
        
        // We are responsible for adding the incoming view to the containerView
        // for the presentation/dismissal.
        if let toView {
            containerView.addSubview(toView)
        }
        
        let transitionDuration = transitionDuration(using: transitionContext)
        
        UIView.animate(withDuration: transitionDuration) {
            fromView?.alpha = 0
            toView?.alpha = 1
        } completion: { finished in
            // When we complete, tell the transition context
            // passing along the BOOL that indicates whether the transition
            // finished or not.
            let wasCancelled = transitionContext.transitionWasCancelled
            transitionContext.completeTransition(!wasCancelled)
        }
    }
}
