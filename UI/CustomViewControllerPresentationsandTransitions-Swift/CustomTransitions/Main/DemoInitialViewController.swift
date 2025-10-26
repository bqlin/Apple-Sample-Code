//
//  DemoInitialViewController.swift
//  
//  Created by Bq on 2025/10/25.
//

import Foundation
import UIKit

class DemoInitialViewController: UIViewController {
    deinit {
        print("🚧 \(self).\(#function)")
    }
    
    override func loadView() {
        view = TrackingView()
    }
    
    lazy var button = view.setupBaseUI(text: "A", buttonTitle: "Present With Custom Transition")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor("E6E6FF")
        
        button.addTarget(self, action: #selector(self.buttonAction(_:)), for: .touchUpInside)
    }
    
    @objc func buttonAction(_ sender: AnyObject) {
    }
}
