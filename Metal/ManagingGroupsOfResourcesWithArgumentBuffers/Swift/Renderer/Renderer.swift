//
// Created by Bq Lin on 2021/8/23.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import MetalKit

class Renderer: NSObject {
    let device: MTLDevice
    var commandQueue: MTLCommandQueue!

    var vertexBuffer: MTLBuffer!
    var numVertices: Int = 0
    var renderPipeline: MTLRenderPipelineState!
    var texture: MTLTexture!
    var sampler: MTLSamplerState!
    var indirectBuffer: MTLBuffer!
    var fragmentShaderArgumentBuffer: MTLBuffer!
    var viewport: MTLViewport!

    init(view: MTKView) {
        device = view.device!

        super.init()
        view.delegate = self
        view.clearColor = .init(red: 0, green: 0.5, blue: 0.5, alpha: 1)
        setupViewport(size: view.drawableSize)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "参数缓冲区示例"
        setupData(descriptor: pipelineDescriptor)
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("创建渲染管线失败，\(error)")
        }
        
        commandQueue = device.makeCommandQueue()
    }
    
    let vertexData: [AAPLVertex] = [
        //      Vertex     |  Texture    | Vertex
        //     Positions   | Coordinates | Colors
        .init([+0.75, -0.75], [1, 0], [0, 1, 0, 1]),
        .init([-0.75, -0.75], [0, 0], [1, 1, 1, 1]),
        .init([-0.75, +0.75], [0, 1], [0, 0, 1, 1]),
        .init([+0.75, -0.75], [1, 0], [0, 1, 0, 1]),
        .init([-0.75, +0.75], [0, 1], [0, 0, 1, 1]),
        .init([+0.75, +0.75], [1, 1], [1, 1, 1, 1]),
    ]
    
    func setupData(descriptor: MTLRenderPipelineDescriptor) {
        // 创建顶点缓冲区
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: MemoryLayout<AAPLVertex>.size * vertexData.count, options: .storageModeShared)!
        vertexBuffer.label = "顶点"
        
        // 创建纹理
        let textureLoader = MTKTextureLoader(device: device)
        do {
            texture = try textureLoader.newTexture(name: "Text", scaleFactor: 1, bundle: nil, options: nil)
        } catch {
            fatalError("纹理加载错误，\(error)")
        }
        texture.label = "文字"
        
        // 创建采样器
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.supportArgumentBuffers = true
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)!
        
        var bufferElements = 256
        let bufferLength = MemoryLayout<CFloat>.size * bufferElements
        indirectBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared)!
        
        let patterns = UnsafeMutableRawBufferPointer(start: indirectBuffer.contents(), count: bufferLength).bindMemory(to: CFloat.self)
        // 或使用下面的方式构建
        // UnsafeMutableRawBufferPointer(start: indirectBuffer.contents().bindMemory(to: CFloat.self, capacity: MemoryLayout<CFloat>.size), count: bufferElements)
        for i in 0 ..< patterns.count {
            patterns[i] = (i % 24) < 3 ? 1 : 0
        }
        indirectBuffer.label = "间接缓冲区"
        
        // 创建渲染管线和参数缓冲区
        let defaultLibrary = device.makeDefaultLibrary()!
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")!
        let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader")!
        let argumentEncoder = fragmentFunction.makeArgumentEncoder(bufferIndex: Int(AAPLFragmentBufferIndexArguments.rawValue))
        
        fragmentShaderArgumentBuffer = device.makeBuffer(length: argumentEncoder.encodedLength, options: [])!
        fragmentShaderArgumentBuffer.label = "参数缓冲区"
        argumentEncoder.setArgumentBuffer(fragmentShaderArgumentBuffer, offset: 0)
        argumentEncoder.setTexture(texture, index: Int(AAPLArgumentBufferIDExampleTexture.rawValue))
        argumentEncoder.setSamplerState(sampler, index: Int(AAPLArgumentBufferIDExampleSampler.rawValue))
        argumentEncoder.setBuffer(indirectBuffer, offset: 0, index: Int(AAPLArgumentBufferIDExampleBuffer.rawValue))
        
        let numElements = argumentEncoder.constantData(at: Int(AAPLArgumentBufferIDExampleConstant.rawValue))
        numElements.copyMemory(from: &bufferElements, byteCount: MemoryLayout.size(ofValue: bufferElements))
        
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setupViewport(size: size)
    }
    
    func setupViewport(size: CGSize) {
        viewport = .init()
        if size.width < size.height {
            viewport.originX = 0
            viewport.originY = Double(abs(size.height - size.width) / 2)
            viewport.width = Double(size.width)
            viewport.height = viewport.width
            viewport.zfar = 1
            viewport.znear = -1
        } else {
            viewport.originY = 0
            viewport.originX = Double(abs(size.height - size.width) / 2)
            viewport.width = Double(size.height)
            viewport.height = viewport.width
            viewport.zfar = 1
            viewport.znear = -1
        }
    }

    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "渲染命令"
        
        if let passDescriptor = view.currentRenderPassDescriptor {
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
            encoder.label = "渲染命令编码器"
            
            encoder.setViewport(viewport)
            encoder.useResource(texture, usage: .sample)
            encoder.useResource(indirectBuffer, usage: .read)
            
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: Int(AAPLVertexBufferIndexVertices.rawValue))
            encoder.setFragmentBuffer(fragmentShaderArgumentBuffer, offset: 0, index: Int(AAPLFragmentBufferIndexArguments.rawValue))
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexData.count)
            encoder.endEncoding()
            commandBuffer.present(view.currentDrawable!)
            commandBuffer.commit()
        }
    }
}

extension AAPLVertex {
    init(_ position: vector_float2, _ texCoord: vector_float2, _ color: vector_float4) {
        self.init()
        self.position = position
        self.texCoord = texCoord
        self.color = color
    }
}
