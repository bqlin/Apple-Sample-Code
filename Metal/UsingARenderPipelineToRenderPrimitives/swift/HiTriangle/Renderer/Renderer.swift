//
//  Renderer.swift
//  HiTriangle-iOS
//
//  Created by Bq Lin on 2021/5/12.
//  Copyright © 2021 Bq. All rights reserved.
//

import MetalKit
import simd

class Renderer: NSObject, MTKViewDelegate {
    init(mtkView: MTKView) {
        device = mtkView.device!
        super.init()
        
        mtkView.delegate = self
        viewportSize = [UInt32(mtkView.drawableSize.width), UInt32(mtkView.drawableSize.height)]
        
        guard let defaultLibrary = device.makeDefaultLibrary() else { return }
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")
        let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Simple Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print(error)
        }
        
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("can not make command queue")
        }
        self.commandQueue = commandQueue
    }
    
    let device: MTLDevice
    var pipelineState: MTLRenderPipelineState!
    var commandQueue: MTLCommandQueue!
    var viewportSize: vector_uint2!
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = [UInt32(size.width), UInt32(size.height)]
    }
    
    let triangleVertices: [AAPLVertex] = [
        AAPLVertex(position: [250, -250], color: [1, 0, 0, 1]),
        AAPLVertex(position: [-250, -250], color: [0, 1, 0, 1]),
        AAPLVertex(position: [0, 250], color: [0, 0, 1, 1]),
    ]
    
    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "MyCommand"
        
        if let passDescriptor = view.currentRenderPassDescriptor {
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
            renderEncoder.label = "MyRenderEncoder"
            renderEncoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(viewportSize.x), height: Double(viewportSize.y), znear: 0, zfar: 1))
            renderEncoder.setRenderPipelineState(pipelineState)
            
            // 注意：区别于C数组，要获取Swift数组转换到C语言的字节大小，不能直接sizeof数组名（要注意是数组名，如果是普通指针也不对，sizeof普通指针只是指针的大小）。Swift中还是要用元素大小x元素个数得出。
            renderEncoder.setVertexBytes(triangleVertices, length: MemoryLayout<AAPLVertex>.size * triangleVertices.count, index: Int(AAPLVertexInputIndexVertices.rawValue))
            renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout.size(ofValue: viewportSize), index: Int(AAPLVertexInputIndexViewportSize.rawValue))
            
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            
            renderEncoder.endEncoding()
            
            commandBuffer.present(view.currentDrawable!)
        }
        commandBuffer.commit()
    }
}
