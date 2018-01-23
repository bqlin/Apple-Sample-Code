/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
A control that allows viewing and editing a rating.
*/

import UIKit

class RatingControl: UIControl {
    
    /*
        NOTE: Unlike OverlayView, this control does not implement `intrinsicContentSize()`.
        Instead, this control configures its auto layout constraints such that the
        size of the star images that compose it can be used by the layout engine 
        to derive the desired content size of this control. Since UIImageView will
        automatically load the correct UIImage asset for the current trait collection,
        we receive automatic adaptivity support for free just by including the images 
        for both the compact and regular size classes.
    */
    
    static let minimumRating = 0
    static let maximumRating = 4
    
    var rating = RatingControl.minimumRating {
        didSet {
            updateImageViews()
        }
    }
    
    fileprivate let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
    fileprivate var imageViews = [UIImageView]()
    
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
    
    // Initialization code common to instances created programmatically as well as instances unarchived from a storyboard.
    fileprivate func commonInit() {
        backgroundView.contentView.backgroundColor = UIColor(white: 0.7, alpha: 0.3)
        addSubview(backgroundView)
        
        // Create image views for each of the sections that make up the control.
        for rating in RatingControl.minimumRating...RatingControl.maximumRating {
            let imageView = UIImageView()
            imageView.isUserInteractionEnabled = true
            
            // Set up our image view's images.
            imageView.image = UIImage(named: "ratingInactive")
            imageView.highlightedImage = UIImage(named: "ratingActive")
            
            let localizedStringFormat = NSLocalizedString("%d stars", comment: "X stars")
            imageView.accessibilityLabel = String.localizedStringWithFormat(localizedStringFormat, rating + 1)
            addSubview(imageView)
            imageViews.append(imageView)
        }
        
        // Setup constraints.
        var newConstraints = [NSLayoutConstraint]()
        
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        
        let views = ["backgroundView": backgroundView]
        
        // Keep our background matching our size
        newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "|[backgroundView]|", options: [], metrics: nil, views: views)
        newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "V:|[backgroundView]|", options: [], metrics: nil, views: views)
        
        // Place the individual image views side-by-side with margins
        var lastImageView: UIImageView?
        for imageView in imageViews {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            
            let currentImageViews: [String: AnyObject]
            
            if lastImageView != nil {
                currentImageViews = [
                    "lastImageView": lastImageView!,
                    "imageView": imageView
                ]
            }
            else {
                currentImageViews = ["imageView": imageView]
            }
            
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "V:|-4-[imageView]-4-|", options: [], metrics: nil, views: currentImageViews)
            
            newConstraints += [
                NSLayoutConstraint(item: imageView, attribute: .width, relatedBy: .equal, toItem: imageView, attribute: .height, multiplier: 1, constant: 0)
            ]

            if lastImageView != nil {
                newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "[lastImageView][imageView(==lastImageView)]", options: [], metrics: nil, views: currentImageViews)
            }
            else {
                newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "|-4-[imageView]", options: [], metrics: nil, views: currentImageViews)
            }
            
            lastImageView = imageView
        }
        
        let currentImageViews = ["lastImageView": lastImageView!]

        newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "[lastImageView]-4-|", options: [], metrics: nil, views: currentImageViews)
        
        NSLayoutConstraint.activate(newConstraints)
    }
    
    func updateImageViews() {
        for (index, imageView) in imageViews.enumerated() {
            imageView.isHighlighted = index + RatingControl.minimumRating <= rating
        }
    }

    // MARK: Touches

    func updateRatingWithTouches(_ touches: Set<UITouch>, event: UIEvent?) {
        guard let touch = touches.first else { return }
        
        let position = touch.location(in: self)
        
        guard let touchedView = hitTest(position, with: event) as? UIImageView else { return }
        
        guard let touchedIndex = imageViews.index(of: touchedView) else { return }
        
        rating = RatingControl.minimumRating + touchedIndex

        sendActions(for: .valueChanged)
    }
    
    // If you override one of the touch event callbacks, you should override all of them.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateRatingWithTouches(touches, event: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateRatingWithTouches(touches, event: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // There's no need to handle `touchesCancelled(_:withEvent:)` for this control.
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // There's no need to handle `touchesCancelled(_:withEvent:)` for this control.
    }

    // MARK: Accessibility

    // This control is not an accessibility element but the individual images that compose it are.
    override var isAccessibilityElement: Bool {
        set { /* ignore value */ }
        
        get { return false }
    }
}
