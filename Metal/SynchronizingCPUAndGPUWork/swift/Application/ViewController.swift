//
//  ViewController.swift
//  CPU-GPU-Synchronization
//
//  Created by Bq Lin on 2021/5/13.
//  Copyright © 2021 Bq. All rights reserved.
//

import UIKit
import MetalKit

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let view = self.view as! MTKView
        view.device = MTLCreateSystemDefaultDevice()
        
        renderer = Renderer(mtkView: view)
    }
    
    var renderer: Renderer!
}
