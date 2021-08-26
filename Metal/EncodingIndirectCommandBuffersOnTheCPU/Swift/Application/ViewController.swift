//
// Created by Bq Lin on 2021/8/26.
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
        view.device = MTLCreateSystemDefaultDevice()
        renderer = Renderer(view: view)
    }
}
