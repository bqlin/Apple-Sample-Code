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

    let maxFramesInFlight = 3
    let inFlightSemaphore: DispatchSemaphore
    var aspectScale: vector_float2!

    init(view: MTKView) {
        device = view.device!
        commandQueue = device.makeCommandQueue()!
        inFlightSemaphore = .init(value: maxFramesInFlight)

        super.init()
        view.delegate = self
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
        view.clearColor = .init(red: 0, green: 0, blue: 0.5, alpha: 1)
        setupQuadScale(size: view.drawableSize)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "渲染管线"
        pipelineDescriptor.sampleCount = view.sampleCount
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipelineDescriptor.supportIndirectCommandBuffers = true
        setupData(descriptor: pipelineDescriptor)

        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("创建渲染管线失败")
        }
    }

    var vertexBuffers = [MTLBuffer]()
    var objectParameterBuffer: MTLBuffer!
    var frameStateBuffers = [MTLBuffer]()
    var indirectFrameStateBuffer: MTLBuffer!
    var indirectCommandBuffer: MTLIndirectCommandBuffer!
    func setupData(descriptor: MTLRenderPipelineDescriptor) {
        let defaultLibrary = device.makeDefaultLibrary()!
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")!
        let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader")!
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction

        vertexBuffers = []
        for i in 0 ..< Int(AAPLNumObjects) {
            let numTeeth = i < 8 ? i + 3 : i * 3
            let buffer = makeGear(numTeeth: numTeeth)
            buffer.label = "Object \(i) Buffer"
            vertexBuffers.append(buffer)
        }

        let objectParameterArraySize = vertexBuffers.count * MemoryLayout<AAPLObjectPerameters>.size
        objectParameterBuffer = device.makeBuffer(length: objectParameterArraySize, options: [])
        objectParameterBuffer.label = "对象参数数组"
        let params = UnsafeMutableRawBufferPointer(start: objectParameterBuffer.contents(), count: objectParameterArraySize).bindMemory(to: AAPLObjectPerameters.self)
        
        let gridWidth = Int(AAPLGridWidth)
        let gridHeight = Int((AAPLNumObjects + AAPLGridWidth - 1) / AAPLGridWidth)
        let gridDimensions: vector_float2 = [Float(gridWidth), Float(gridHeight)]
        let offset: vector_float2 = Float(AAPLObjecDistance) / 2 * (gridDimensions - 1)
        for i in 0 ..< vertexBuffers.count {
            let gridPosition: vector_float2 = [Float(i % gridWidth), Float(i / gridWidth)]
            let position = -offset + gridPosition * Float(AAPLObjecDistance)
            params[i].position = position
        }

        frameStateBuffers = []
        for i in 0 ..< maxFramesInFlight {
            let buffer = device.makeBuffer(length: MemoryLayout<AAPLFrameState>.size, options: .storageModeShared)!
            buffer.label = "帧状态 \(i)"
            frameStateBuffers.append(buffer)
        }

        indirectFrameStateBuffer = device.makeBuffer(length: MemoryLayout<AAPLFrameState>.size, options: .storageModePrivate)!
        indirectFrameStateBuffer.label = "间接帧状态缓冲区"
        
        let icbDescriptor = MTLIndirectCommandBufferDescriptor()
        icbDescriptor.commandTypes = .draw
        icbDescriptor.inheritBuffers = false
        icbDescriptor.maxVertexBufferBindCount = 3
        icbDescriptor.maxFragmentBufferBindCount = 0
        icbDescriptor.inheritPipelineState = true
        indirectCommandBuffer = device.makeIndirectCommandBuffer(descriptor: icbDescriptor, maxCommandCount: vertexBuffers.count, options: [])!
        indirectCommandBuffer.label = "Scene ICB"

        for i in 0 ..< vertexBuffers.count {
            let icbCommand = indirectCommandBuffer.indirectRenderCommandAt(i)
            icbCommand.setVertexBuffer(vertexBuffers[i], offset: 0, at: Int(AAPLVertexBufferIndexVertices.rawValue))
            icbCommand.setVertexBuffer(indirectFrameStateBuffer, offset: 0, at: Int(AAPLVertexBufferIndexFrameState.rawValue))
            icbCommand.setVertexBuffer(objectParameterBuffer, offset: 0, at: Int(AAPLVertexBufferIndexObjectParams.rawValue))
            let vertextCount = vertexBuffers[i].length / MemoryLayout<AAPLVertex>.size
            icbCommand.drawPrimitives(.triangle, vertexStart: 0, vertexCount: vertextCount, instanceCount: 1, baseInstance: i)
        }
    }

    func makeGear(numTeeth: Int) -> MTLBuffer {
        assert(numTeeth >= 3, "至少需要3个齿")

        let innerRatio: Float = 0.8
        let toothWidth: Float = 0.25
        let toothSlop: Float = 0.2

        let numVertices = numTeeth * 12
        let bufferSize = MemoryLayout<AAPLVertex>.size * numVertices
        let buffer = device.makeBuffer(length: bufferSize, options: [])!
        buffer.label = "\(numTeeth)齿齿轮顶点"
        
        let meshVertices = UnsafeMutableRawBufferPointer(start: buffer.contents(), count: bufferSize).bindMemory(to: AAPLVertex.self)
        let angle: Float = 2 * .pi / Float(numTeeth)
        let origin: packed_float2 = [0, 0]
        var vtx = 0

        for i in 0 ..< numTeeth {
            // 计算齿和槽的角度
            let tooth = Float(i)
            let toothStartAngle = tooth * angle
            let toothTip1Angle = (tooth + toothSlop) * angle
            let toothTip2Angle = (tooth + toothSlop + toothWidth) * angle
            let toothEndAngle = (tooth + 2 * toothSlop + toothWidth) * angle
            let nextToothAngle = (tooth + 1) * angle

            // 计算齿需要的顶点位置
            let groove1: packed_float2 = [sin(toothStartAngle) * innerRatio, cos(toothStartAngle) * innerRatio]
            let tip1: packed_float2 = [sin(toothTip1Angle), cos(toothTip1Angle)]
            let tip2: packed_float2 = [sin(toothTip2Angle), cos(toothTip2Angle)]
            let groove2: packed_float2 = [sin(toothEndAngle) * innerRatio, cos(toothEndAngle) * innerRatio]
            let nextGroove: packed_float2 = [sin(nextToothAngle) * innerRatio, cos(nextToothAngle) * innerRatio]

            // 齿的右上角三角形
            meshVertices[vtx].position = groove1
            meshVertices[vtx].texcoord = (groove1 + 1) / 2
            vtx += 1
            meshVertices[vtx].position = tip1
            meshVertices[vtx].texcoord = (tip1 + 1) / 2
            vtx += 1
            meshVertices[vtx].position = tip2
            meshVertices[vtx].texcoord = (tip2 + 1) / 2
            vtx += 1
            
            // 齿左下角三角形
            meshVertices[vtx].position = groove1
            meshVertices[vtx].texcoord = (groove1 + 1) / 2
            vtx += 1
            meshVertices[vtx].position = tip2
            meshVertices[vtx].texcoord = (tip2 + 1) / 2
            vtx += 1
            meshVertices[vtx].position = groove2
            meshVertices[vtx].texcoord = (groove2 + 1) / 2
            vtx += 1

            // 从齿底到齿轮中心的圆的切面
            meshVertices[vtx].position = origin
            meshVertices[vtx].texcoord = (origin + 1) / 2
            vtx += 1
            meshVertices[vtx].position = groove1
            meshVertices[vtx].texcoord = (groove1 + 1) / 2
            vtx += 1
            meshVertices[vtx].position = groove2
            meshVertices[vtx].texcoord = (groove2 + 1) / 2
            vtx += 1

            // 从槽到齿轮中心的圆的切面
            meshVertices[vtx].position = origin
            meshVertices[vtx].texcoord = (origin + 1) / 2
            vtx += 1
            meshVertices[vtx].position = groove2
            meshVertices[vtx].texcoord = (groove2 + 1) / 2
            vtx += 1
            meshVertices[vtx].position = nextGroove
            meshVertices[vtx].texcoord = (nextGroove + 1) / 2
            vtx += 1
        }

        return buffer
    }

    var inFloghtIndex = 0
    var frameNumber = 0
    func updateState() {
        frameNumber += 1
        inFloghtIndex = frameNumber % maxFramesInFlight
        let frameStatePtr = frameStateBuffers[inFloghtIndex].contents()
        var frameState = frameStatePtr.load(as: AAPLFrameState.self)
        frameState.aspectScale = aspectScale
        frameStatePtr.copyMemory(from: &frameState, byteCount: MemoryLayout.size(ofValue: frameState))
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setupQuadScale(size: size)
    }

    func setupQuadScale(size: CGSize) {
        aspectScale = size.width < size.height ? [1, Float(size.width / size.height)] : [Float(size.height / size.width), 1]
    }

    func draw(in view: MTKView) {
        inFlightSemaphore.wait()
        updateState()
        guard let commanBuffer = commandQueue.makeCommandBuffer() else { fatalError("无法创建命令缓冲区") }
        commanBuffer.label = "帧命令缓冲区"
        commanBuffer.addCompletedHandler { [weak self] commandBuffer in
            guard let self = self else { return }
            self.inFlightSemaphore.signal()
        }

        let blitEncoder = commanBuffer.makeBlitCommandEncoder()!
        blitEncoder.copy(from: frameStateBuffers[inFloghtIndex], sourceOffset: 0, to: indirectFrameStateBuffer, destinationOffset: 0, size: indirectFrameStateBuffer.length)
        blitEncoder.endEncoding()

        if let passDescriptor = view.currentRenderPassDescriptor {
            let renderEncoder = commanBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
            renderEncoder.label = "渲染命令编码器"
            renderEncoder.setCullMode(.back)
            renderEncoder.setRenderPipelineState(renderPipeline)
            vertexBuffers.forEach { buffer in
                renderEncoder.useResource(buffer, usage: .read)
            }
            renderEncoder.useResource(objectParameterBuffer, usage: .read)
            renderEncoder.useResource(indirectFrameStateBuffer, usage: .read)
            renderEncoder.executeCommandsInBuffer(indirectCommandBuffer, range: 0 ..< vertexBuffers.count)
            renderEncoder.endEncoding()
            commanBuffer.present(view.currentDrawable!)
        }
        commanBuffer.commit()
    }
}
