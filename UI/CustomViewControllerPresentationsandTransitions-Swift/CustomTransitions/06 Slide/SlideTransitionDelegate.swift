//
//  SlideTransitionDelegate.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit
import ObjectiveC

//! They key used to associate an instance of AAPLSlideTransitionDelegate with
//! the tab bar controller for which it is the delegate.
private let SlideTabBarControllerDelegateAssociationKey = "SlideTabBarControllerDelegateAssociationKey"

/// The delegate of the tab bar controller for the Slide demo.  Manages the
///  gesture recognizer used for the interactive transition.  Vends
///  instances of AAPLSlideTransitionAnimator and
///  AAPLSlideTransitionInteractionController.
class SlideTransitionDelegate: NSObject, UITabBarControllerDelegate {
    //! The UITabBarController instance for which this object is the delegate of.
    weak var tabBarController: UITabBarController? { didSet { tabBarControllerDidSet(oldValue) } }
    
    //! The gesture recognizer used for driving the interactive transition
    //! between view controllers.  AAPLSlideTransitionDelegate installs this
    //! gesture recognizer on the tab bar controller's view.
    lazy var panGestureRecongizer = makePanGestureRecognizer()
    
    func tabBarControllerDidSet(_ oldValue: UITabBarController?) {
        guard tabBarController != oldValue else { return }
        
        // Remove all associations of this object from the old tab bar
        // controller.
        if let oldValue {
            objc_setAssociatedObject(oldValue, SlideTabBarControllerDelegateAssociationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            oldValue.view.removeGestureRecognizer(panGestureRecongizer)
            if oldValue.delegate === self {
                oldValue.delegate = nil
            }
        }
        
        guard let tabBarController else { return }
        
        tabBarController.delegate = self
        tabBarController.view.addGestureRecognizer(panGestureRecongizer)
        // Associate this object with the new tab bar controller.  This ensures
        // that this object wil not be deallocated prior to the tab bar
        // controller being deallocated.
        objc_setAssociatedObject(tabBarController, SlideTabBarControllerDelegateAssociationKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    // MARK: - Gesture Recognizer
    
    //| ----------------------------------------------------------------------------
    //  Custom implementation of the getter for the panGestureRecognizer property.
    //  Lazily creates the pan gesture recognizer for the tab bar controller.
    //
    func makePanGestureRecognizer() -> UIPanGestureRecognizer {
        UIPanGestureRecognizer(target: self, action: #selector(self.panGestureRecognizerDidPan(_:)))
    }
    
    //| ----------------------------------------------------------------------------
    //! Action method for the panGestureRecognizer.
    //
    @objc func panGestureRecognizerDidPan(_ sender: UIPanGestureRecognizer) {
        // Do not attempt to begin an interactive transition if one is already
        // ongoing
        guard (tabBarController?.transitionCoordinator) == nil else { return }
        
        switch sender.state {
        case .began, .changed:
            beginInteractiveTransitionIfPossible(sender)
        default: break
        }
        
        // Remaining cases are handled by the vended
        // SlideTransitionInteractionController.
    }
    
    //| ----------------------------------------------------------------------------
    //! Begins an interactive transition with the provided gesture recognizer, if
    //! there is a view controller to transition to.
    //
    func beginInteractiveTransitionIfPossible(_ sender: UIPanGestureRecognizer) {
        guard let tabBarController else { return }
        let translation = sender.translation(in: tabBarController.view)
        
        if translation.x > 0, tabBarController.selectedIndex > 0 {
            // Panning right, transition to the left view controller.
            tabBarController.selectedIndex -= 1
        } else if translation.x < 0, tabBarController.selectedIndex + 1 < tabBarController.viewControllers!.count {
            // Panning left, transition to the right view controller.
            tabBarController.selectedIndex += 1
        } else {
            // Don't reset the gesture recognizer if we skipped starting the
            // transition because we don't have a translation yet (and thus, could
            // not determine the transition direction).
            if translation != .zero {
                // There is not a view controller to transition to, force the
                // gesture recognizer to fail.
                sender.isEnabled = false
                sender.isEnabled = true
            }
        }
        
        // We must handle the case in which the user begins panning but then
        // reverses direction without lifting their finger.  The transition
        // should seamlessly switch to revealing the correct view controller
        // for the new direction.
        //
        // The approach presented in this demonstration relies on coordination
        // between this object and the AAPLSlideTransitionInteractionController
        // it vends.  If the AAPLSlideTransitionInteractionController detects
        // that the current position of the user's touch along the horizontal
        // axis has crossed over the initial position, it cancels the
        // transition.  A completion block is attached to the tab bar
        // controller's transition coordinator.  This block will be called when
        // the transition completes or is cancelled.  If the transition was
        // cancelled but the gesture recgonzier has not transitioned to the
        // ended or failed state, a new transition to the proper view controller
        // is started, and new animation + interaction controllers are created.
        //
        tabBarController.transitionCoordinator?.animate(alongsideTransition: nil, completion: { [weak self] context in
            guard let self else { return }
            if context.isCancelled, sender.state == .changed {
                beginInteractiveTransitionIfPossible(sender)
            }
        })
    }
    
    // MARK: - UITabBarControllerDelegate
    
    //| ----------------------------------------------------------------------------
    //  The tab bar controller tries to invoke this method on its delegate to
    //  retrieve an animator object to be used for animating the transition to the
    //  incoming view controller.  Your implementation is expected to return an
    //  object that conforms to the UIViewControllerAnimatedTransitioning protocol,
    //  or nil if the transition should not be animated.
    //
    func tabBarController(_ tabBarController: UITabBarController, animationControllerForTransitionFrom fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        assert(tabBarController == self.tabBarController, "\(tabBarController) is not the tab bar controller currently associated with \(self)")
        let viewControllers = tabBarController.viewControllers ?? []
        
        if let toIndex = viewControllers.firstIndex(of: toVC), let fromIndex = viewControllers.firstIndex(of: fromVC), toIndex > fromIndex {
            // The incoming view controller succeeds the outgoing view controller,
            // slide towards the left.
            return SlideTransitionAnimator(targetEdge: .left)
        } else {
            // The incoming view controller precedes the outgoing view controller,
            // slide towards the right.
            return SlideTransitionAnimator(targetEdge: .right)
        }
    }
    
    //| ----------------------------------------------------------------------------
    //  If an id<UIViewControllerAnimatedTransitioning> was returned from
    //  -tabBarController:animationControllerForTransitionFromViewController:toViewController:,
    //  the tab bar controller tries to invoke this method on its delegate to
    //  retrieve an interaction controller for the transition.  Your implementation
    //  is expected to return an object that conforms to the
    //  UIViewControllerInteractiveTransitioning protocol, or nil if the transition
    //  should not be a interactive.
    //
    func tabBarController(_ tabBarController: UITabBarController, interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        assert(tabBarController == self.tabBarController, "\(tabBarController) is not the tab bar controller currently associated with \(self)")
        
        return switch panGestureRecongizer.state {
        case .began, .changed:
            SlideTransitionInteractionController(gestureRecognizer: panGestureRecongizer)
        default:
            // You must not return an interaction controller from this method unless
            // the transition will be interactive.
            nil
        }
    }
}
