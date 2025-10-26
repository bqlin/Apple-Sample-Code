//
//  AdaptivePresentationSecondViewController.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit

/// The second view controller for the Adaptive Presentation demo.
class AdaptivePresentationSecondViewController: DemoPresentedViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // In the regular environment, AAPLAdaptivePresentationController displays
        // a close button for the presented view controller.  For the compact
        // environment, a 'dismiss' button is added to this view controller's
        // navigationItem.  This button will be picked up and displayed in the
        // navigation bar of the navigation controller returned by
        // -presentationController:viewControllerForAdaptivePresentationStyle:
        let dismissButton = UIBarButtonItem(title: "Dismiss", style: .plain, target: self, action: #selector(self.buttonAction(_:)))
        navigationItem.leftBarButtonItem = dismissButton
    }
    
    override var transitioningDelegate: (any UIViewControllerTransitioningDelegate)? {
        didSet {
            // For an adaptive presentation, the presentation controller's delegate
            // must be configured prior to invoking
            // -presentViewController:animated:completion:.  This ensures the
            // presentation is able to properly adapt if the initial presentation
            // environment is compact.
            presentationController?.delegate = self
        }
    }
}
    
// MARK: - UIAdaptivePresentationControllerDelegate
extension AdaptivePresentationSecondViewController: UIAdaptivePresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        // An adaptive presentation may only fallback to
        // UIModalPresentationFullScreen or UIModalPresentationOverFullScreen
        // in the horizontally compact environment.  Other presentation styles
        // are interpreted as UIModalPresentationNone - no adaptation occurs.
        .fullScreen
    }
    
    func presentationController(_ controller: UIPresentationController, viewControllerForAdaptivePresentationStyle style: UIModalPresentationStyle) -> UIViewController? {
        // 将自身使用 UINavigationController 包一层
        UINavigationController(rootViewController: controller.presentedViewController)
    }
}
