/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The detail view controller in the Custom Back Button example.
 */

import UIKit

class CustomBackButtonDetailViewController: UIViewController {
    
    @IBOutlet var cityLabel: UILabel!
    @objc var city: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        cityLabel.text = city
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        navigationController?.pushViewController(NewDetailViewController(), animated: true)
    }
}
