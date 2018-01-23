/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
A view controller that shows placeholder text.
*/

import UIKit

class EmptyViewController: UIViewController {
    override func loadView() {
        let view = UIView()
        view.backgroundColor = UIColor.white
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("No Conversation Selected", comment: "No Conversation Selected")
        label.textColor = UIColor(white: 0.0, alpha: 0.4)
        label.font = UIFont.preferredFont(forTextStyle: UIFontTextStyle.headline)
        view.addSubview(label)
        
        let xConstraint = NSLayoutConstraint(item: label, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: 1, constant: 0)
        let yConstraint = NSLayoutConstraint(item: label, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([xConstraint, yConstraint])
        
        self.view = view
    }
}
