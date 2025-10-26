//
//  SwipeTransitionInteractionController.swift
//  
//  Created by Bq on 2025/10/24.
//

import Foundation
import UIKit

/// The interaction controller for the Swipe demo.  Tracks a UIScreenEdgePanGestureRecognizer
///  from a specified screen edge and derives the completion percentage for the
///  transition.
class SwipeTransitionInteractionController: UIPercentDrivenInteractiveTransition {
    let gestureRecognizer: UIScreenEdgePanGestureRecognizer
    let edge: UIRectEdge
    weak var transitionContext: UIViewControllerContextTransitioning?
    
    init(gestureRecognizer: UIScreenEdgePanGestureRecognizer, edge: UIRectEdge) {
        assert(edge == .top || edge == .bottom ||
               edge == .left || edge == .right,
               "edgeForDragging must be one of UIRectEdgeTop, UIRectEdgeBottom, UIRectEdgeLeft, or UIRectEdgeRight.")
        self.gestureRecognizer = gestureRecognizer
        self.edge = edge
        super.init()
        
        // Add self as an observer of the gesture recognizer so that this
        // object receives updates as the user moves their finger.
        gestureRecognizer.addTarget(self, action: #selector(self.gestureRecognizeDidUpdate(_:)))
    }
    
    override init() {
        fatalError("Use init(gestureRecognizer:edge:)")
    }
    
    deinit {
        gestureRecognizer.removeTarget(self, action: #selector(self.gestureRecognizeDidUpdate(_:)))
        print("🚧 \(self).\(#function)")
    }
    
    @objc func gestureRecognizeDidUpdate(_ sender: UIScreenEdgePanGestureRecognizer) {
        switch sender.state {
        case .began:
            // The Began state is handled by the view controllers.  In response
            // to the gesture recognizer transitioning to this state, they
            // will trigger the presentation or dismissal.
            break
        case .changed:
            // We have been dragging! Update the transition context accordingly.
            update(percentForGesture(sender))
        case .ended:
            // Dragging has finished.
            // Complete or cancel, depending on how far we've dragged.
            if percentForGesture(sender) >= 0.5 {
                finish()
            } else {
                cancel()
            }
        default:
            cancel()
        }
    }
    
    override func startInteractiveTransition(_ transitionContext: any UIViewControllerContextTransitioning) {
        // Save the transitionContext for later.
        self.transitionContext = transitionContext
        super.startInteractiveTransition(transitionContext)
    }
    
    //| ----------------------------------------------------------------------------
    //! Returns the offset of the pan gesture recognizer from the edge of the
    //! screen as a percentage of the transition container view's width or height.
    //! This is the percent completed for the interactive transition.
    //
    func percentForGesture(_ gesture: UIScreenEdgePanGestureRecognizer) -> CGFloat {
        // Because view controllers will be sliding on and off screen as part
        // of the animation, we want to base our calculations in the coordinate
        // space of the view that will not be moving: the containerView of the
        // transition context.
        guard  let transitionContainerView = transitionContext?.containerView else { return 0 }
        
        let locationInSourceView = gesture.location(in: transitionContainerView)
        
        // Figure out what percentage we've gone.
        
        let width = transitionContainerView.bounds.width
        let height = transitionContainerView.bounds.height
        
        // Return an appropriate percentage based on which edge we're dragging
        // from.
        switch edge {
        case .right:
            return (width - locationInSourceView.x) / width
        case .left:
            return locationInSourceView.x / width
        case .bottom:
            return (height - locationInSourceView.y) / height
        case .top:
            return locationInSourceView.y / height
        default:
            return 0
        }
    }
}
