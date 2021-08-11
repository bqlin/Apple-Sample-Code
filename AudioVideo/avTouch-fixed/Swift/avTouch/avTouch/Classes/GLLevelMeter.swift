//
// Created by Bq Lin on 2021/8/10.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import UIKit
import QuartzCore
import OpenGLES

class GLLevelMeter: LevelMeter {
    var backingWidth: GLint = 0
    var backingHeight: GLint = 0
    var context: EAGLContext!
    var viewRenderBuffer: GLuint = 0, viewFrameBuffer: GLuint = 0
    
    override class var layerClass: AnyClass { CAEAGLLayer.self }
    var glLayer: CAEAGLLayer { layer as! CAEAGLLayer}
    
    var finishedInit = false
    override func commonInit() {
        super.commonInit()
        
        colorThresholds = [
            ColorThreshold(maxValue: 0.6, color: UIColor(red: 0, green: 1, blue: 0, alpha: 1)),
            ColorThreshold(maxValue: 0.9, color: UIColor(red: 1, green: 1, blue: 0, alpha:1)),
            ColorThreshold(maxValue: 1, color: UIColor(red: 1, green: 0, blue: 0, alpha: 1)),
        ]
        
        scaleFactor = UIScreen.main.scale
        contentScaleFactor = scaleFactor
        
        glLayer.isOpaque = true
        glLayer.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking: false,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
        ]
        
        context = EAGLContext(api: .openGLES1)
        guard context != nil, EAGLContext.setCurrent(context), createFrameBuffer() else {
            fatalError()
        }
        
        setupView()
        finishedInit = true
    }
    
    override func layoutSubviews() {
        EAGLContext.setCurrent(context)
        destoryFrameBuffer()
        createFrameBuffer()
        drawView()
    }
    
    override func draw(_ rect: CGRect) {
        drawView()
    }
    
    override func setNeedsDisplay() {
        drawView()
    }
    
    deinit {
        if EAGLContext.current() == context {
            EAGLContext.setCurrent(nil)
        }
    }
}

extension GLLevelMeter {
    func setupView() {
        glViewport(0, 0, backingWidth, backingHeight)
        glMatrixMode(GLenum(GL_PROJECTION))
        glLoadIdentity()
        glOrthof(0, GLfloat(backingWidth), 0, GLfloat(backingHeight), -1, 1)
        glMatrixMode(GLenum(GL_MODELVIEW))
        
        glClearColor(0, 0, 0, 1)
        glEnableClientState(GLenum(GL_VERTEX_ARRAY))
    }
    
    @discardableResult
    func createFrameBuffer() -> Bool {
        glGenFramebuffersOES(1, &viewFrameBuffer)
        glGenRenderbuffersOES(1, &viewRenderBuffer)
        
        glBindFramebufferOES(GLenum(GL_FRAMEBUFFER_OES), viewFrameBuffer)
        glBindRenderbufferOES(GLenum(GL_RENDERBUFFER_OES), viewRenderBuffer)
        context.renderbufferStorage(Int(GL_RENDERBUFFER_OES), from: glLayer)
        glFramebufferRenderbufferOES(GLenum(GL_FRAMEBUFFER_OES), GLenum(GL_COLOR_ATTACHMENT0_OES), GLenum(GL_RENDERBUFFER_OES), viewRenderBuffer)
        
        glGetRenderbufferParameterivOES(GLenum(GL_RENDERBUFFER_OES), GLenum(GL_RENDERBUFFER_WIDTH_OES), &backingWidth)
        glGetRenderbufferParameterivOES(GLenum(GL_RENDERBUFFER_OES), GLenum(GL_RENDERBUFFER_HEIGHT_OES), &backingHeight)
        
        let status = glCheckFramebufferStatusOES(GLenum(GL_FRAMEBUFFER_OES))
        guard status == GL_FRAMEBUFFER_COMPLETE_OES else {
            print("failed to make complete framebuffer object \(status)")
            return false
        }
        return true
    }
    
    func destoryFrameBuffer() {
        glDeleteFramebuffersOES(1, &viewFrameBuffer)
        viewFrameBuffer = 0
        glDeleteRenderbuffersOES(1, &viewRenderBuffer)
        viewRenderBuffer = 0
    }
    
