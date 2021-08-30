//
// Created by Bq Lin on 2021/8/29.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import Metal
import QuartzCore

class Renderer: NSObject {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var renderPipeline: MTLRenderPipelineState!
    var vertexBuffer: MTLBuffer!
    var depthTarget: MTLTexture!
    
    var renderPassDescriptor: MTLRenderPassDescriptor!
    var viewportSize = vector_uint2()
    
    let depthPixelFormat = MTLPixelFormat.depth32Float
    var frameNumber = 0
    
    init(device: MTLDevice, drawablePixelFormat: MTLPixelFormat) {
        self.device = device
        commandQueue = device.makeCommandQueue()!
        
        // 渲染通道
        let passDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor = passDescriptor
        let colorAttachment = passDescriptor.colorAttachments[0]!
        colorAttachment.loadAction = .clear
        colorAttachment.storeAction = .store
        colorAttachment.clearColor = .init(red: 0, green: 1, blue: 1, alpha: 1)
        if createDepthBuffer {
            passDescriptor.depthAttachment.loadAction = .clear
            passDescriptor.depthAttachment.storeAction = .dontCare
            passDescriptor.depthAttachment.clearDepth = 1
        }
        
        let defaultLibrary = device.makeDefaultLibrary()!
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")!
        let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader")!
        
        // 渲染管线
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "渲染管线"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = drawablePixelFormat
        if createDepthBuffer {
            pipelineDescriptor.depthAttachmentPixelFormat = depthPixelFormat
        }
        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("创建渲染管线失败，\(error)")
        }
        
        // 顶点
        vertexBuffer = device.makeBuffer(bytes: quadVertices, length: MemoryLayout<AAPLVertex>.size * quadVertices.count, options: .storageModeShared)
        vertexBuffer.label = "四边形"
    }
    
    let quadVertices: [AAPLVertex] = [
        .init(position: [+250, -250], color: [1, 0, 0]),
        .init(position: [-250, -250], color: [0, 1, 0]),
        .init(position: [-250, +250], color: [0, 0, 1]),
        
        .init(position: [+250, -250], color: [1, 0, 0]),
        .init(position: [-250, +250], color: [0, 0, 1]),
        .init(position: [+250, +250], color: [1, 0, 1]),
    ]
    
    func render(to metalLayer: CAMetalLayer) {
        frameNumber += 1
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        guard let currentDrawable = metalLayer.nextDrawable() else { return }
        renderPassDescriptor.colorAttachments[0].texture = currentDrawable.texture
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(renderPipeline)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: Int(AAPLVertexInputIndexVertices.rawValue))
        
        var uniforms = AAPLUniforms()
        if animationRendering {
            uniforms.scale = 0.5 + (1.0 + 0.5 * sin(Float(frameNumber) * 0.1))
        } else {
            uniforms.scale = 1
        }
        uniforms.viewportSize = viewportSize
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout.size(ofValue: uniforms), index: Int(AAPLVertexInputIndexUniforms.rawValue))
        
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: quadVertices.count)
        renderEncoder.endEncoding()
        
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
    
    func drawableResize(_ size: CGSize) {
        viewportSize.x = UInt32(size.width)
        viewportSize.y = UInt32(size.height)
        
        if createDepthBuffer {
            let depthTargetDecriptor = MTLTextureDescriptor()
            depthTargetDecriptor.width = Int(size.width)
            depthTargetDecriptor.height = Int(size.height)
            depthTargetDecriptor.pixelFormat = depthPixelFormat
            depthTargetDecriptor.storageMode = .private
            depthTargetDecriptor.usage = .renderTarget
            
            depthTarget = device.makeTexture(descriptor: depthTargetDecriptor)
            renderPassDescriptor.depthAttachment.texture = depthTarget
        }
    }
}
