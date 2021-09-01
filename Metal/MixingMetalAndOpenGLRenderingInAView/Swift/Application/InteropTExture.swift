//
// Created by Bq Lin on 2021/9/1.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import Metal

#if os(macOS)
import AppKit
typealias PlatformGLContext = NSOpenGLContext
#else
import UIKit
typealias PlatformGLContext = EAGLContext
#endif

class InteropTexture: NSObject {
    let mtlDevice: MTLDevice
    var mtlTexture: MTLTexture!

    let glContext: PlatformGLContext
    var glTexture: GLuint = 0

    let formatInfo: TextureFormatInfo
    var cvPixelBuffer: CVPixelBuffer!

    #if os(macOS)
        var cvglTextureCache: CVOpenGLTextureCache!
        var cvglTexture: CVOpenGLTexture!
        var cglPixelFormat: CGLPixelFormatObj
    #else
    var cvglTextureCache: CVOpenGLESTextureCache!
    var cvglTexture: CVOpenGLESTexture!
    #endif

    var cvmtlTextureCahce: CVMetalTextureCache!
    var cvmtlTexture: CVMetalTexture!

    let size: (width: Int, height: Int)

    init(mtlDevice: MTLDevice, glContext: PlatformGLContext, mtlPixelFormat: MTLPixelFormat, size: CGSize) {
        formatInfo = .make(form: mtlPixelFormat)
        self.size = (Int(size.width), Int(size.height))
        self.mtlDevice = mtlDevice
        self.glContext = glContext
        #if os(macOS)
            cglPixelFormat = glContext.pixelFormat.cglPixelFormatObj!
        #endif

        let cvBufferOptions = [
            kCVPixelBufferOpenGLCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        let cvret = CVPixelBufferCreate(kCFAllocatorDefault, self.size.width, self.size.height, formatInfo.cvPixelFormat, cvBufferOptions as CFDictionary, &cvPixelBuffer)
        assert(cvret == kCVReturnSuccess, "创建CVPixelBuffer失败")

        super.init()
        createGLTexture()
        createMetalTexture()
    }
}

extension InteropTexture {
    func createMetalTexture() {
        var cvret: CVReturn
        cvret = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, mtlDevice, nil, &cvmtlTextureCahce)
        assert(cvret == kCVReturnSuccess, "创建Metal纹理缓存失败")

        cvret = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cvmtlTextureCahce, cvPixelBuffer, nil, formatInfo.mtlFormat, size.width, size.height, 0, &cvmtlTexture)
        assert(cvret == kCVReturnSuccess, "从PixelBuffer创建CoreVideo纹理失败")

        mtlTexture = CVMetalTextureGetTexture(cvmtlTexture)!
    }

    #if os(macOS)
        func createGLTexture() {
            var cvret: CVReturn
            cvret = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, nil, glContext.cglContextObj!, cglPixelFormat, nil, &cvglTextureCache)
            assert(cvret == kCVReturnSuccess, "创建OpenGL纹理缓存失败")

            cvret = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cvglTextureCache, cvPixelBuffer, nil, &cvglTexture)
            assert(cvret == kCVReturnSuccess, "从PixelBuffer创建OpenGL纹理失败")
            glTexture = CVOpenGLTextureGetName(cvglTexture)
        }
    #else
        func createGLTexture() {
            var cvret: CVReturn
            cvret = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, glContext, nil, &cvglTextureCache)
            assert(cvret == kCVReturnSuccess, "创建GLES纹理缓存失败")
            
            cvret = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cvglTextureCache, cvPixelBuffer, nil, GLenum(GL_TEXTURE_2D), formatInfo.glInternalFormat, GLsizei(size.width), GLsizei(size.height), GLenum(formatInfo.glFormat), GLenum(formatInfo.glType), 0, &cvglTexture)
            assert(cvret == kCVReturnSuccess, "从PixelBuffer创建GLES纹理失败")
            
            glTexture = CVOpenGLESTextureGetName(cvglTexture)
    }
    #endif
}

#if os(macOS)
#else
let GL_UNSIGNED_INT_8_8_8_8_REV: GLint = 0x8367
#endif
struct TextureFormatInfo {
    var cvPixelFormat: OSType
    var mtlFormat: MTLPixelFormat
    var glInternalFormat: GLint
    var glFormat: GLint
    var glType: GLint

    #if os(macOS)
        static let formatTable: [TextureFormatInfo] = [
            TextureFormatInfo(cvPixelFormat: kCVPixelFormatType_32BGRA, mtlFormat: .bgra8Unorm, glInternalFormat: GL_RGBA, glFormat: GL_BGRA_EXT, glType: GL_UNSIGNED_INT_8_8_8_8_REV),
            TextureFormatInfo(cvPixelFormat: kCVPixelFormatType_ARGB2101010LEPacked, mtlFormat: .bgr10a2Unorm, glInternalFormat: GL_RGB10_A2, glFormat: GL_BGRA, glType: GL_UNSIGNED_INT_2_10_10_10_REV),
            TextureFormatInfo(cvPixelFormat: kCVPixelFormatType_32BGRA, mtlFormat: .bgra8Unorm_srgb, glInternalFormat: GL_SRGB8_ALPHA8, glFormat: GL_BGRA, glType: GL_UNSIGNED_INT_8_8_8_8_REV),
            TextureFormatInfo(cvPixelFormat: kCVPixelFormatType_64RGBAHalf, mtlFormat: .rgba16Float, glInternalFormat: GL_RGBA, glFormat: GL_RGBA, glType: GL_HALF_FLOAT),
        ]
    #else
        static let formatTable: [TextureFormatInfo] = [
            TextureFormatInfo(cvPixelFormat: kCVPixelFormatType_32BGRA, mtlFormat: .bgra8Unorm, glInternalFormat: GL_RGBA, glFormat: GL_BGRA_EXT, glType: GL_UNSIGNED_INT_8_8_8_8_REV),
            TextureFormatInfo(cvPixelFormat: kCVPixelFormatType_32BGRA, mtlFormat: .bgra8Unorm_srgb, glInternalFormat: GL_RGBA, glFormat: GL_BGRA_EXT, glType: GL_UNSIGNED_INT_8_8_8_8_REV),
        ]
    #endif

    static func make(form metalPixelFormat: MTLPixelFormat) -> TextureFormatInfo {
        let info = formatTable.filter { (info) -> Bool in
            info.mtlFormat == metalPixelFormat
        }.first!
        return info
    }
}
