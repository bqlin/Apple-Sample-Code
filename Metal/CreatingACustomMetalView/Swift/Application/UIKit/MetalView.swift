//
// Created by Bq Lin on 2021/8/29.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import UIKit

class MetalView: PlatformView, MetalBehavior {
    let lock: NSLock = .init()
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    weak var delegate: MetalViewDelegate?
    var displayLink: CADisplayLink?
    var notificaitonObservers = [NSObjectProtocol]()
    
    var renderThread: Thread?
    var continureRunloop: Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    func commonInit() {
        notificaitonObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { (notification) in
            self.isPause = true
        })
        notificaitonObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { (notification) in
            self.isPause = false
        })
    }
    
    deinit {
        notificaitonObservers.forEach{ NotificationCenter.default.removeObserver($0) }
    }

    func setupDisplayLink() {
        if animationRendering {
            guard let window = window else {
                displayLink?.invalidate()
                displayLink = nil
                return
            }
            
            stopRenderLoop()
            
            let link = window.screen.displayLink(withTarget: self, selector: #selector(_render))!
            link.preferredFramesPerSecond = 60
            displayLink = link
            
            if renderOnMainThread {
                displayLink?.add(to: .current, forMode: .common)
            } else {
                lock.lock()
                continureRunloop = false
                lock.unlock()
                
                // 在另外一个线程执行开辟一个runloop
                let thread = Thread(block: { [weak self] in
                    self?.runThread()
                })
                renderThread = thread
                continureRunloop = true
                thread.start()
                DispatchQueue.global().async {}
            }
        }
        
        if automaticallyResize {
            resizeDrawable(scaleFactor: window?.screen.nativeScale)
        } else {
            var size = bounds.size
            size.width *= layer.contentsScale
            size.height *= layer.contentsScale
            delegate?.drawableResize(size)
        }
    }

    @objc private func _render() {
        render()
    }
    
    let customRunLoopMode = RunLoop.Mode("DisplayLinkMode")
    func runThread() {
        guard !renderOnMainThread else { return }
        guard let displayLink = displayLink else { return }
        let runLoop = RunLoop.current
        displayLink.add(to: runLoop, forMode: customRunLoopMode)
        
        var continureRunloop = true
        while continureRunloop {
            _ = autoreleasepool {
                runLoop.run(mode: customRunLoopMode, before: .distantFuture)
            }
            lock.lock()
            continureRunloop = self.continureRunloop
            lock.unlock()
        }
    }

    func stopRenderLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    var isPause: Bool {
        get { displayLink?.isPaused ?? true }
        set { displayLink?.isPaused = newValue }
    }

    // MARK: - override

    override class var layerClass: AnyClass { CAMetalLayer.self }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setupDisplayLink()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resizeDrawable(scaleFactor: window?.screen.nativeScale)
    }

    override var frame: CGRect {
        didSet {
            resizeDrawable(scaleFactor: window?.screen.nativeScale)
        }
    }

    override var bounds: CGRect {
        didSet {
            resizeDrawable(scaleFactor: window?.screen.nativeScale)
        }
    }

    override func draw(_ rect: CGRect) {
        guard animationRendering else {
            super.draw(rect)
            return
        }
        renderOnEvent()
    }

    override func display(_ layer: CALayer) {
        guard animationRendering else {
            super.display(layer)
            return
        }
        renderOnEvent()
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        guard animationRendering else {
            super.draw(layer, in: ctx)
            return
        }
        renderOnEvent()
    }
}
