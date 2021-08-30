//
// Created by Bq Lin on 2021/8/29.
// Copyright © 2021 Bq. All rights reserved.
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
    var renderer: Renderer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        let device = MTLCreateSystemDefaultDevice()!
        let view = self.view as! MetalView
        view.metalLayer.device = device
        view.delegate = self
        view.metalLayer.pixelFormat = .bgra8Unorm_srgb
        renderer = Renderer(device: device, drawablePixelFormat: view.metalLayer.pixelFormat)
    }
}

extension ViewController: MetalViewDelegate {
    func drawableResize(_ size: CGSize) {
        renderer.drawableResize(size)
    }
    
    func render(to metalLayer: CAMetalLayer) {
        renderer.render(to: metalLayer)
    }
}
