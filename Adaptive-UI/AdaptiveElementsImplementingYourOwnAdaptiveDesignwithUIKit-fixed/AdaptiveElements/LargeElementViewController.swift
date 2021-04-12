/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	LargeElementViewController is used in two different ways:
	 1. Contained within ExampleContainerViewController, when its width is large.
	 2. Presented by SmallElementViewController, when the ExampleContainerViewController's width is small.
	 It shows a large version of the element. When it is presented, tapping on it will dismiss it.
 */

import UIKit

class LargeElementViewController: UIViewController {

    var widthConstraint: NSLayoutConstraint?

    override func updateViewConstraints() {
        super.updateViewConstraints()

        /*
            If we are not being presented full-screen,
            then add a constraint to make this view no wider than our superview's readable content guide.
         */
        // 确定当前是非全屏的才添加约束
        if presentingViewController == nil && widthConstraint == nil, let superview = view.superview {
            widthConstraint = view.widthAnchor.constraint(lessThanOrEqualTo: superview.readableContentGuide.widthAnchor)
            widthConstraint?.isActive = true
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        /*
            When this view appears, if we are being presented,
            add a tap gesture recognizer so we can dismiss when we are tapped.
         */
        // 只有在present时才添加手势
        if isBeingPresented {
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapped))
            view.addGestureRecognizer(tapGestureRecognizer)
        }
    }

    @objc func tapped(_ gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer.state == .ended {
            dismiss(animated: true, completion: nil)
        }
    }
    
    deinit {
        print("\(Self.self) \(#function)")
    }

}
