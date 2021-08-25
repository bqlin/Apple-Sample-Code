//
// Created by Bq Lin on 2021/8/24.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import MetalKit

class Renderer: NSObject {
    let device: MTLDevice
    var commandQueue: MTLCommandQueue!
    var vertexBuffer: MTLBuffer!
    var renderPipeline: MTLRenderPipelineState!
    var textures = [MTLTexture]()
    var dataBuffers = [MTLBuffer]()
    var fragmentShaderArgumentBuffer: MTLBuffer!
    var heap: MTLHeap!
    var viewport = MTLViewport()

    init(view: MTKView) {
        device = view.device!

        super.init()
        view.delegate = self
        view.clearColor = .init(red: 0, green: 0.5, blue: 0.5, alpha: 1)
        setupViewport(size: view.drawableSize)

        commandQueue = device.makeCommandQueue()!

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "使用堆管理参数缓冲区"
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        setupData(descriptor: pipelineDescriptor)
        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("创建渲染管线错误，\(error)")
        }
    }

    let vertexData: [AAPLVertex] = [
        //      Vertex     |  Texture
        //     Positions   | Coordinates
        .init([+0.75, -0.75], [1, 0]),
        .init([-0.75, -0.75], [0, 0]),
        .init([-0.75, +0.75], [0, 1]),
        .init([+0.75, -0.75], [1, 0]),
        .init([-0.75, +0.75], [0, 1]),
        .init([+0.75, +0.75], [1, 1]),
    ]

    func setupData(descriptor: MTLRenderPipelineDescriptor) {
        // 顶点缓冲区
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: MemoryLayout<AAPLVertex>.size * vertexData.count, options: .storageModeShared)
        vertexBuffer.label = "顶点"

        loadResouces()
        createHeap()
        moveResourcesToHeap()

        let defaultLibrary = device.makeDefaultLibrary()!
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")!
        let fragmentFuction = defaultLibrary.makeFunction(name: "fragmentShader")!

        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFuction

        let argumentEncoder = fragmentFuction.makeArgumentEncoder(bufferIndex: Int(AAPLFragmentBufferIndexArguments.rawValue))
        fragmentShaderArgumentBuffer = device.makeBuffer(length: argumentEncoder.encodedLength, options: [])!
        fragmentShaderArgumentBuffer.label = "片元着色器参数缓冲区"
        argumentEncoder.setArgumentBuffer(fragmentShaderArgumentBuffer, offset: 0)
        for (i, texture) in textures.enumerated() {
            argumentEncoder.setTexture(texture, index: i + Int(AAPLArgumentBufferIDExampleTextures.rawValue))
        }
        for (i, dataBuffer) in dataBuffers.enumerated() {
            argumentEncoder.setBuffer(dataBuffer, offset: 0, index: i + Int(AAPLArgumentBufferIDExampleBuffers.rawValue))
            let elementCountAddress = argumentEncoder.constantData(at: i + Int(AAPLArgumentBufferIDExampleConstants.rawValue))
            var count: Int = dataBuffer.length / 4
            elementCountAddress.copyMemory(from: &count, byteCount: MemoryLayout.size(ofValue: count))
        }
    }

    // 改变存储方式
    func moveResourcesToHeap() {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.label = "堆拷贝命令缓冲区"

        let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
        blitEncoder.label = "堆转换blit编码器"

        // 转换纹理内存到堆
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

            // 替换纹理
            textures[i] = heapTexture
        }

        // 转换data buffer内存到堆
        for i in 0 ..< dataBuffers.count {
            let dataBuffer = dataBuffers[i]
            let heapBuffer = heap.makeBuffer(length: dataBuffer.length, options: .storageModePrivate)!
            heapBuffer.label = dataBuffer.label
            blitEncoder.copy(from: dataBuffer, sourceOffset: 0, to: heapBuffer, destinationOffset: 0, size: heapBuffer.length)

            // 替换缓冲区
            dataBuffers[i] = heapBuffer
        }

        blitEncoder.endEncoding()
        commandBuffer.commit()
    }

    // 在资源加载后创建堆
    func createHeap() {
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.storageMode = .private
        heapDescriptor.size = 0

        // 计算堆大小
        for texture in textures {
            let textureDescriptor = Renderer.makeDescriptor(texture: texture, storageMode: heapDescriptor.storageMode)
            var sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: textureDescriptor)
            sizeAndAlign.size += (sizeAndAlign.size & (sizeAndAlign.align - 1)) + sizeAndAlign.align
            heapDescriptor.size += sizeAndAlign.size
        }

        for dataBuffer in dataBuffers {
            var sizeAndAlign = device.heapBufferSizeAndAlign(length: dataBuffer.length, options: .storageModePrivate)
            sizeAndAlign.size += (sizeAndAlign.size & (sizeAndAlign.align - 1)) + sizeAndAlign.align
            heapDescriptor.size += sizeAndAlign.size
        }

        heap = device.makeHeap(descriptor: heapDescriptor)!
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

    typealias DataType = CFloat
    func loadResouces() {
        // 加载纹理资源
        let textureLoader = MTKTextureLoader(device: device)
        do {
            textures = []
            for i in 0 ..< Int(AAPLNumTextureArguments.rawValue) {
                let name = "Texture\(i)"
                let texture = try textureLoader.newTexture(name: name, scaleFactor: 1, bundle: nil, options: nil)
                texture.label = name
                textures.append(texture)
            }
        } catch {
            fatalError("资源加载失败，\(error)")
        }

        // 构建数量值缓冲区
        let bufferArgumentCount = Int(AAPLNumBufferArguments.rawValue)
        // var elementCounts = [Int]()
        dataBuffers = []
        for i in 0 ..< bufferArgumentCount {
            let elementCount = Int.random(in: 0 ..< 384) + 128
            // elementCounts.append(elementCount)

            let bufferSize = elementCount * MemoryLayout<DataType>.size
            let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)!
            buffer.label = "DataBuffer\(i)"

            let elements = UnsafeMutableRawBufferPointer(start: buffer.contents(), count: bufferSize).bindMemory(to: DataType.self)
            for k in 0 ..< elements.count {
                let point = DataType(k) * 2 * .pi / DataType(elementCount)
                elements[k] = sin(point * DataType(i)) * 0.5 + 0.5
            }
            dataBuffers.append(buffer)
        }
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
        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.label = "帧命令"

        if let passDescriptor = view.currentRenderPassDescriptor {
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
            encoder.label = "帧渲染"
            encoder.setViewport(viewport)

            if let heap = heap {
                encoder.useHeap(heap)
            } else {
                textures.forEach { texture in
                    encoder.useResource(texture, usage: .sample)
                }
                dataBuffers.forEach { dataBuffer in
                    encoder.useResource(dataBuffer, usage: .read)
                }
            }

            encoder.setRenderPipelineState(renderPipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: Int(AAPLVertexBufferIndexVertices.rawValue))
            encoder.setFragmentBuffer(fragmentShaderArgumentBuffer, offset: 0, index: Int(AAPLFragmentBufferIndexArguments.rawValue))

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexData.count)
            encoder.endEncoding()

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
