//
//  AdaptivePresentationController.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit

class AdaptivePresentationController: UIPresentationController, UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning {
    var presentationWrappingView: UIView!
    var dismissButton: UIButton!
    
    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        
        // The presented view controller must have a modalPresentationStyle
        // of UIModalPresentationCustom for a custom presentation controller
        // to be used.
        presentedViewController.modalPresentationStyle = .custom
    }
    
    override var presentedView: UIView? {
        // Return the wrapping view created in -presentationTransitionWillBegin.
        presentationWrappingView
    }
    
    //| ----------------------------------------------------------------------------
    //  This is one of the first methods invoked on the presentation controller
    //  at the start of a presentation.  By the time this method is called,
    //  the containerView has been created and the view hierarchy set up for the
    //  presentation.  However, the -presentedView has not yet been retrieved.
    //
    override func presentationTransitionWillBegin() {
        // The default implementation of -presentedView returns
        // self.presentedViewController.view.
        guard let presentedViewControllerView = super.presentedView else { return }
        
        // Wrap the presented view controller's view in an intermediate hierarchy
        // that applies a shadow and adds a dismiss button to the top left corner.
        //
        // presentationWrapperView              <- shadow
        //     |- presentedViewControllerView (presentedViewController.view)
        //     |- close button
        do {
            let presentationWrapperView = UIView()
            presentationWrapperView.layer.shadowOpacity = 0.63
            presentationWrapperView.layer.shadowRadius = 17
            self.presentationWrappingView = presentationWrapperView;
            
            // Add presentedViewControllerView -> presentationWrapperView.
            presentedViewControllerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            presentationWrapperView.addSubview(presentedViewControllerView)
            
            // Create the dismiss button.
            let dismissButton = UIButton(frame: CGRect(x: 0, y: 0, width: 26, height: 26))
            dismissButton.setImage(.closeButton, for: .normal)
            dismissButton.addTarget(self, action: #selector(self.dismissButtonTapped(_:)), for: .touchUpInside)
            self.dismissButton = dismissButton
            
            // Add dismissButton -> presentationWrapperView.
            presentationWrapperView.addSubview(dismissButton)
        }
    }
    
    // MARK: - Dismiss Button
    
    //| ----------------------------------------------------------------------------
    //  IBAction for the dismiss button.  Dismisses the presented view controller.
    //
    @objc func dismissButtonTapped(_ sender: UIButton) {
        presentingViewController.dismiss(animated: true)
    }
    
    // MARK: - Layout
    
    //| ----------------------------------------------------------------------------
    //  This method is invoked when the interface rotates.  For performance,
    //  the shadow on presentationWrapperView is disabled for the duration
    //  of the rotation animation.
    //
    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        presentationWrappingView.clipsToBounds = true
        presentationWrappingView.layer.shadowOpacity = 0
        presentationWrappingView.layer.shadowRadius = 0
        
        coordinator.animate { context in
            // Intentionally left blank.
        } completion: { [weak self] context in
            guard let self else { return }
            presentationWrappingView.clipsToBounds = false
            presentationWrappingView.layer.shadowOpacity = 0.63
            presentationWrappingView.layer.shadowRadius = 17
        }
    }
    
    //| ----------------------------------------------------------------------------
    //  When the presentation controller receives a
    //  -viewWillTransitionToSize:withTransitionCoordinator: message it calls this
    //  method to retrieve the new size for the presentedViewController's view.
    //  The presentation controller then sends a
    //  -viewWillTransitionToSize:withTransitionCoordinator: message to the
    //  presentedViewController with this size as the first argument.
    //
    //  Note that it is up to the presentation controller to adjust the frame
    //  of the presented view controller's view to match this promised size.
    //  We do this in -containerViewWillLayoutSubviews.
    //
    override func size(forChildContentContainer container: any UIContentContainer, withParentContainerSize parentSize: CGSize) -> CGSize {
        if container === presentedViewController {
            CGSize(width: parentSize.width / 2, height: parentSize.height / 2)
        } else {
            super.size(forChildContentContainer: container, withParentContainerSize: parentSize)
        }
    }
    
    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let containerViewBounds = containerView.bounds
        let presentedViewContentSize = size(forChildContentContainer: presentedViewController, withParentContainerSize: containerViewBounds.size)
        
        // Center the presentationWrappingView view within the container.
        let frame = CGRect(
            x: containerViewBounds.midX - presentedViewContentSize.width/2,
            y: containerViewBounds.midY - presentedViewContentSize.height/2,
            width: presentedViewContentSize.width,
            height: presentedViewContentSize.height
        )
        
        // Outset the centered frame of presentationWrappingView so that the
        // dismiss button is within the bounds of presentationWrappingView.
        return frame.insetBy(dx: -20, dy: -20)
    }
    
    //| ----------------------------------------------------------------------------
    //  This method is similar to the -viewWillLayoutSubviews method in
    //  UIViewController.  It allows the presentation controller to alter the
    //  layout of any custom views it manages.
    //
    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        
        presentationWrappingView.frame = frameOfPresentedViewInContainerView
        
        // Undo the outset that was applied in -frameOfPresentedViewInContainerView.
        presentedViewController.view.frame = presentationWrappingView.bounds.insetBy(dx: 20, dy: 20)
        
        // Position the dismissButton above the top-left corner of the presented
        // view controller's view.
        dismissButton.center = CGPoint(x: presentedViewController.view.frame.minX, y: presentedViewController.view.frame.minY)
    }
    
    // MARK: - UIViewControllerAnimatedTransitioning
    
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        transitionContext?.isAnimated == true ? 0.35 : 0
    }
    
    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        let fromViewController = transitionContext.viewController(forKey: .from)!
        let toViewController = transitionContext.viewController(forKey: .to)!
        
        let containerView = transitionContext.containerView
        let isPresenting = fromViewController == presentingViewController
        
        // For a Presentation:
        //      fromView = The presenting view.
        //      toView   = The presented view.
        // For a Dismissal:
        //      fromView = The presented view.
        //      toView   = The presenting view.
        let fromView = transitionContext.view(forKey: .from)
        let toView = transitionContext.view(forKey: .to)
        
        // We are responsible for adding the incoming view to the containerView
        // for the presentation (will have no effect on dismissal because the
        // presenting view controller's view was not removed).
        if let toView {
            containerView.addSubview(toView)
        }
        
        if isPresenting {
            toView?.alpha = 0
            
            // This animation only affects the alpha.  The views can be set to
            // their final frames now.
            fromView?.frame = transitionContext.finalFrame(for: fromViewController)
            toView?.frame = transitionContext.finalFrame(for: toViewController)
        } else {
            // Because our presentation wraps the presented view controller's view
            // in an intermediate view hierarchy, it is more accurate to rely
            // on the current frame of fromView than fromViewInitialFrame as the
            // initial frame.
            toView?.frame = transitionContext.finalFrame(for: toViewController)
        }
        
        let transitionDuration = transitionDuration(using: transitionContext)
        
        UIView.animate(withDuration: transitionDuration) {
            if isPresenting {
                toView?.alpha = 1
            } else {
                fromView?.alpha = 0
            }
        } completion: { finished in
            // When we complete, tell the transition context
            // passing along the BOOL that indicates whether the transition
            // finished or not.
            let wasCancelled = transitionContext.transitionWasCancelled;
            transitionContext.completeTransition(!wasCancelled)
            
            // Reset the alpha of the dismissed view, in case it will be used
            // elsewhere in the app.
            if !isPresenting {
                fromView?.alpha = 1
            }
        }
    }
    
    // MARK: - UIViewControllerTransitioningDelegate
    
    //| ----------------------------------------------------------------------------
    //  If the modalPresentationStyle of the presented view controller is
    //  UIModalPresentationCustom, the system calls this method on the presented
    //  view controller's transitioningDelegate to retrieve the presentation
    //  controller that will manage the presentation.  If your implementation
    //  returns nil, an instance of UIPresentationController is used.
    //
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        assert(presentedViewController === presented, "You didn't initialize \(self) with the correct presentedViewController.  Expected \(presented), got \(presentedViewController).")
        return self
    }
    
    //| ----------------------------------------------------------------------------
    //  The system calls this method on the presented view controller's
    //  transitioningDelegate to retrieve the animator object used for animating
    //  the presentation of the incoming view controller.  Your implementation is
    //  expected to return an object that conforms to the
    //  UIViewControllerAnimatedTransitioning protocol, or nil if the default
    //  presentation animation should be used.
    //
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        self
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
        self
    }
}
