//
//  SwipeFirstViewController.swift
//  
//  Created by Bq on 2025/10/24.
//

import Foundation
import UIKit

/// The initial view controller for the Swipe demo.
class SwipeFirstViewController: DemoInitialViewController {
    lazy var customTransitionDelegate = SwipeTransitionDelegate()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Swipe"
        
        // This gesture recognizer could be defined in the storyboard but is
        // instead created in code for clarity.
        let interactiveTransitionRecognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(self.interactiveTransitionRecognizerAction(_:)))
        interactiveTransitionRecognizer.edges = .right
        view.addGestureRecognizer(interactiveTransitionRecognizer)
    }
    
    @objc func interactiveTransitionRecognizerAction(_ sender: UIScreenEdgePanGestureRecognizer) {
        if sender.state == .began {
            persentSecond(sender: sender)
        }
    }
    
    func persentSecond(sender: UIScreenEdgePanGestureRecognizer?) {
        // Unlike in the Cross Dissolve demo, we use a separate object as the
        // transition delegate rather then (our)self.  This promotes
        // 'separation of concerns' as AAPLSwipeTransitionDelegate will
        // handle pairing the correct animation controller and interaction
        // controller for the presentation.
        let transitionDelegate = customTransitionDelegate
        
        // If this will be an interactive presentation, pass the gesture
        // recognizer along to our AAPLSwipeTransitionDelegate instance
        // so it can return the necessary
        // <UIViewControllerInteractiveTransitioning> for the presentation.
        transitionDelegate.gestureRecognizer = sender
        
        // Set the edge of the screen to present the incoming view controller
        // from.  This will match the edge we configured the
        // UIScreenEdgePanGestureRecognizer with previously.
        //
        // NOTE: We can not retrieve the value of our gesture recognizer's
        //       configured edges because prior to iOS 8.3
        //       UIScreenEdgePanGestureRecognizer would always return
        //       UIRectEdgeNone when querying its edges property.
        transitionDelegate.targetEdge = .right
        
        // Note that the view controller does not hold a strong reference to
        // its transitioningDelegate.  If you instantiate a separate object
        // to be the transitioningDelegate, ensure that you hold a strong
        // reference to that object.
        let destinationViewController = SwipeSecondViewController()
        destinationViewController.transitioningDelegate = transitionDelegate
        
        // Setting the modalPresentationStyle to FullScreen enables the
        // <ContextTransitioning> to provide more accurate initial and final
        // frames of the participating view controllers.
        destinationViewController.modalPresentationStyle = .fullScreen
        // destinationViewController.modalPresentationStyle = .overFullScreen
        
        present(destinationViewController, animated: true)
    }
    
    @objc override func buttonAction(_ sender: AnyObject) {
        persentSecond(sender: nil)
    }
}
