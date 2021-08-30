//
// Created by Bq Lin on 2021/8/29.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation

#if os(macOS)
import AppKit
typealias PlatformView = NSView
#else
import UIKit
typealias PlatformView = UIView
#endif

import Metal

protocol MetalViewDelegate: AnyObject {
    func drawableResize(_ size: CGSize)
    func render(to metalLayer: CAMetalLayer)
}

protocol MetalBehavior: PlatformView {
    var metalLayer: CAMetalLayer { get }
    var isPause: Bool { get set }
    var delegate: MetalViewDelegate? { get set }
    var lock: NSLock { get }
    
    func commonInit()
    func stopRenderLoop()
    func renderOnEvent()
    func resizeDrawable(scaleFactor: CGFloat?)
    func render()
}

extension MetalBehavior {
    func renderOnEvent() {
        guard !animationRendering else { return }
        
        if renderOnMainThread {
            render()
        } else {
            DispatchQueue.global().async {
                self.render()
            }
        }
    }
    
    func resizeDrawable(scaleFactor: CGFloat?) {
        guard let scaleFactor = scaleFactor else { return }
        var newSize = bounds.size
        newSize.width *= scaleFactor
        newSize.height *= scaleFactor
        guard newSize.width > 0, newSize.height > 0 else {
            return
        }
        
        if renderOnMainThread {
            _resize(newSize)
        } else {
            lock.lock()
            _resize(newSize)
            lock.unlock()
        }
    }
    
    fileprivate func _resize(_ newSize: CGSize) {
        guard newSize.width != metalLayer.drawableSize.width, newSize.height != metalLayer.drawableSize.height else {
            return
        }
        metalLayer.drawableSize = newSize
        delegate?.drawableResize(newSize)
    }
    
    func render() {
        if renderOnMainThread {
            _render()
        } else {
            // 访问CALayer需要在主线程
            DispatchQueue.main.async {
                self.lock.lock()
                self._render()
                self.lock.unlock()
            }
        }
    }
    
    fileprivate func _render() {
        delegate?.render(to: metalLayer)
    }
}
