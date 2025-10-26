//
//  DemoPresentedViewController.swift
//  
//  Created by Bq on 2025/10/24.
//

import Foundation
import UIKit

/// The presented view controller for the demo.
class DemoPresentedViewController: UIViewController {
    var backgroundColor = UIColor("FFE6E6")
    var contentText = "B"
    
    lazy var button = view.setupBaseUI(text: contentText, buttonTitle: "Dismiss")
    
    convenience init(backgroundColor: UIColor, contentText: String) {
        self.init(nibName: nil, bundle: nil)
        self.backgroundColor = backgroundColor
        self.contentText = contentText
    }
    
    deinit {
        print("🚧 \(self).\(#function)")
    }
    
    override func loadView() {
        view = TrackingView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = backgroundColor
        button.addTarget(self, action: #selector(self.buttonAction(_:)), for: .touchUpInside)
    }
    
    @objc func buttonAction(_ sender: AnyObject) {
        dismiss(animated: true)
    }
}
