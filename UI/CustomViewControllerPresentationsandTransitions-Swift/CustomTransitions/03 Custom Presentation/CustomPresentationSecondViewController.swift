//
//  CustomPresentationSecondViewController.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit

/// The second view controller for the Custom Presentation demo.
class CustomPresentationSecondViewController: DemoPresentedViewController {
    lazy var slider = UISlider()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        button.setTitle("Present With Standard Presentation", for: .normal)
        
        slider.addTarget(self, action: #selector(self.sliderValueChange(_:)), for: .valueChanged)
        view.addSubview(slider)
        slider.prepareForAutoLayout()
        NSLayoutConstraint.activate([
            slider.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            slider.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor),
            slider.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor),
            slider.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -8),
        ])
        
        updatePreferredContentSize(traitCollection: traitCollection)
        
        // NOTE: View controllers presented with custom presentation controllers
        //       do not assume control of the status bar appearance by default
        //       (their -preferredStatusBarStyle and -prefersStatusBarHidden
        //       methods are not called).  You can override this behavior by
        //       setting the value of the presented view controller's
        //       modalPresentationCapturesStatusBarAppearance property to YES.
        /* modalPresentationCapturesStatusBarAppearance = true */
    }
    
    @objc override func buttonAction(_ sender: AnyObject) {
        present(DemoPresentedViewController(backgroundColor: UIColor("C9E6E6"), contentText: "C"), animated: true)
    }
    
    @objc func sliderValueChange(_ sender: UISlider) {
        preferredContentSize = CGSize(width: view.bounds.width, height: .init(sender.value))
    }
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
        
        // When the current trait collection changes (e.g. the device rotates),
        // update the preferredContentSize.
        updatePreferredContentSize(traitCollection: newCollection)
    }
    
    //| ----------------------------------------------------------------------------
    //! Updates the receiver's preferredContentSize based on the verticalSizeClass
    //! of the provided \a traitCollection.
    //
    func updatePreferredContentSize(traitCollection: UITraitCollection) {
        preferredContentSize = CGSize(width: view.bounds.width, height: traitCollection.verticalSizeClass == .compact ? 270 : 420)
        
        // To demonstrate how a presentation controller can dynamically respond
        // to changes to its presented view controller's preferredContentSize,
        // this view controller exposes a slider.  Dragging this slider updates
        // the preferredContentSize of this view controller in real time.
        //
        // Update the slider with appropriate min/max values and reset the
        // current value to reflect the changed preferredContentSize.
        slider.maximumValue = .init(preferredContentSize.height)
        slider.minimumValue = 220
        slider.value = slider.maximumValue
    }
}
