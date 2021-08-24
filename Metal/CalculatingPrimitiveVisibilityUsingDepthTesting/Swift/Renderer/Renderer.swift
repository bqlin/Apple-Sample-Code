//
// Created by Bq Lin on 2021/8/22.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import MetalKit

class Renderer: NSObject {
    @objc dynamic var topVertexDepth: Float = 0
    @objc dynamic var leftVertexDepth: Float = 0
    @objc dynamic var rightVertexDepth: Float = 0

    private let device: MTLDevice
    private var commandQueue: MTLCommandQueue!
    private var renderState: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!
    private var viewportSize: vector_uint2!

    init(view: MTKView) {
        device = view.device!
        super.init()
        view.clearColor = .init(red: 0, green: 0, blue: 0, alpha: 1)
        view.depthStencilPixelFormat = .depth32Float
        // Indicate that Metal should clear all values in the depth buffer to `1.0` when you create a render command encoder with the MetalKit view's `currentRenderPassDescriptor` property.
        view.clearDepth = 1

        viewportSize = [UInt32(view.drawableSize.width), UInt32(view.drawableSize.height)]
        view.delegate = self

        guard let defaultLibrary = device.makeDefaultLibrary(),
              let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader"),
              let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader")
        else { fatalError("无法加载着色器") }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Render Pipeline"
        pipelineDescriptor.sampleCount = view.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipelineDescriptor.vertexBuffers[Int(AAPLVertexInputIndexVertices.rawValue)].mutability = .immutable

        do {
            renderState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("创建渲染管线失败，\(error)")
        }

        let stencilDecriptor = MTLDepthStencilDescriptor()
        stencilDecriptor.depthCompareFunction = .lessEqual
        stencilDecriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: stencilDecriptor)
        guard depthState != nil else { fatalError("创建深度模版失败") }

        commandQueue = device.makeCommandQueue()
        guard commandQueue != nil else { fatalError("创建命令队列失败") }
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = [UInt32(size.width), UInt32(size.height)]
    }

    // 先绘制矩形，再绘制三角形，都设置了深度值
    func draw(in view: MTKView) {
        guard viewportSize != nil else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            debugPrint("创建命令缓冲区失败")
            return
        }
        commandBuffer.label = "Command Buffer"

        if let passDescriptor = view.currentRenderPassDescriptor {
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
            renderEncoder.label = "Render Encoder"
            renderEncoder.setRenderPipelineState(renderState)
            renderEncoder.setDepthStencilState(depthState)

            let floatSize: (x: Float, y: Float) = (Float(viewportSize.x), Float(viewportSize.y))

            renderEncoder.setVertexBytes(&viewportSize!, length: MemoryLayout.size(ofValue: viewportSize), index: Int(AAPLVertexInputIndexViewport.rawValue))
            
            // 矩形顶点，设置顶点深度值为0.5
            let quadVertices: [AAPLVertex] = [
                // Pixel positions (x, y) and clip depth (z),RGBA colors.
                .init([100              , 100              , 0.5], [0.5, 0.5, 0.5, 1]),
                .init([100              , floatSize.y - 100, 0.5], [0.5, 0.5, 0.5, 1]),
                .init([floatSize.x - 100, floatSize.y - 100, 0.5], [0.5, 0.5, 0.5, 1]),
                .init([100              , 100              , 0.5], [0.5, 0.5, 0.5, 1]),
                .init([floatSize.x - 100, floatSize.y - 100, 0.5], [0.5, 0.5, 0.5, 1]),
                .init([floatSize.x - 100, 100              , 0.5], [0.5, 0.5, 0.5, 1]),
            ]
            renderEncoder.setVertexBytes(quadVertices, length: MemoryLayout<AAPLVertex>.size * quadVertices.count, index: Int(AAPLVertexInputIndexVertices.rawValue))
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: quadVertices.count)

            // 三角形顶点
            let triangleVertices: [AAPLVertex] = [
                .init([200              , floatSize.y - 200, leftVertexDepth] , [1, 1, 1, 1]),
                .init([floatSize.x / 2.0, 200              , topVertexDepth]  , [1, 1, 1, 1]),
                .init([floatSize.x - 200, floatSize.y - 200, rightVertexDepth], [1, 1, 1, 1]),
            ]
            renderEncoder.setVertexBytes(triangleVertices, length: MemoryLayout<AAPLVertex>.size * triangleVertices.count, index: Int(AAPLVertexInputIndexVertices.rawValue))
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triangleVertices.count)
            
            renderEncoder.endEncoding()
            commandBuffer.present(view.currentDrawable!)
        } else {
            debugPrint("无法获取渲染通道")
        }

        commandBuffer.commit()
    }
}

extension AAPLVertex {
    init(_ position: vector_float3, _ color: vector_float4) {
        self.init()
        self.position = position
        self.color = color
    }
}
