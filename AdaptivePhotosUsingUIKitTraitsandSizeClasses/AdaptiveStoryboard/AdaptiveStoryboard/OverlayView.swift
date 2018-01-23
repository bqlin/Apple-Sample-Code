/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
A view that shows a textual overlay whose margins change with its vertical size class.
*/

import UIKit

class OverlayView: UIView {
    // MARK: Properties
    
    var text: String? {
        /*
            Custom implementations of the getter and setter for the comment propety. 
            Changes to this property are forwarded to the label and the intrinsic
            content size is invalidated.
        */
        get {
            return label.text
        }

        set {
            label.text = newValue
        }
    }
    
    fileprivate var label = UILabel()
    
    // MARK: Initialization
    
    // This initializer will be called if the control is created programatically.
    override init(frame: CGRect) {
        super.init(frame: frame)

        commonInit()
    }
    
    // This initializer will be called if the control is loaded from a storyboard.
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        commonInit()
    }
    
    /*
        Initialization code common to instances created programmatically as well
        as instances unarchived from a storyboard.
    */
    fileprivate func commonInit() {
        let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        backgroundView.contentView.backgroundColor = UIColor(white: 0.7, alpha: 0.3)
        addSubview(backgroundView)
        
        label.font = UIFont.preferredFont(forTextStyle: UIFontTextStyle.body)
        addSubview(label)
        
        // Setup constraints.
        var newConstraints = [NSLayoutConstraint]()
        
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        let views = ["backgroundView": backgroundView]

        newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "|[backgroundView]|", options: [], metrics: nil, views: views)
        
        newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "V:|[backgroundView]|", options: [], metrics: nil, views: views)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        
        newConstraints += [
            NSLayoutConstraint(item: label, attribute: .centerX, relatedBy: .equal, toItem: self, attribute: .centerX, multiplier: 1, constant: 0),
            
            NSLayoutConstraint(item: label, attribute: .centerY, relatedBy: .equal, toItem: self, attribute: .centerY, multiplier: 1, constant: 0)
        ]
        
        NSLayoutConstraint.activate(newConstraints)
        
        /*
            Listening for changes to the user's preferred text size and updating 
            the relevant views is necessary to fully support Dynamic Type in your 
            view or control.  The user may adjust their preferred text style while
            your application is suspended.  Upon returning to the foreground, your
            application will receive a `UIContentSizeCategoryDidChangeNotification`
            should a change to the user's preferred text size have occurred.
        */
        NotificationCenter.default.addObserver(self, selector: #selector(OverlayView.contentSizeCategoryDidChange(_:)), name: NSNotification.Name.UIContentSizeCategoryDidChange, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Content Size Handling
    
    func contentSizeCategoryDidChange(_ notification: Notification) {
        label.font = UIFont.preferredFont(forTextStyle: UIFontTextStyle.body)

        invalidateIntrinsicContentSize()
    }
    
    override var intrinsicContentSize : CGSize {
        var size = label.intrinsicContentSize
        
        // Add a horizontal margin whose size depends on our horizontal size class.
        if traitCollection.horizontalSizeClass == .compact {
            size.width += 8.0
        }
        else {
            size.width += 40.0
        }
        
        // Add a vertical margin whose size depends on our vertical size class.
        if traitCollection.verticalSizeClass == .compact {
            size.height += 8.0
        }
        else {
            size.height += 40.0
        }
        
        return size
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass ||
              traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass else { return }
        
        /*
            If our size class has changed, then our intrinsic content size will
            need to be updated.
        */
        invalidateIntrinsicContentSize()
    }
}
