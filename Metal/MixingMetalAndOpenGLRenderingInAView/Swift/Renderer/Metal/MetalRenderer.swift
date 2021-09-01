//
// Created by Bq Lin on 2021/8/31.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import MetalKit

class MetalRenderer: NSObject {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let maxBufferInFlight = 3
    let inFlightSemaphore: DispatchSemaphore
    
    var renderPipeline: MTLRenderPipelineState!
    var renderPassDescriptor: MTLRenderPassDescriptor!
    var baseMap: MTLTexture!
    var labelMap: MTLTexture!
    var quadVertexBuffer: MTLBuffer!
    var dynamicUniformBuffers: [MTLBuffer] = []
    var currentBufferIndex: Int = 0
    var projectionMatrix: matrix_float4x4 = .init()
    var rotation: Float = 0
    var rotationIncrement: Float = 0.01
    
    init(device: MTLDevice, colorPixelFormat: MTLPixelFormat) {
        self.device = device
        commandQueue = device.makeCommandQueue()!
        inFlightSemaphore = .init(value: maxBufferInFlight)
        
        super.init()
        
        let defaultLibrary = device.makeDefaultLibrary()!
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")!
        let fragmnetFuction = defaultLibrary.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "渲染管线"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmnetFuction
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("创建渲染管线失败")
        }
        
        dynamicUniformBuffers = []
        for i in 0 ..< maxBufferInFlight {
            let buffer = device.makeBuffer(length: MemoryLayout<AAPLUniforms>.size, options: .storageModeShared)!
            buffer.label = "UniformBuffer \(i)"
            dynamicUniformBuffers.append(buffer)
        }
        
        quadVertexBuffer = device.makeBuffer(bytes: quadVertices, length: MemoryLayout<AAPLVertex>.size * quadVertices.count, options: [])
        
        renderPassDescriptor = MTLRenderPassDescriptor()
        let colorAttachment = renderPassDescriptor.colorAttachments[0]!
        colorAttachment.clearColor = .init(red: 0, green: 1, blue: 0, alpha: 1)
        colorAttachment.loadAction = .clear
        colorAttachment.storeAction = .store
    }
    
    let quadVertices: [AAPLVertex] = [
        .init(position: [-0.75, -0.75, 0, 1], texCoord: [0, 1]),
        .init(position: [-0.75, +0.75, 0, 1], texCoord: [0, 0]),
        .init(position: [+0.75, -0.75, 0, 1], texCoord: [1, 1]),
        
        .init(position: [+0.75, -0.75, 0, 1], texCoord: [1, 1]),
        .init(position: [-0.75, +0.75, 0, 1], texCoord: [0, 0]),
        .init(position: [+0.75, +0.75, 0, 1], texCoord: [1, 0]),
    ]
    
    func useInteropTextureAsBaseMap(_ texture: MTLTexture) {
        baseMap = texture
        let textureLoader = MTKTextureLoader(device: device)
        let url = Bundle.main.url(forResource: "Assets/QuadWithMetalToView", withExtension: "png")!
        do {
            labelMap = try textureLoader.newTexture(URL: url, options: nil)
        } catch {
            fatalError("加载纹理失败，\(error)")
        }
        rotationIncrement = 0.01
    }
    
    func useTextureFromFileAsBaseMap() {
        let textureLoader = MTKTextureLoader(device: device)
        do {
            var url = Bundle.main.url(forResource: "Assets/Colors", withExtension: "png")!
            baseMap = try textureLoader.newTexture(URL: url, options: nil)
            
            url = Bundle.main.url(forResource: "Assets/QuadWithMetalToPixelBuffer", withExtension: "png")!
            labelMap = try textureLoader.newTexture(URL: url, options: nil)
        } catch {
            fatalError("加载纹理失败，\(error)")
        }
        
        rotationIncrement = -0.01
    }
    
    func resize(_ size: CGSize) {
        let aspect = Float(size.width / size.height)
        projectionMatrix = matrix_perspective_right_hand(1, aspect, 0.1, 5)
    }
    
    func updateState() {
        if rotation > 30 * .pi / 180 {
            rotationIncrement = -0.01
        } else if rotation < -30 * .pi / 180 {
            rotationIncrement = 0.01
        }
        rotation += rotationIncrement
        
        let t = matrix4x4_translation(0, 0, -2)
        let r = matrix4x4_rotation(rotation, 0, 1, 0)
        let modelView = matrix_multiply(t, r)
        let mvp = matrix_multiply(projectionMatrix, modelView)
        var unifom = dynamicUniformBuffers[currentBufferIndex].contents().load(as: AAPLUniforms.self)
        unifom.mvp = mvp
        dynamicUniformBuffers[currentBufferIndex].contents().copyMemory(from: &unifom, byteCount: MemoryLayout.size(ofValue: unifom))
    }
    
    func drawToTexture(_ texture: MTLTexture) -> MTLCommandBuffer {
        inFlightSemaphore.wait()
        updateState()
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.label = "渲染命令"
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            self?.inFlightSemaphore.signal()
        }
        renderPassDescriptor.colorAttachments[0].texture = texture
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.label = "渲染命令编码器"
        
        renderEncoder.pushDebugGroup("绘制mesh")
        
        renderEncoder.setCullMode(.back)
        renderEncoder.setRenderPipelineState(renderPipeline)
        renderEncoder.setVertexBuffer(dynamicUniformBuffers[currentBufferIndex], offset: 0, index: Int(AAPLBufferIndexUniforms.rawValue))
        renderEncoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: Int(AAPLBufferIndexVertices.rawValue))
        renderEncoder.setFragmentBuffer(dynamicUniformBuffers[currentBufferIndex], offset: 0, index: Int(AAPLBufferIndexUniforms.rawValue))
        renderEncoder.setFragmentTexture(baseMap, index: Int(AAPLTextureIndexBaseMap.rawValue))
        renderEncoder.setFragmentTexture(labelMap, index: Int(AAPLTextureIndexLabelMap.rawValue))
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: quadVertices.count)
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
        
        return commandBuffer
    }
    
    func draw(to view: MTKView) {
        guard let drawableTextexture = view.currentDrawable?.texture else { return }
        let commandBuffer = drawToTexture(drawableTextexture)
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
    
    func draw(to interopTexture: MTLTexture) {
        let commandBuffer = drawToTexture(interopTexture)
        commandBuffer.commit()
    }
}
