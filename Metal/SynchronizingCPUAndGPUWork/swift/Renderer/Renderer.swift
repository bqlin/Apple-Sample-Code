//
//  Renderer.swift
//  CPU-GPU-Synchronization
//
//  Created by Bq Lin on 2021/5/13.
//  Copyright © 2021 Bq. All rights reserved.
//

import MetalKit

class Renderer: NSObject, MTKViewDelegate {
    
    init(mtkView: MTKView) {
        device = mtkView.device!
        viewportSize = mtkView.drawableSize.toVector_uint2
        inFlightSemaphore = DispatchSemaphore(value: maxFramesInFlight)
        super.init()
        
        guard let defaultLibrary = device.makeDefaultLibrary() else {
            fatalError("can not make default library!")
        }
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")
        let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "WavePipeline"
        pipelineDescriptor.sampleCount = mtkView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        pipelineDescriptor.vertexBuffers[Int(AAPLVertexInputIndexVertices.rawValue)].mutability = .immutable
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("\(error)")
        }
        
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("can not make command queue")
        }
        self.commandQueue = commandQueue
        
        generateTriangles()
        
        totalVertexCount = Triangle.vertices.count * triangles.count
        let triangleVertexBufferSize = totalVertexCount * MemoryLayout<AAPLVertex>.size
        for bufferIndex in 0 ..< maxFramesInFlight {
            guard let buffer = device.makeBuffer(length: triangleVertexBufferSize, options: .storageModeShared) else { break }
            buffer.label = "Vertex Buffer #\(bufferIndex)"
            vertexBuffers.append(buffer)
        }
        
        mtkView.delegate = self
    }
    
    let device: MTLDevice
    let inFlightSemaphore: DispatchSemaphore
    let maxFramesInFlight = 3
    var vertexBuffers = [MTLBuffer]()
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var viewportSize: vector_uint2
    var totalVertexCount: Int!
    var wavePosition: Float = 0
    var currentBufferIndex = -1
    
    let numTriangles = 50
    var triangles = [Triangle]()
    
    func generateTriangles() {
        let colors: [vector_float4] = [
            [1.0, 0.0, 0.0, 1.0], // Red
            [0.0, 1.0, 0.0, 1.0], // Green
            [0.0, 0.0, 1.0, 1.0], // Blue
            [1.0, 0.0, 1.0, 1.0], // Magenta
            [0.0, 1.0, 1.0, 1.0], // Cyan
            [1.0, 1.0, 0.0, 1.0], // Yellow
        ]
        
        let horizontalSpacing: Float = 16
        var triangles = [Triangle]()
        for t in 0 ..< numTriangles {
            // position：横向排列；color：循环使用上面定义的颜色
            let trianglePosition: vector_float2 = [(Float(numTriangles) / -2 + Float(t)) * horizontalSpacing, 0]
            triangles.append(Triangle(position: trianglePosition, color: colors[t % colors.count]))
        }
        self.triangles = triangles
    }
    
    func updateState() {
        let waveMagnitude: Float = 128
        let waveSpeed: Float = 0.05
        wavePosition += waveSpeed
        let vertices = Triangle.vertices
        
        var currentTriangleVertices = vertexBuffers[currentBufferIndex].contents().bindMemory(to: AAPLVertex.self, capacity: numTriangles * vertices.count)
        
        for i in 0 ..< numTriangles {
            // 得出应用波形曲线后的三角形位置
            var position = triangles[i].position
            position.y = sin(position.x / waveMagnitude + wavePosition) * waveMagnitude
            triangles[i].position = position
            
            // 给每个顶点增加用三角形位置偏移，以及同步颜色值
            for vi in 0 ..< vertices.count {
                let index = vi + (i * vertices.count)
                currentTriangleVertices[index].position = vertices[vi].position + position
                currentTriangleVertices[index].color = triangles[i].color
            }
        }
    }
    
    // MARK: MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size.toVector_uint2
    }
    
    func draw(in view: MTKView) {
        inFlightSemaphore.wait()
        
        currentBufferIndex = (currentBufferIndex + 1) % maxFramesInFlight
        updateState()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "WaveCommandBuffer"
        
        if let passDescriptor = view.currentRenderPassDescriptor {
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
                fatalError("can not make render command encoder!")
            }
            renderEncoder.label = "WaveRenderEncoder"
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffers[currentBufferIndex], offset: 0, index: Int(AAPLVertexInputIndexVertices.rawValue))
            renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout.size(ofValue: viewportSize), index: Int(AAPLVertexInputIndexViewportSize.rawValue))
            
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: totalVertexCount)
            
            renderEncoder.endEncoding()
            
            commandBuffer.present(view.currentDrawable!)
        }
        
        commandBuffer.addCompletedHandler { [weak self] buffer in
            self?.inFlightSemaphore.signal()
        }
        commandBuffer.commit()
    }
}

extension CGSize {
    var toVector_uint2: vector_uint2 {
        [UInt32(width), UInt32(height)]
    }
}
