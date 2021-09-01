//
// Created by Bq Lin on 2021/9/1.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import MetalKit

// 若修改为.bgra8Unorm则可以确保与GL展示效果一致
let interopPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

class MetalViewController: PlatformViewController {
    var mtlView: MTKView { view as! MTKView }
    var interopTexture: InteropTexture!
    var glContext: PlatformGLContext!
    var glRenderer: GLRenderer!
    var mtlRenderer: MetalRenderer!

    override func viewDidLoad() {
        super.viewDidLoad()

        prepareView()

        mtlRenderer = .init(device: mtlView.device!, colorPixelFormat: mtlView.colorPixelFormat)
        mtlRenderer.resize(mtlView.drawableSize)
        interopTexture = .init(mtlDevice: mtlView.device!, glContext: glContext, mtlPixelFormat: interopPixelFormat, size: interopTextureSize)
        mtlRenderer.useInteropTextureAsBaseMap(interopTexture.mtlTexture)

        //makeCurrentContext()
        glRenderer = .init(FBOName: defaultFBO(interopTexture: interopTexture))
        glRenderer.useTextureFromFileAsBaseMap()
        glRenderer.resize(interopTextureSize)
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
        // 配置视图
        mtlView.device = MTLCreateSystemDefaultDevice()
        mtlView.colorPixelFormat = interopPixelFormat
        mtlView.delegate = self

        // 创建并绑定上下文
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
        #endif
        makeCurrentContext()
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
        glFlush() // 用此确保GL绘制命令的执行，便于Metal读取
        mtlRenderer.draw(to: view)
    }
}
