//
// Created by Bq Lin on 2021/8/29.
// Copyright © 2021 Bq. All rights reserved.
//

import AppKit
import Foundation

class MetalView: PlatformView, MetalBehavior {
    let lock: NSLock = .init()
    var isPause: Bool = true
    weak var delegate: MetalViewDelegate?
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var displayLink: CVDisplayLink?
    var displaySource: DispatchSourceUserDataAdd?
    var notificaitonObservers = [NSObjectProtocol]()
    
    deinit {
        notificaitonObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        layer?.delegate = self
        
        notificaitonObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            if let displayLink = self.displayLink {
                CVDisplayLinkStop(displayLink)
            }
            if renderOnMainThread, let displaySource = self.displaySource {
                displaySource.cancel()
            }
        })
    }
    
    func setupDisplayLink(for screen: NSScreen?) {
        guard let screen = screen else { return }
        if renderOnMainThread {
            // 使用主队列创建一个调度源，以确保在主线程上执行渲染
            let displaySource = DispatchSource.makeUserDataAddSource(queue: .main)
            displaySource.setEventHandler { [weak self] in
                self?.render()
            }
            displaySource.resume()
            self.displaySource = displaySource
        }
        
        var ret = CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard ret == kCVReturnSuccess else { return }
        let displayLink = self.displayLink!
        
        if renderOnMainThread {
            ret = CVDisplayLinkSetOutputCallback(displayLink, DispatchRenderLoop, &displaySource!)
        } else {
            ret = CVDisplayLinkSetOutputCallback(displayLink, DispatchRenderLoop, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        }
        guard ret == kCVReturnSuccess else { return }
        
        let viewDisplayID = CGDirectDisplayID(screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as! uint)
        ret = CVDisplayLinkSetCurrentCGDisplay(displayLink, viewDisplayID)
        guard ret == kCVReturnSuccess else { return }
        
        CVDisplayLinkStart(displayLink)
    }
    
    func stopRenderLoop() {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            if renderOnMainThread, let displaySource = self.displaySource {
                displaySource.cancel()
            }
        }
    }
    
    // MARK: - override
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if animationRendering {
            setupDisplayLink(for: window?.screen)
        }
        
        if automaticallyResize {
            resizeDrawable(scaleFactor: window?.screen?.backingScaleFactor)
        } else {
            var size = bounds.size
            size.width *= layer!.contentsScale
            size.height *= layer!.contentsScale
            delegate?.drawableResize(size)
        }
    }
    
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard automaticallyResize else { return }
        resizeDrawable(scaleFactor: window?.screen?.backingScaleFactor)
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard automaticallyResize else { return }
        resizeDrawable(scaleFactor: window?.screen?.backingScaleFactor)
    }
    
    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        guard automaticallyResize else { return }
        resizeDrawable(scaleFactor: window?.screen?.backingScaleFactor)
    }
}

extension MetalView: CALayerDelegate {
    func display(_ layer: CALayer) {
        guard !animationRendering else { return }
        renderOnEvent()
    }
    
    func draw(_ layer: CALayer, in ctx: CGContext) {
        guard !animationRendering else { return }
        renderOnEvent()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard !animationRendering else { return }
        renderOnEvent()
    }
}

private func DispatchRenderLoop(displayLink: CVDisplayLink, now: UnsafePointer<CVTimeStamp>, outputTime: UnsafePointer<CVTimeStamp>, flagsIn: CVOptionFlags, flagsOut: UnsafeMutablePointer<CVOptionFlags>, displayLinkContext: UnsafeMutableRawPointer?) -> CVReturn {
    if renderOnMainThread {
        let source = displayLinkContext!.load(as: DispatchSourceUserDataAdd.self)
        source.add(data: 1)
    } else {
        let view = Unmanaged<MetalView>.fromOpaque(displayLinkContext!).takeUnretainedValue()
        view.render()
    }
    
    return kCVReturnSuccess
}
