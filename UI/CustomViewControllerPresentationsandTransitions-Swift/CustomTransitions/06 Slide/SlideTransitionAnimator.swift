//
//  SlideTransitionAnimator.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit

/// A transition animator that transitions between two view controllers in
///  a tab bar controller by sliding both view controllers in a given
///  direction.
class SlideTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    
    //! The value for this property determines which direction the view controllers
    //! slide during the transition.  This must be one of UIRectEdgeLeft or
    //! UIRectEdgeRight.
    let targetEdge: UIRectEdge
    
    init(targetEdge: UIRectEdge) {
        self.targetEdge = targetEdge
    }
    
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        0.35
    }
    
    //| ----------------------------------------------------------------------------
    //  Custom transitions within a UITabBarController follow the same
    //  conventions as those used for modal presentations.  Your animator will
    //  be given the incoming and outgoing view controllers along with a container
    //  view where both view controller's views will reside.  Your animator is
    //  tasked with animating the incoming view controller's view into the
    //  container view.  The frame of the incoming view controller's view is
    //  is expected to match the value returned from calling
    //  [transitionContext finalFrameForViewController:toViewController] when
    //  the transition is complete.
    //
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
        let fromView = transitionContext.view(forKey: .from)
        let toView = transitionContext.view(forKey: .to)
        
        let fromFrame = transitionContext.initialFrame(for: fromViewController)
        let toFrame = transitionContext.finalFrame(for: toViewController)
        
        // Based on the configured targetEdge, derive a normalized vector that will
        // be used to offset the frame of the view controllers.
        var offset = CGVector.zero
        switch targetEdge {
        case .left:
            offset = CGVector(dx: -1, dy: 0)
        case .right:
            offset = CGVector(dx: 1, dy: 0)
        default:
            assertionFailure("targetEdge must be one of UIRectEdgeLeft, or UIRectEdgeRight.")
        }
        
        // The toView starts off-screen and slides in as the fromView slides out.
        fromView?.frame = fromFrame
        toView?.frame = toFrame.offsetBy(
            dx: toFrame.width * offset.dx * -1,
            dy: toFrame.height * offset.dy * -1
        )
        
        // We are responsible for adding the incoming view to the containerView.
        if let toView {
            containerView.addSubview(toView)
        }
        
        let transitionDuration = transitionDuration(using: transitionContext)
        
        UIView.animate(withDuration: transitionDuration) {
            fromView?.frame = fromFrame.offsetBy(
                dx: fromFrame.width * offset.dx,
                dy: fromFrame.height * offset.dy
            )
            toView?.frame = toFrame
        } completion: { finished in
            let wasCancelled = transitionContext.transitionWasCancelled
            // When we complete, tell the transition context
            // passing along the BOOL that indicates whether the transition
            // finished or not.
            transitionContext.completeTransition(!wasCancelled)
        }

    }
}
