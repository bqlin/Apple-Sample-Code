//
// Created by Bq Lin on 2021/8/25.
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
        let view = self.view as! MTKView
        if let device = MTLCreateSystemDefaultDevice(),
           device.argumentBuffersSupport == .tier2
        {
            view.device = device
            renderer = Renderer(view: view)
        } else {
            fatalError("设备不满足运行要求")
        }
    }

    #if os(macOS)
        override func viewDidAppear() {
            super.viewDidAppear()
            view.window?.contentAspectRatio = .init(width: CGFloat(AAPLGridWidth), height: CGFloat((AAPLNumInstances + 1) / AAPLGridWidth))
        }
    #endif
}
