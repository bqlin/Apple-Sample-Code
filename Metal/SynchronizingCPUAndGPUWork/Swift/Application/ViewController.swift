//
//  ViewController.swift
//  CPU-GPU-Synchronization
//
//  Created by Bq Lin on 2021/5/13.
//  Copyright © 2021 Bq. All rights reserved.
//

#if os(iOS) || os(tvOS)
import UIKit
typealias PlatformViewController = UIViewController
#else
import AppKit
typealias PlatformViewController = NSViewController
#endif

import MetalKit

class ViewController: PlatformViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let view = self.view as! MTKView
        view.device = MTLCreateSystemDefaultDevice()
        guard view.device != nil else {
            fatalError("can not fetch default device!")
        }
        
        renderer = Renderer(mtkView: view)
    }
    
    var renderer: Renderer!
}