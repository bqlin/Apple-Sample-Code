//
// Created by Bq Lin on 2021/8/26.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import MetalKit

class Renderer: NSObject {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var renderPipeline: MTLRenderPipelineState!
    var computePipeline: MTLComputePipelineState!
    
    let maxBufferInFlight = 3
    let inFlightSemaphore: DispatchSemaphore
    var quadScale: vector_float2!
    
    init(view: MTKView) {
        device = view.device!
        commandQueue = device.makeCommandQueue()!
        inFlightSemaphore = DispatchSemaphore(value: maxBufferInFlight)
        
        super.init()
        view.delegate = self
        view.clearColor = .init(red: 0, green: 0.5, blue: 0.5, alpha: 1)
        setupQuadScale(size: view.drawableSize)
        
        let defaultLibrary = device.makeDefaultLibrary()!
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")!
        let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader")!
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "参数缓冲区管线"
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("创建渲染管线失败，\(error)")
        }
        
        // 创建计算管线
        let computeFunction = defaultLibrary.makeFunction(name: "updateInstances")!
        do {
            computePipeline = try device.makeComputePipelineState(function: computeFunction)
        } catch {
            fatalError("创建计算管线失败，\(error)")
        }
        
        setupData()
        makeAugumentBuffers(computeFunction: computeFunction)
    }
    
    var vertexData: [AAPLVertex]!
    var vertexBuffer: MTLBuffer!
    var frameStateBuffers = [MTLBuffer]()
    var textures = [MTLTexture]()
    var sourceTextureBuffer: MTLBuffer!
    var instanceParamterBuffer: MTLBuffer!
    
    let threadgroupSize: MTLSize = .init(width: 16, height: 1, depth: 1)
    var threadgroupCount: MTLSize = .init(width: 1, height: 1, depth: 1)
    
    func setupData() {
        threadgroupCount.width = (2 * Int(AAPLNumInstances) - 1) / threadgroupSize.width
        threadgroupCount.width = max(threadgroupCount.width, 1)
        
        // 顶点缓冲区
        let quadSize = Float(AAPLQuadSize)
        vertexData = [
            //       Vertex          |  Texture  |
            //      Positions        |Coordinates|
            .init([quadSize, 0], [1, 0]),
            .init([0, 0], [0, 0]),
            .init([0, quadSize], [0, 1]),
            .init([quadSize, 0], [1, 0]),
            .init([0, quadSize], [0, 1]),
            .init([quadSize, quadSize], [1, 1]),
        ]
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: MemoryLayout<AAPLVertex>.size * vertexData.count, options: .storageModeShared)
        vertexBuffer.label = "顶点数据"
        
        loadResources()
        createHeap()
        moveResourceToHeap()
        
        frameStateBuffers = []
        for i in 0 ..< maxBufferInFlight {
            let buffer = device.makeBuffer(length: MemoryLayout<AAPLFrameState>.size, options: .storageModeShared)!
            buffer.label = "frame data buffer \(i)"
            frameStateBuffers.append(buffer)
        }
    }
    
    func makeAugumentBuffers(computeFunction: MTLFunction) {
        // 编码参数缓冲区传入计算函数
        let argumentEncoder = computeFunction.makeArgumentEncoder(bufferIndex: Int(AAPLComputeBufferIndexSourceTextures.rawValue))
        let textureArgumentArrayLength = argumentEncoder.encodedLength * textures.count
        sourceTextureBuffer = device.makeBuffer(length: textureArgumentArrayLength, options: [])
        sourceTextureBuffer.label = "纹理列表"
        for i in 0 ..< textures.count {
            let argumentBufferOffset = i * argumentEncoder.encodedLength
            // Set the offset to which the renderer will write the texture argument.
            argumentEncoder.setArgumentBuffer(sourceTextureBuffer, offset: argumentBufferOffset)
            argumentEncoder.setTexture(textures[i], index: Int(AAPLArgumentBufferIDTexture.rawValue))
        }
        
        // 编码计算函数的输出到渲染管线
        let instanceParameterEncoder = computeFunction.makeArgumentEncoder(bufferIndex: Int(AAPLComputeBufferIndexInstanceParams.rawValue))
        let instanceParameterLength = instanceParameterEncoder.encodedLength * Int(AAPLNumInstances)
        instanceParamterBuffer = device.makeBuffer(length: instanceParameterLength, options: [])!
        instanceParamterBuffer.label = "实例参数数组"
    }
    
    func loadResources() {
        // 加载纹理资源
        let textureLoader = MTKTextureLoader(device: device)
        do {
            textures = []
            for i in 0 ..< Int(AAPLNumTextures) {
                let name = "Texture\(i)"
                let texture = try textureLoader.newTexture(name: name, scaleFactor: 1, bundle: nil, options: nil)
                texture.label = name
                textures.append(texture)
            }
        } catch {
            fatalError("资源加载失败，\(error)")
        }
    }
    
    var heap: MTLHeap!
    func createHeap() {
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.storageMode = .private
        heapDescriptor.size = 0
        var texturesSize = 0
        for texture in textures {
            let descriptor = Renderer.makeDescriptor(texture: texture, storageMode: heapDescriptor.storageMode)
            var sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: descriptor)
            sizeAndAlign.size += (sizeAndAlign.size & (sizeAndAlign.align - 1)) + sizeAndAlign.align
            texturesSize += sizeAndAlign.size
        }
        heapDescriptor.size = texturesSize * 2
        heap = device.makeHeap(descriptor: heapDescriptor)
        heap.label = "纹理堆"
    }
    
    func moveResourceToHeap() {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.label = "堆上传命令缓冲区"
        
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
        blitEncoder.label = "堆转存编码器"
        
        for i in 0 ..< textures.count {
            let texture = textures[i]
            let descriptor = Renderer.makeDescriptor(texture: texture, storageMode: heap.storageMode)
            let heapTexture = heap.makeTexture(descriptor: descriptor)!
            heapTexture.label = texture.label
            
            blitEncoder.pushDebugGroup("\(heapTexture.label!) Blits")
            var region = MTLRegionMake2D(0, 0, texture.width, texture.height)
            for level in 0 ..< texture.mipmapLevelCount {
                blitEncoder.pushDebugGroup("Level \(level) Blit")
                
                for slice in 0 ..< texture.arrayLength {
                    blitEncoder.copy(from: texture, sourceSlice: slice, sourceLevel: level, sourceOrigin: region.origin, sourceSize: region.size, to: heapTexture, destinationSlice: slice, destinationLevel: level, destinationOrigin: region.origin)
                }
                
                region.size.width /= 2
                region.size.height /= 2
                region.size.width = max(region.size.width, 1)
                region.size.height = max(region.size.height, 1)
                blitEncoder.popDebugGroup()
            }
            blitEncoder.popDebugGroup()
            textures[i] = heapTexture
        }
        
        blitEncoder.endEncoding()
        commandBuffer.commit()
    }
    
    var inFlightIndex: Int = 0
    var blendTheta: Float = 0
    var textureIndexOffset: Int = 0
    func updateState() {
        inFlightIndex = (inFlightIndex + 1) % maxBufferInFlight
        
        let frameStatePtr = frameStateBuffers[inFlightIndex].contents().bindMemory(to: AAPLFrameState.self, capacity: 1)
        var frameState = frameStatePtr.pointee
        // var frameState = frameStatePtr.load(as: AAPLFrameState.self)
        blendTheta += 0.025
        frameState.quadScale = quadScale
        
        let gridWidth = Float(AAPLGridWidth)
        let gridHeight = Float((AAPLNumInstances + 1) / AAPLGridWidth)
        let halfGridDimensions: vector_float2 = [0.5 * gridWidth, 0.5 * gridHeight]
        frameState.offset.x = Float(AAPLQuadSpacing) * quadScale.x * (halfGridDimensions.x - 1)
        frameState.offset.y = Float(AAPLQuadSpacing) * quadScale.y * -halfGridDimensions.y
        frameState.slideFactor = (cosf(blendTheta + .pi) + 1) / 2
        frameState.textureIndexOffset = uint(textureIndexOffset)
        // frameStatePtr.copyMemory(from: &frameState, byteCount: MemoryLayout.size(ofValue: frameState))
        frameStatePtr.pointee = frameState
        
        if blendTheta >= .pi {
            blendTheta = 0
            textureIndexOffset += 1
        }
    }
    
    static func makeDescriptor(texture: MTLTexture, storageMode: MTLStorageMode) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = texture.textureType
        descriptor.pixelFormat = texture.pixelFormat
        descriptor.width = texture.width
        descriptor.height = texture.height
        descriptor.depth = texture.depth
        descriptor.mipmapLevelCount = texture.mipmapLevelCount
        descriptor.arrayLength = texture.arrayLength
        descriptor.sampleCount = texture.sampleCount
        descriptor.storageMode = storageMode
        return descriptor
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setupQuadScale(size: size)
    }
    
    func setupQuadScale(size: CGSize) {
        quadScale = size.width < size.height ? [1, Float(size.width / size.height)] : [Float(size.height / size.width), 1]
    }
    
    func draw(in view: MTKView) {
        inFlightSemaphore.wait()
        updateState()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("创建命令缓冲区失败")
        }
        commandBuffer.label = "每帧命令"
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            guard let self = self else { return }
            self.inFlightSemaphore.signal()
        }
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.label = "每帧计算命令"
        computeEncoder.setComputePipelineState(computePipeline)
        computeEncoder.setBuffer(sourceTextureBuffer, offset: 0, index: Int(AAPLComputeBufferIndexSourceTextures.rawValue))
        computeEncoder.setBuffer(frameStateBuffers[inFlightIndex], offset: 0, index: Int(AAPLComputeBufferIndexFrameState.rawValue))
        computeEncoder.setBuffer(instanceParamterBuffer, offset: 0, index: Int(AAPLComputeBufferIndexInstanceParams.rawValue))
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        
        if let passDesscriptor = view.currentRenderPassDescriptor {
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesscriptor)!
            renderEncoder.label = "每帧渲染"
            renderEncoder.useHeap(heap)
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: Int(AAPLVertexBufferIndexVertices.rawValue))
            renderEncoder.setVertexBuffer(frameStateBuffers[inFlightIndex], offset: 0, index: Int(AAPLVertexBufferIndexFrameState.rawValue))
            renderEncoder.setVertexBuffer(instanceParamterBuffer, offset: 0, index: Int(AAPLVertexBufferIndexInstanceParams.rawValue))
            renderEncoder.setFragmentBuffer(instanceParamterBuffer, offset: 0, index: Int(AAPLFragmentBufferIndexInstanceParams.rawValue))
            renderEncoder.setFragmentBuffer(frameStateBuffers[inFlightIndex], offset: 0, index: Int(AAPLFragmentBufferIndexFrameState.rawValue))
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexData.count, instanceCount: Int(AAPLNumInstances))
            renderEncoder.endEncoding()
            commandBuffer.present(view.currentDrawable!)
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

extension AAPLVertex {
    init(_ position: vector_float2, _ texCoord: vector_float2) {
        self.init()
        self.position = position
        self.texCoord = texCoord
    }
}
