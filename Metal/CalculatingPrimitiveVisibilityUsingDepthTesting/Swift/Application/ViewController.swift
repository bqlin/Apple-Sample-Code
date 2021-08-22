//
// Created by Bq Lin on 2021/8/22.
// Copyright © 2021 Bq. All rights reserved.
//

#if os(iOS) || os(tvOS)
    import UIKit
    typealias PlatformViewController = UIViewController
    typealias Slider = UISlider
    typealias Label = UILabel
#else
    import AppKit
    typealias PlatformViewController = NSViewController
    typealias Slider = NSSlider
    typealias Label = NSTextField
#endif

import MetalKit

class ViewController: PlatformViewController {
    @IBOutlet var topVertexDepthSlider: Slider!
    @IBOutlet var topVertexDepthLabel: Label!
    @IBOutlet var leftVertexDepthSlider: Slider!
    @IBOutlet var leftVertexDepthLabel: Label!
    @IBOutlet var rightVertexDepthSlider: Slider!
    @IBOutlet var rightVertexDepthLabel: Label!

    var kvObservations = [NSKeyValueObservation]()
    var renderer: Renderer!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        let view = self.view as! MTKView
        view.device = MTLCreateSystemDefaultDevice()!
        renderer = Renderer(view: view)

        #if os(iOS) || os(tvOS)
            renderer.topVertexDepth = topVertexDepthSlider.value
            renderer.leftVertexDepth = leftVertexDepthSlider.value
            renderer.rightVertexDepth = rightVertexDepthSlider.value
        #else
            renderer.topVertexDepth = topVertexDepthSlider.floatValue
            renderer.leftVertexDepth = leftVertexDepthSlider.floatValue
            renderer.rightVertexDepth = rightVertexDepthSlider.floatValue
        #endif

        kvObservations.append(renderer.observe(\.topVertexDepth, options: [.initial, .new]) { [weak self] renderer, change in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setupLabel(self.topVertexDepthLabel, value: renderer.topVertexDepth)
            }
        })
        kvObservations.append(renderer.observe(\.leftVertexDepth, options: [.initial, .new]) { [weak self] renderer, change in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setupLabel(self.leftVertexDepthLabel, value: renderer.leftVertexDepth)
            }
        })
        kvObservations.append(renderer.observe(\.rightVertexDepth, options: [.initial, .new]) { [weak self] renderer, change in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setupLabel(self.rightVertexDepthLabel, value: renderer.rightVertexDepth)
            }
        })
    }

    deinit {
        kvObservations = []
    }
}

#if os(iOS) || os(tvOS)
    extension ViewController {
        @IBAction func setTopVertexDepth(_ sender: Slider) {
            renderer.topVertexDepth = sender.value
        }

        @IBAction func setLeftVertexDepth(_ sender: Slider) {
            renderer.leftVertexDepth = sender.value
        }

        @IBAction func setRightVertexDepth(_ sender: Slider) {
            renderer.rightVertexDepth = sender.value
        }

        func setupLabel(_ label: Label, value: Float) {
            DispatchQueue.main.async {
                label.text = String(format: "%.2f", value)
            }
        }
    }
#else
    extension ViewController {
        @IBAction func setTopVertexDepth(_ sender: Slider) {
            renderer.topVertexDepth = sender.floatValue
        }

        @IBAction func setLeftVertexDepth(_ sender: Slider) {
            renderer.leftVertexDepth = sender.floatValue
        }

        @IBAction func setRightVertexDepth(_ sender: Slider) {
            renderer.rightVertexDepth = sender.floatValue
        }

        func setupLabel(_ label: Label, value: Float) {
            DispatchQueue.main.async {
                label.stringValue = String(format: "%.2f", value)
            }
        }
    }
#endif
