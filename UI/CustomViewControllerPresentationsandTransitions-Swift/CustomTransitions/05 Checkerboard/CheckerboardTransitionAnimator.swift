//
//  CheckerboardTransitionAnimator.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit

/// A transition animator that transitions between two view controllers in
///  a navigation stack, using a 3D checkerboard effect.
class CheckerboardTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        3
    }
    
    //| ----------------------------------------------------------------------------
    //  Custom transitions within a UINavigationController follow the same
    //  conventions as those used for modal presentations.  Your animator will
    //  be given the incoming and outgoing view controllers along with a container
    //  view where both view controller's views will reside.  Your animator is
    //  tasked with animating the incoming view controller's view into the
    //  container view.  The frame of the incoming view controller's view is
    //  is expected to match the value returned from calling
    //  [transitionContext finalFrameForViewController:toViewController] when the
    //  transition is complete.
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
        let fromView = transitionContext.view(forKey: .from)!
        let toView = transitionContext.view(forKey: .to)!
        
        // If a push is being animated, the incoming view controller will have a
        // higher index on the navigation stack than the current top view
        // controller.
        let isPush =
        if
            let toIndex = toViewController.navigationController?.viewControllers.firstIndex(of: toViewController),
            let fromIndex = fromViewController.navigationController?.viewControllers.firstIndex(of: fromViewController)
        { toIndex > fromIndex } else { false }
        
        // Our animation will be operating on snapshots of the fromView and toView,
        // so the final frame of toView can be configured now.
        fromView.frame = transitionContext.initialFrame(for: fromViewController)
        toView.frame = transitionContext.finalFrame(for: toViewController)
        
        // We are responsible for adding the incoming view to the containerView
        // for the transition.
        containerView.addSubview(toView)
        
        var fromViewSnapshot: UIImage!
        var toViewSnapshot: UIImage!
        
        // Snapshot the fromView.
        UIGraphicsBeginImageContextWithOptions(containerView.bounds.size, true, containerView.window?.screen.scale ?? 0)
        fromView.drawHierarchy(in: containerView.bounds, afterScreenUpdates: false)
        fromViewSnapshot = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // To avoid a blank snapshot, defer snapshotting the incoming view until it
        // has had a chance to perform layout and drawing (1 run-loop cycle).
        DispatchQueue.main.async {
            UIGraphicsBeginImageContextWithOptions(containerView.bounds.size, true, containerView.window?.screen.scale ?? 0)
            toView.drawHierarchy(in: containerView.bounds, afterScreenUpdates: false)
            toViewSnapshot = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
        }
        
        let transitionContainer = UIView(frame: containerView.bounds)
        transitionContainer.isOpaque = true
        transitionContainer.backgroundColor = .black
        containerView.addSubview(transitionContainer)
        
        // Apply a perpective transform to the sublayers of transitionContainer.
        var t = CATransform3DIdentity
        t.m34 = 1 / -900
        transitionContainer.layer.sublayerTransform = t
        
        // The size and number of slices is a function of the width.
        let sliceSize = (transitionContainer.frame.width / 10).rounded()
        let horizontalSlices = Int((transitionContainer.frame.width / sliceSize).rounded(.up))
        let verticalSlices = Int((transitionContainer.frame.height / sliceSize).rounded(.up))
        
        // transitionSpacing controls the transition duration for each slice.
        // Higher values produce longer animations with multiple slices having
        // their animations 'in flight' simultaneously.
        let transitionSpacing: CGFloat = 160
        let transitionDuration = transitionDuration(using: transitionContext)
        
        let transitionVector: CGVector =
        if isPush {
            CGVector(dx: transitionContainer.bounds.maxX - transitionContainer.bounds.minX, dy: transitionContainer.bounds.maxY - transitionContainer.bounds.minY)
        } else {
            CGVector(dx: transitionContainer.bounds.minX - transitionContainer.bounds.maxX, dy: transitionContainer.bounds.minY - transitionContainer.bounds.maxY)
        }
        
        let transitionVectorLength = sqrt(transitionVector.dx * transitionVector.dx + transitionVector.dy * transitionVector.dy)
        let transitionUnitVector = CGVector(
            dx: transitionVector.dx / transitionVectorLength,
            dy: transitionVector.dy / transitionVectorLength
        )
        
        for y in 0 ..< verticalSlices {
            for x in 0 ..< horizontalSlices {
                let fromContentLayer = CALayer()
                fromContentLayer.frame = CGRect(
                    x: .init(x) * sliceSize * -1,
                    y: .init(y) * sliceSize * -1,
                    width: containerView.bounds.width,
                    height: containerView.bounds.height
                )
                fromContentLayer.rasterizationScale = fromViewSnapshot.scale
                fromContentLayer.contents = fromViewSnapshot.cgImage
                
                let toContentLayer = CALayer()
                toContentLayer.frame = fromContentLayer.frame
                
                // Snapshotting the toView was deferred so we must also defer applying
                // the snapshot to the layer's contents.
                DispatchQueue.main.async {
                    // Disable actions so the contents are applied without animation.
                    let wereActiondDisabled = CATransaction.disableActions()
                    CATransaction.setDisableActions(true)
                    
                    toContentLayer.rasterizationScale = toViewSnapshot.scale
                    toContentLayer.contents = toViewSnapshot.cgImage
                    
                    CATransaction.setDisableActions(wereActiondDisabled)
                }
                
                let toCheckboardSquareView = UIView(frame: CGRect(x: .init(x) * sliceSize, y: .init(y) * sliceSize, width: sliceSize, height: sliceSize))
                toCheckboardSquareView.isOpaque = false
                toCheckboardSquareView.layer.masksToBounds = true
                toCheckboardSquareView.layer.isDoubleSided = false
                toCheckboardSquareView.layer.transform = CATransform3DMakeRotation(.pi, 0, 1, 0)
                toCheckboardSquareView.layer.addSublayer(toContentLayer)
                
                let fromCheckboardSquareView = UIView(frame: CGRect(
                    x: .init(x) * sliceSize,
                    y: .init(y) * sliceSize,
                    width: sliceSize,
                    height: sliceSize
                ))
                fromCheckboardSquareView.isOpaque = false
                fromCheckboardSquareView.layer.masksToBounds = true
                fromCheckboardSquareView.layer.isDoubleSided = false
                fromCheckboardSquareView.layer.transform = CATransform3DIdentity
                fromCheckboardSquareView.layer.addSublayer(fromContentLayer)
                
                transitionContainer.addSubview(toCheckboardSquareView)
                transitionContainer.addSubview(fromCheckboardSquareView)
            }
        }
        
        // Used to track how many slices have animations which are still in flight.
        var sliceAnimationsPending = 0
        for y in 0 ..< verticalSlices {
            for x in 0 ..< horizontalSlices {
                let toCheckboardSquareView = transitionContainer.subviews[y * horizontalSlices * 2 + (x * 2)]
                let fromCheckboardSquareView = transitionContainer.subviews[y * horizontalSlices * 2 + (x * 2 + 1)]
                
                let sliceOriginVector =
                if isPush {
                    // Define a vector from the origin of transitionContainer to the
                    // top left corner of the slice.
                    CGVector(
                        dx: fromCheckboardSquareView.frame.minX - transitionContainer.bounds.minX,
                        dy: fromCheckboardSquareView.frame.minY - transitionContainer.bounds.minY
                    )
                } else {
                    CGVector(
                        dx: fromCheckboardSquareView.frame.maxX - transitionContainer.bounds.maxX,
                        dy: fromCheckboardSquareView.frame.maxY - transitionContainer.bounds.maxY
                    )
                }
                
                // Project sliceOriginVector onto transitionVector.
                let dot = sliceOriginVector.dx * transitionVector.dx + sliceOriginVector.dy * transitionVector.dy
                let projection = CGVector(dx: transitionUnitVector.dx * dot/transitionVectorLength, dy: transitionUnitVector.dy * dot/transitionVectorLength)
                
                // Compute the length of the projection.
                let projectionLength = sqrt(projection.dx * projection.dx + projection.dy * projection.dy)
                
                let startTime = projectionLength/(transitionVectorLength + transitionSpacing) * transitionDuration
                let duration = ( (projectionLength + transitionSpacing)/(transitionVectorLength + transitionSpacing) * transitionDuration ) - startTime
                
                sliceAnimationsPending += 1
                
                UIView.animate(withDuration: duration, delay: startTime) {
                    toCheckboardSquareView.layer.transform = CATransform3DIdentity
                    fromCheckboardSquareView.layer.transform = CATransform3DMakeRotation(.pi, 0, 1, 0)
                } completion: { finished in
                    // Finish the transition once the final animation completes.
                    sliceAnimationsPending -= 1
                    if sliceAnimationsPending == 0 {
                        let wasCancelled = transitionContext.transitionWasCancelled
                        
                        transitionContainer.removeFromSuperview()
                        
                        // When we complete, tell the transition context
                        // passing along the BOOL that indicates whether the transition
                        // finished or not.
                        transitionContext.completeTransition(!wasCancelled)
                    }
                }
            }
        }
    }
}
