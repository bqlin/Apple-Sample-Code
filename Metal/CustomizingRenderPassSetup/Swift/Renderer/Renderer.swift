//
// Created by Bq Lin on 2021/8/22.
// Copyright © 2021 Bq. All rights reserved.
//

import MetalKit

class Renderer: NSObject {
    let device: MTLDevice
    var commandQueue: MTLCommandQueue!
    var aspectRatio: Float!
    
    var renderTargetTexture: MTLTexture!
    let targetRenderPassDescriptor = MTLRenderPassDescriptor()
    
    var offscreenRenderPipeline: MTLRenderPipelineState!
    var drawableRenderPipeline: MTLRenderPipelineState!

    init(view: MTKView) {
        device = view.device!

        super.init()
        view.delegate = self
        view.clearColor = .init(red: 1, green: 0, blue: 0, alpha: 1)
        aspectRatio = Float(view.drawableSize.height / view.drawableSize.width)

        commandQueue = device.makeCommandQueue()!

        // Set up a texture for rendering to and sampling from
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.width = 512
        textureDescriptor.height = 512
        textureDescriptor.pixelFormat = .rgba8Unorm
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        renderTargetTexture = device.makeTexture(descriptor: textureDescriptor)
        assert(renderTargetTexture != nil, "创建目标纹理失败")

        let colorAttachment = targetRenderPassDescriptor.colorAttachments[0]!
        colorAttachment.texture = renderTargetTexture
        colorAttachment.loadAction = .clear
        colorAttachment.clearColor = .init(red: 1, green: 1, blue: 1, alpha: 1)
        colorAttachment.storeAction = .store
        targetRenderPassDescriptor.colorAttachments[0] = colorAttachment

        // 配置视图渲染管线
        guard let defaultLibrary = device.makeDefaultLibrary() else { fatalError("加载着色器失败") }
        let piplineDescriptor = MTLRenderPipelineDescriptor()
        piplineDescriptor.label = "Drawable Render Pipeline"
        piplineDescriptor.sampleCount = view.sampleCount
        piplineDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "textureVertexShader")
        piplineDescriptor.fragmentFunction = defaultLibrary.makeFunction(name: "textureFragmentShader")
        piplineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        piplineDescriptor.vertexBuffers[Int(AAPLVertexInputIndexVertices.rawValue)].mutability = .immutable
        do {
            drawableRenderPipeline = try device.makeRenderPipelineState(descriptor: piplineDescriptor)
        } catch {
            fatalError("渲染管线创建失败")
        }

        // 配置离屏渲染纹理
        piplineDescriptor.label = "Offscreen Render Pipeline"
        piplineDescriptor.sampleCount = 1
        piplineDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "simpleVertexShader")
        piplineDescriptor.fragmentFunction = defaultLibrary.makeFunction(name: "simpleFragmentShader")
        piplineDescriptor.colorAttachments[0].pixelFormat = renderTargetTexture.pixelFormat
        do {
            offscreenRenderPipeline = try device.makeRenderPipelineState(descriptor: piplineDescriptor)
        } catch {
            fatalError("离屏渲染管线创建失败")
        }
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspectRatio = Float(size.height / size.width)
    }

    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { fatalError("命令缓冲区创建失败") }
        commandBuffer.label = "Command Buffer"
        
        drawOffscreen(commandBuffer: commandBuffer)
        drawOnscreen(view: view, commandBuffer: commandBuffer)
        
        commandBuffer.commit()
    }

    /// 离屏绘制三角形
    func drawOffscreen(commandBuffer: MTLCommandBuffer) {
        let triangleVertices: [AAPLSimpleVertex] = [
            // Positions     ,  Colors
            .init([0.5, -0.5], [1.0, 0.0, 0.0, 1.0]),
            .init([-0.5, -0.5], [0.0, 1.0, 0.0, 1.0]),
            .init([0.0, 0.5], [0.0, 0.0, 1.0, 0.0]),
        ]

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: targetRenderPassDescriptor)!
        encoder.label = "Offscreen Render Pass"
        encoder.setRenderPipelineState(offscreenRenderPipeline)
        encoder.setVertexBytes(triangleVertices, length: MemoryLayout<AAPLSimpleVertex>.size * triangleVertices.count, index: Int(AAPLVertexInputIndexVertices.rawValue))
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triangleVertices.count)
        encoder.endEncoding()
    }

    /// 把离屏纹理绘制在白色矩形中
    func drawOnscreen(view: MTKView, commandBuffer: MTLCommandBuffer) {
        guard let passDecriptor = view.currentRenderPassDescriptor else { return }

        let quadVertices: [AAPLTextureVertex] = [
            // Positions     , Texture coordinates
            .init([0.5, -0.5], [1.0, 1.0]),
            .init([-0.5, -0.5], [0.0, 1.0]),
            .init([-0.5, 0.5], [0.0, 0.0]),
            .init([0.5, -0.5], [1.0, 1.0]),
            .init([-0.5, 0.5], [0.0, 0.0]),
            .init([0.5, 0.5], [1.0, 0.0]),
        ]
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDecriptor)!
        encoder.label = "Drawable Render Pass"
        encoder.setRenderPipelineState(drawableRenderPipeline)
        encoder.setVertexBytes(quadVertices, length: MemoryLayout<AAPLTextureVertex>.size * quadVertices.count, index: Int(AAPLVertexInputIndexVertices.rawValue))
        encoder.setVertexBytes(&aspectRatio, length: MemoryLayout.size(ofValue: aspectRatio), index: Int(AAPLVertexInputIndexAspectRatio.rawValue))
        
        encoder.setFragmentTexture(renderTargetTexture, index: Int(AAPLTextureInputIndexColor.rawValue))
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: quadVertices.count)
        
        encoder.endEncoding()
        commandBuffer.present(view.currentDrawable!)
    }
}

extension AAPLSimpleVertex {
    init(_ position: vector_float2, _ color: vector_float4) {
        self.init()
        self.position = position
        self.color = color
    }
}

extension AAPLTextureVertex {
    init(_ position: vector_float2, _ texcoord: vector_float2) {
        self.init()
        self.position = position
        self.texcoord = texcoord
    }
}
