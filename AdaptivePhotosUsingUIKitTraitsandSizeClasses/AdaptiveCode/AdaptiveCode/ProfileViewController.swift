/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
A view controller that shows a user's profile.
*/

import UIKit

class ProfileViewController: UIViewController {
    // MARK: Properties
    
    fileprivate var imageView: UIImageView?
    fileprivate var nameLabel: UILabel?
    fileprivate var conversationsLabel: UILabel?
    fileprivate var photosLabel: UILabel?
    
    // Holds the current constraints used to position the subviews.
    fileprivate var constraints = [NSLayoutConstraint]()
    
    let user: User
    
    var nameText: String {
        return user.name
    }
    
    var conversationsText: String {
        let conversationCount = user.conversations.count
        
        let localizedStringFormat = NSLocalizedString("%d conversations", comment: "X conversations")
        
        return String.localizedStringWithFormat(localizedStringFormat, conversationCount)
    }
    
    var photosText: String {
        let photoCount = user.conversations.reduce(0) { count, conversation in
            return count + conversation.photos.count
        }
        
        let localizedStringFormat = NSLocalizedString("%d photos", comment: "X photos")
        
        return String.localizedStringWithFormat(localizedStringFormat, photoCount)
    }
    
    // MARK: Initialization
    
    init(user: User) {
        self.user = user
        
        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("Profile", comment: "Profile")
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: View Controller
    
    override func loadView() {
        let view = UIView()
        view.backgroundColor = UIColor.white
        
        // Create an image view
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView = imageView
        view.addSubview(imageView)
        
        // Create a label for the profile name
        let nameLabel = UILabel()
        nameLabel.font = UIFont.preferredFont(forTextStyle: UIFontTextStyle.headline)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        self.nameLabel = nameLabel
        view.addSubview(nameLabel)
        
        // Create a label for the number of conversations
        let conversationsLabel = UILabel()
        conversationsLabel.font = UIFont.preferredFont(forTextStyle: UIFontTextStyle.body)
        conversationsLabel.translatesAutoresizingMaskIntoConstraints = false
        self.conversationsLabel = conversationsLabel
        view.addSubview(conversationsLabel)
        
        // Create a label for the number of photos
        let photosLabel = UILabel()
        photosLabel.font = UIFont.preferredFont(forTextStyle: UIFontTextStyle.body)
        photosLabel.translatesAutoresizingMaskIntoConstraints = false
        self.photosLabel = photosLabel
        view.addSubview(photosLabel)
        
        self.view = view
        
        // Update all of the visible information
        updateUser()
        updateConstraintsForTraitCollection(traitCollection)
    }
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)

        // When the trait collection changes, change our views' constraints and animate the change
        coordinator.animate(alongsideTransition: { _ in
            self.updateConstraintsForTraitCollection(newCollection)
            self.view.setNeedsLayout()
        }, completion: nil)
    }
    
    // Applies the proper constraints to the subviews for the size class of the given trait collection.
    func updateConstraintsForTraitCollection(_ collection: UITraitCollection) {
        let views: [String: AnyObject] = [
            "topLayoutGuide":       topLayoutGuide,
            "imageView":            imageView!,
            "nameLabel":            nameLabel!,
            "conversationsLabel":   conversationsLabel!,
            "photosLabel":          photosLabel!
        ]
        
        // Make our new set of constraints for the current traits
        var newConstraints = [NSLayoutConstraint]()
        
        if collection.verticalSizeClass == .compact {
            // When we're vertically compact, show the image and labels side-by-side
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "|[imageView]-[nameLabel]-|", options: [], metrics: nil, views: views)
            
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "[imageView]-[conversationsLabel]-|", options: [], metrics: nil, views: views)
            
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "[imageView]-[photosLabel]-|", options: [], metrics: nil, views: views)
            
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "V:|[topLayoutGuide]-[nameLabel]-[conversationsLabel]-[photosLabel]", options: [], metrics: nil, views: views)
            
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "V:|[topLayoutGuide][imageView]|", options: [], metrics: nil, views: views)
            
            newConstraints += [
                NSLayoutConstraint(item: imageView!, attribute: .width, relatedBy: .equal, toItem: view, attribute: .width, multiplier: 0.5, constant: 0)
            ]
        }
        else {
            // When we're vertically compact, show the image and labels top-and-bottom
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "|[imageView]|", options: [], metrics: nil, views: views)
            
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "|-[nameLabel]-|", options: [], metrics: nil, views: views)
            
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "|-[conversationsLabel]-|", options: [], metrics: nil, views: views)
            
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "|-[photosLabel]-|", options: [], metrics: nil, views: views)
            
            newConstraints += NSLayoutConstraint.constraints(withVisualFormat: "V:[topLayoutGuide]-[nameLabel]-[conversationsLabel]-[photosLabel]-20-[imageView]|", options: [], metrics: nil, views: views)
        }
        
        // Change to our new constraints
        NSLayoutConstraint.deactivate(constraints)
        constraints = newConstraints
        NSLayoutConstraint.activate(newConstraints)
    }
    
    // MARK: Convenience
    
    // Updates the user interface with the data from the current user object.
    func updateUser() {
        nameLabel?.text = nameText
        conversationsLabel?.text = conversationsText
        photosLabel?.text = photosText
        imageView?.image = user.lastPhoto?.image
    }
}
