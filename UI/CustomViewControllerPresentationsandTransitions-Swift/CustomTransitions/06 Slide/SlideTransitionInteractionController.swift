//
//  SlideTransitionInteractionController.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit

class SlideTransitionInteractionController: UIPercentDrivenInteractiveTransition {
    let gestureRecognizer: UIPanGestureRecognizer
    weak var transitionContext: UIViewControllerContextTransitioning?
    var initialLocationInContainerView: CGPoint = .zero
    var initialTranslationInContainerView: CGPoint = .zero
    
    init(gestureRecognizer: UIPanGestureRecognizer) {
        self.gestureRecognizer = gestureRecognizer
        super.init()
        
        // Add self as an observer of the gesture recognizer so that this
        // object receives updates as the user moves their finger.
        gestureRecognizer.addTarget(self, action: #selector(self.gestureRecognizeDidUpdate(_:)))
    }
    
    deinit {
        print("🚧 \(self).\(#function)")
        gestureRecognizer.removeTarget(self, action: #selector(self.gestureRecognizeDidUpdate(_:)))
    }
    
    //| ----------------------------------------------------------------------------
    //! Action method for the gestureRecognizer.
    //
    @objc func gestureRecognizeDidUpdate(_ sender: UIPanGestureRecognizer) {
        switch sender.state {
        case .began:
            // The Began state is handled by AAPLSlideTransitionDelegate.  In
            // response to the gesture recognizer transitioning to this state,
            // it will trigger the transition.
            break
        case .changed:
            // -percentForGesture returns -1.f if the current position of the
            // touch along the horizontal axis has crossed over the initial
            // position.  See the comment in the
            // -beginInteractiveTransitionIfPossible: method of
            // AAPLSlideTransitionDelegate for details.
            if percentForGesture(sender) < 0 {
                cancel()
                // Need to remove our action from the gesture recognizer to
                // ensure it will not be called again before deallocation.
                gestureRecognizer.removeTarget(self, action: #selector(self.gestureRecognizeDidUpdate(_:)))
            } else {
                // We have been dragging! Update the transition context
                // accordingly.
                update(percentForGesture(gestureRecognizer))
            }
        case .ended:
            // Dragging has finished.
            // Complete or cancel, depending on how far we've dragged.
            if percentForGesture(sender) >= 0.4 {
                finish()
            } else {
                cancel()
            }
        default:
            // Something happened. cancel the transition.
            cancel()
        }
    }
    
    override func startInteractiveTransition(_ transitionContext: any UIViewControllerContextTransitioning) {
        // Save the transitionContext, initial location, and the translation within
        // the containing view.
        self.transitionContext = transitionContext
        initialLocationInContainerView = gestureRecognizer.location(in: transitionContext.containerView)
        initialTranslationInContainerView = gestureRecognizer.translation(in: transitionContext.containerView)
        
        super.startInteractiveTransition(transitionContext)
    }
    
    //| ----------------------------------------------------------------------------
    //! Returns the offset of the pan gesture recognizer from its initial location
    //! as a percentage of the transition container view's width.  This is
    //! the percent completed for the interactive transition.
    //
    func percentForGesture(_ gesture: UIPanGestureRecognizer) -> CGFloat {
        guard let transitionContainerView = transitionContext?.containerView else { return 0 }
        
        let translationInContainerView = gesture.translation(in: transitionContainerView)
        
        // If the direction of the current touch along the horizontal axis does not
        // match the initial direction, then the current touch position along
        // the horizontal axis has crossed over the initial position.  See the
        // comment in the -beginInteractiveTransitionIfPossible: method of
        // SlideTransitionDelegate.
        if (translationInContainerView.x > 0 && self.initialTranslationInContainerView.x < 0) ||
            (translationInContainerView.x < 0 && self.initialTranslationInContainerView.x > 0) {
            return -1
        }
        
        // Figure out what percentage we've traveled.
        return abs(translationInContainerView.x) / transitionContainerView.bounds.width
    }
}
