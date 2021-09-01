//
// Created by Bq Lin on 2021/9/1.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import MetalKit

class MetalViewController: PlatformViewController {
    var mtlView: MTKView { view as! MTKView }
    var interopTexture: InteropTexture!
    var glContext: PlatformGLContext!
    var glRenderer: GLRenderer!
    var mtlRenderer: MetalRenderer!

    let interopPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    override func viewDidLoad() {
        super.viewDidLoad()

        prepareView()
        makeCurrentContext()

        mtlRenderer = .init(device: mtlView.device!, colorPixelFormat: mtlView.colorPixelFormat)
        mtlRenderer.resize(mtlView.drawableSize)
        interopTexture = .init(mtlDevice: mtlView.device!, glContext: glContext, mtlPixelFormat: interopPixelFormat, size: GLRenderer.interopTextureSize)

        makeCurrentContext()
        glRenderer = .init(FBOName: defaultFBO(interopTexture: interopTexture))
        glRenderer.useTextureFromFileAsBaseMap()
        glRenderer.resize(GLRenderer.interopTextureSize)

        mtlRenderer.useInteropTextureAsBaseMap(interopTexture.mtlTexture)
    }
}

extension MetalViewController {
    func makeCurrentContext() {
        #if os(macOS)
            glContext.makeCurrentContext()
        #else
            EAGLContext.setCurrent(glContext)
        #endif
    }

    func prepareView() {
        mtlView.device = MTLCreateSystemDefaultDevice()
        mtlView.colorPixelFormat = interopPixelFormat
        mtlView.delegate = self

        #if os(macOS)
            let attrs = [
                NSOpenGLPFAAccelerated,
                0,
            ].map { NSOpenGLPixelFormatAttribute($0) }
            guard let pixelFormat = NSOpenGLPixelFormat(attributes: attrs) else {
                fatalError("No OpenGL pixel format")
            }
            glContext = NSOpenGLContext(format: pixelFormat, share: nil)
        #else
            glContext = EAGLContext(api: .openGLES2)
            makeCurrentContext()
        #endif
    }

    func defaultFBO(interopTexture: InteropTexture) -> GLuint {
        var defaultFBOName: GLuint = 0
        glGenFramebuffers(1, &defaultFBOName)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), defaultFBOName)

        #if os(macOS)
            let texType = GL_TEXTURE_RECTANGLE
        #else
            let texType = GL_TEXTURE_2D
        #endif

        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(texType), interopTexture.glTexture, 0)
        GetGLError()
        return defaultFBOName
    }
}

extension MetalViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        mtlRenderer.resize(size)
    }

    func draw(in view: MTKView) {
        makeCurrentContext()
        glRenderer.draw()
        glFlush()
        mtlRenderer.draw(to: view)
    }
}