    func drawView() {
        guard finishedInit else { return }
        guard viewFrameBuffer != 0 else { fatalError() }
        
        EAGLContext.setCurrent(context)
        
        glBindFramebufferOES(GLenum(GL_FRAMEBUFFER_OES), viewFrameBuffer)
        
        guard let bgc = bgColor?.cgColor, bgc.numberOfComponents == 4 else {
            fatalError()
        }
        let bgcComponents = bgc.components!.map { GLfloat($0) }
        
        glClearColor(bgcComponents[0], bgcComponents[1], bgcComponents[2], 1)
        //glClearColor(1, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        glPushMatrix()
        
        var bds: CGRect
        if isVertical {
            glScalef(1, -1, 1)
            bds = CGRect(x: 0, y: -1, width: bounds.width * scaleFactor, height: bounds.height * scaleFactor)
        } else {
            glTranslatef(0, GLfloat(bounds.height * scaleFactor), 0)
            glRotatef(-90, 0, 0, 1)
            bds = CGRect(x: 0, y: 1, width: bounds.height * scaleFactor, height: bounds.width * scaleFactor)
        }
        
        if numLights == 0 {
            var currentTop: CGFloat = 0
            for thresh in colorThresholds {
                let val = min(thresh.maxValue, level)
                let rect = CGRect(x: 0, y: bds.height * CGFloat(currentTop), width: bds.width, height: bds.height * (val - CGFloat(currentTop)))
                print("Drawing rect \(rect)")
                
                let vertices = [
                    rect.minX, rect.minY,
                    rect.maxX, rect.minY,
                    rect.minX, rect.maxY,
                    rect.maxX, rect.maxY
                ].map { GLfloat($0) }
                
                let rgba = thresh.color.cgColor.components!.map { GLfloat($0) }
                guard rgba.count == 4 else { fatalError() }
                glColor4f(rgba[0], rgba[1], rgba[2], rgba[3])
                
                glVertexPointer(2, GLenum(GL_FLOAT), 0, vertices)
                glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
                
                guard level >= thresh.maxValue else { break }
                currentTop = val
            }
        } else {
            var lightMinVal: CGFloat = 0
            var insetAmount, lightVSpace: CGFloat
            lightVSpace = bds.height / CGFloat(numLights)
            if lightVSpace < 4 {
                insetAmount = 0
            } else if lightVSpace < 8 {
                insetAmount = 0.5
            } else {
                insetAmount = 1
            }
            
            var peakLight = -1
            if peakLevel > 0 {
                peakLight = Int(peakLevel * CGFloat(numLights))
                if peakLight >= numLights {
                    peakLight = numLights - 1
                }
            }
            
            for light_i in 0 ..< numLights {
                let lightMaxVal = CGFloat(light_i + 1) / CGFloat(numLights)
                var lightIntensity: CGFloat
                
                if light_i == peakLight {
                    lightIntensity = 1
                } else {
                    lightIntensity = (level - lightMinVal) / (lightMaxVal - lightMinVal)
                    lightIntensity = min(max(lightIntensity, 0), 1)
                    if !isVariableLightIntensity && lightIntensity > 0 {
                        lightIntensity = 1
                    }
                }
                
                var lightColor = colorThresholds[0].color
                for color_i in 0 ..< colorThresholds.count - 1 {
                    let thisThresh = colorThresholds[color_i]
                    let nextThresh = colorThresholds[color_i + 1]
                    if thisThresh.maxValue <= lightMaxVal {
                        lightColor = nextThresh.color
                    }
                }
                
                var lightRect = CGRect(x: 0, y: bds.height * CGFloat(light_i) / CGFloat(numLights), width: bds.width, height: bds.height / CGFloat(numLights))
                lightRect = lightRect.insetBy(dx: insetAmount, dy: insetAmount)
                
                let vertices = [
                    lightRect.minX, lightRect.minY,
                    lightRect.maxX, lightRect.minY,
                    lightRect.minX, lightRect.maxY,
                    lightRect.maxX, lightRect.maxY
                ].map { GLfloat($0) }
                
                glVertexPointer(2, GLenum(GL_FLOAT), 0, vertices)
                
                glColor4f(1, 0, 0, 1)
                
                
                if lightIntensity == 1.0 {
                    let color = lightColor.cgColor
                    if color.numberOfComponents == 4 {
                        let rgba = color.components!.map { GLfloat($0) }
                        glColor4f(rgba[0], rgba[1], rgba[2], rgba[3])
                        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
                    }
                } else if lightIntensity > 0 {
                    let color = lightColor.cgColor
                    if color.numberOfComponents == 4 {
                        let rgba = color.components!.map { GLfloat($0) }
                        glColor4f(rgba[0], rgba[1], rgba[2], rgba[3])
                        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
                    }
                }
                
                lightMinVal = lightMaxVal
            }
        }
        
        glPopMatrix()
        glFlush()
        glBindRenderbufferOES(GLenum(GL_RENDERBUFFER_OES), viewRenderBuffer)
        context.presentRenderbuffer(Int(GL_RENDERBUFFER_OES))
    }
}
