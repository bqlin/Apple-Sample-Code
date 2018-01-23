/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
A view controller that shows text about this app, using readable margins.
*/

import UIKit

class AboutViewController: UIViewController {
    // MARK: Properties

    var headlineLabel: UILabel?
    var label: UILabel?
    
    // MARK: View Controller
    
    override func loadView() {
        let view = UIView()
        view.backgroundColor = UIColor.white

        let headlineLabel = UILabel()
        headlineLabel.font = UIFont.preferredFont(forTextStyle: UIFontTextStyle.headline)
        headlineLabel.numberOfLines = 1
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headlineLabel)
        self.headlineLabel = headlineLabel

        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: UIFontTextStyle.body)
        label.numberOfLines = 0

        if let url = Bundle.main.url(forResource: "Text", withExtension: "txt") {
            do {
                let text = try String(contentsOf: url)
                label.text = text
            } catch let error {
                print("Error loading text: \(error)")
            }
        }
        
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        self.label = label
        
        self.view = view
        
        var constraints = [NSLayoutConstraint]()

        let viewsAndGuides: [String: AnyObject] = [
            "topLayoutGuide":       topLayoutGuide,
            "bottomLayoutGuide":    bottomLayoutGuide,
            "headlineLabel":        headlineLabel,
            "label":                label
        ]

        // Position our labels in the center, respecting the readableContentGuide if it is available
        constraints += NSLayoutConstraint.constraints(withVisualFormat: "V:[topLayoutGuide]-[headlineLabel]-[label]-[bottomLayoutGuide]|", options: [], metrics: nil, views: viewsAndGuides)

        if #available(iOS 9.0, *) {
            // Use `readableContentGuide` on iOS 9.
            let readableContentGuide = view.readableContentGuide
           
            constraints += [
                label.leadingAnchor.constraint(equalTo: readableContentGuide.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: readableContentGuide.trailingAnchor),
                headlineLabel.leadingAnchor.constraint(equalTo: readableContentGuide.leadingAnchor),
                headlineLabel.trailingAnchor.constraint(equalTo: readableContentGuide.trailingAnchor)
            ]
        }
        else {
            // Fallback on earlier versions.
            constraints += NSLayoutConstraint.constraints(withVisualFormat: "20-[label]-20|", options: [], metrics:nil, views: viewsAndGuides)
            
            constraints += NSLayoutConstraint.constraints(withVisualFormat: "20-[headlineLabel]-20|", options: [], metrics:nil, views: viewsAndGuides)
        }

        NSLayoutConstraint.activate(constraints)
        updateLabelsForTraitCollection(traitCollection)
    }
    
    // MARK: Transition
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with:coordinator)
        
        updateLabelsForTraitCollection(newCollection)
    }
    
    fileprivate func updateLabelsForTraitCollection(_ collection: UITraitCollection) {
        if collection.horizontalSizeClass == .regular {
            headlineLabel?.text = "Regular Width"
        }
        else {
            headlineLabel?.text = "Compact Width"
        }
    }
    
    // MARK: IBActions
    
    @IBAction func closeAboutViewController(_ sender: AnyObject) {
        dismiss(animated: true, completion: nil)
    }
}
