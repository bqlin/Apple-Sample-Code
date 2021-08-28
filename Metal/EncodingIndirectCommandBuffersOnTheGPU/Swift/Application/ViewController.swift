//
// Created by Bq Lin on 2021/8/27.
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
        let supportICB: Bool
        #if os(macOS)
        supportICB = device.supportsFeatureSet(.macOS_GPUFamily2_v1)
        #else
        supportICB = device.supportsFeatureSet(.iOS_GPUFamily3_v4)
        #endif
        assert(supportICB, "示例需要设备支持macOS_GPUFamily2_v1或iOS_GPUFamily3_v4，才能使用间接命令缓冲区")
        let view = self.view as! MTKView
        view.device = device
        renderer = Renderer(view: view)
    }
}
