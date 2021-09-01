//
// Created by Bq Lin on 2021/9/1.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation

#if os(macOS)
    import AppKit
import OpenGL.GL3
    typealias PlatformView = NSOpenGLView
    typealias PlatformViewController = NSViewController
#else
    import GLKit
    import UIKit
    typealias PlatformView = UIView
    typealias PlatformViewController = UIViewController
#endif

class GLView: PlatformView {
    #if os(iOS)
    override class var layerClass: AnyClass { CAEAGLLayer.self }
    #endif
}


class GLViewController: PlatformViewController {
    var glView: GLView { view as! GLView }
    var glRenderer: GLRenderer!
    var glContext: PlatformGLContext!
    var defaultFBOName: GLuint = 0

    var mtlDevice: MTLDevice!
    var mtlRenderer: MetalRenderer!

    var interopTexture: InteropTexture!

    #if os(macOS)
    var displayLink: CVDisplayLink!
    #else
    var displayLink: CADisplayLink!
    var colorRenderBuffer: GLuint = 0
    #endif

    let interopPixelFormat: MTLPixelFormat = .bgra8Unorm

    override func viewDidLoad() {
        super.viewDidLoad()

        prepareView()
        makeCurrentContext()

        glRenderer = .init(FBOName: defaultFBOName)
        mtlDevice = MTLCreateSystemDefaultDevice()
        mtlRenderer = .init(device: mtlDevice, colorPixelFormat: interopPixelFormat)
        interopTexture = .init(mtlDevice: mtlDevice, glContext: glContext, mtlPixelFormat: interopPixelFormat, size: GLRenderer.interopTextureSize)

        glRenderer.useInteropTextureAsBaseMap(interopTexture.glTexture)
        glRenderer.resize(drawableSize)
        mtlRenderer.useTextureFromFileAsBaseMap()
        mtlRenderer.resize(GLRenderer.interopTextureSize)
    }
    
    #if os(macOS)
    override func viewDidLayout() {
        super.viewDidLayout()
        guard let cglContext = glContext.cglContextObj else { fatalError() }
        CGLLockContext(cglContext)
        
        let viewSize = view.bounds.size
        let viewSizeInPixel = view.convertToBacking(viewSize)
        makeCurrentContext()
        glRenderer.resize(viewSizeInPixel)
        
        CGLUnlockContext(cglContext)
        
        if !CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStart(displayLink)
        }
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        CVDisplayLinkStop(displayLink)
    }
    
    deinit {
        CVDisplayLinkStop(displayLink)
        displayLink = nil
    }
    #else
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizeDrawable()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resizeDrawable()
    }
    #endif

}

#if os(macOS)
extension GLViewController {
    var drawableSize: CGSize {
        let viewSize = view.bounds.size
        let viewSizeInPixel = view.convertToBacking(viewSize)
        return viewSizeInPixel
    }
    
    func makeCurrentContext() {
        glContext.makeCurrentContext()
    }
    
    func draw() {
        guard let cglContext = glContext.cglContextObj else { fatalError() }
        CGLLockContext(cglContext)
        
        makeCurrentContext()
        mtlRenderer.draw(to: interopTexture.mtlTexture)
        glRenderer.draw()
        
        CGLFlushDrawable(cglContext)
        CGLUnlockContext(cglContext)
    }
    
    func prepareView() {
        let attrs = [
            NSOpenGLPFAColorSize, 32,
            NSOpenGLPFADoubleBuffer,
            NSOpenGLPFADepthSize, 24,
            0,
            ].map { NSOpenGLPixelFormatAttribute($0) }
        guard let pixelFormat = NSOpenGLPixelFormat(attributes: attrs) else {
            fatalError("No OpenGL pixel format")
        }
        
        glContext = NSOpenGLContext(format: pixelFormat, share: nil)
        
        guard let cglContext = glContext.cglContextObj else { fatalError() }
        CGLLockContext(cglContext)
        makeCurrentContext()
        CGLUnlockContext(cglContext)
        
        glView.pixelFormat = pixelFormat
        glView.openGLContext = glContext
        glView.wantsBestResolutionOpenGLSurface = true
        
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        CVDisplayLinkSetOutputCallback(displayLink, { (displayLink, now, outputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
            let controller = Unmanaged<GLViewController>.fromOpaque(displayLinkContext!).takeUnretainedValue()
            controller.draw()
            return 1
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink, cglContext, pixelFormat.cglPixelFormatObj!)
    }
}
#else
extension GLViewController {
    var drawableSize: CGSize {
        var backingWidth: GLint = 0
        var backingHeight: GLint = 0
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderBuffer)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &backingWidth)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &backingHeight)
        return CGSize(width: CGFloat(backingWidth), height: CGFloat(backingHeight))
    }
    
    func makeCurrentContext() {
        EAGLContext.setCurrent(glContext)
    }
    
    @objc func draw() {
        makeCurrentContext()
        mtlRenderer.draw(to: interopTexture.mtlTexture)
        glRenderer.draw()
        
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderBuffer)
        glContext.presentRenderbuffer(Int(GL_RENDERBUFFER))
    }
    
    func prepareView() {
        let glLayer = view.layer as! CAEAGLLayer
        glLayer.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking: false,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
        ]
        glLayer.isOpaque = true
        
        glContext = EAGLContext(api: .openGLES2)
        makeCurrentContext()
        
        view.contentScaleFactor = UIScreen.main.nativeScale
        
        glGenFramebuffers(1, &defaultFBOName)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), defaultFBOName)
        
        glGenRenderbuffers(1, &colorRenderBuffer)
        
        resizeDrawable()
        
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), colorRenderBuffer)
        
        displayLink = .init(target: self, selector: #selector(self.draw))
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(to: .current, forMode: .default)
    }
    
    func resizeDrawable() {
        makeCurrentContext()
        assert(colorRenderBuffer != 0)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderBuffer)
        glContext.renderbufferStorage(Int(GL_RENDERBUFFER), from: view.layer as? EAGLDrawable)
        if glRenderer != nil {
            glRenderer.resize(drawableSize)
        }
    }
}
#endif
