//
//  SwipeSecondViewController.swift
//  
//  Created by Bq on 2025/10/24.
//

import Foundation
import UIKit

/// The presented view controller for the Swipe demo.
class SwipeSecondViewController: DemoPresentedViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // This gesture recognizer could be defined in the storyboard but is
        // instead created in code for clarity.
        let interactiveTransitionRecognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(self.interactiveTransitionRecognizerAction(_:)))
        interactiveTransitionRecognizer.edges = .left
        view.addGestureRecognizer(interactiveTransitionRecognizer)
    }
    
    @objc func interactiveTransitionRecognizerAction(_ sender: UIScreenEdgePanGestureRecognizer) {
        if sender.state == .began {
            dismiss(sender: sender)
        }
    }
    
    func dismiss(sender: UIScreenEdgePanGestureRecognizer?) {
        // Check if we were presented with our custom transition delegate.
        // If we were, update the configuration of the
        // AAPLSwipeTransitionDelegate with the gesture recognizer and
        // targetEdge for this view controller.
        if let transitionDelegate = transitioningDelegate as? SwipeTransitionDelegate {
            // If this will be an interactive presentation, pass the gesture
            // recognizer along to our AAPLSwipeTransitionDelegate instance
            // so it can return the necessary
            // <UIViewControllerInteractiveTransitioning> for the presentation.
            transitionDelegate.gestureRecognizer = sender
            
            // Set the edge of the screen to dismiss this view controller
            // from.  This will match the edge we configured the
            // UIScreenEdgePanGestureRecognizer with previously.
            //
            // NOTE: We can not retrieve the value of our gesture recognizer's
            //       configured edges because prior to iOS 8.3
            //       UIScreenEdgePanGestureRecognizer would always return
            //       UIRectEdgeNone when querying its edges property.
            transitionDelegate.targetEdge = .left
        }
        dismiss(animated: true)
    }
    
    @objc override func buttonAction(_ sender: AnyObject) {
        dismiss(sender: nil)
    }
}
