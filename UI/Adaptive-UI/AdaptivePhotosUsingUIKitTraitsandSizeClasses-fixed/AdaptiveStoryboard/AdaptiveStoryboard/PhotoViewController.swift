/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
A view controller that shows a photo and its metadata.
*/

import UIKit

class PhotoViewController: UIViewController {
    // MARK: Properties

    @IBOutlet fileprivate var imageView: UIImageView?
    @IBOutlet fileprivate var overlayView: OverlayView?
    @IBOutlet fileprivate var ratingControl: RatingControl?

    var photo: Photo?
    
    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()
    
        updatePhoto()
    }
    
    // MARK: IBActions
    
    /*
        Action for a change in value from the `RatingControl` (the user choose a
        different rating for the photo).
    */
    @IBAction func changeRating(_ sender: RatingControl) {
        photo?.rating = sender.rating
    }
    
    // MARK: Convenience
    
    // Updates the image view and meta data views with the data from the current photo.
    func updatePhoto() {
        imageView?.image = photo?.image
        overlayView?.text = photo?.comment
        ratingControl?.rating = photo?.rating ?? RatingControl.minimumRating
    }
    
    // This method is originally declared in the PhotoContents extension on UIViewController.
    override func containedPhoto() -> Photo? {
        return photo
    }
}
