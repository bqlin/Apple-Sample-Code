//
// Created by Bq Lin on 2021/8/27.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import MetalKit

class Renderer: NSObject {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let inFlightSemaphore: DispatchSemaphore

    let maxFramesInFlight = 3
    var aspectScale: vector_float2!
    var renderPipelineState: MTLRenderPipelineState! // 用于执行ICB的渲染管线
    var computePipelineState: MTLComputePipelineState! // 当使用GPU做背面剔除时构建间接命令缓冲区

    init(view: MTKView) {
        device = view.device!
        commandQueue = device.makeCommandQueue()!
        inFlightSemaphore = .init(value: maxFramesInFlight)

        super.init()
        view.delegate = self
        view.clearColor = .init(red: 0, green: 0, blue: 0.5, alpha: 1)
        view.depthStencilPixelFormat = .depth32Float
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.sampleCount = 1
        setupAspectScale(size: view.drawableSize)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "渲染管线"
        pipelineDescriptor.sampleCount = view.sampleCount
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipelineDescriptor.supportIndirectCommandBuffers = true // 使用ICB
        setupData(descriptor: pipelineDescriptor)

        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("无法创建渲染管线")
        }
    }

    var objectParameterBuffer: MTLBuffer!
    var vertexBuffer: MTLBuffer!
    var frameStateBuffers = [MTLBuffer]()
    var indirectCommandBuffer: MTLIndirectCommandBuffer!
    var icbArgumentBuffer: MTLBuffer!
    var gridCenter: vector_float2 = [0, 0]
    var movementSpeed: Float = 0.15
    var objectDirection: MovementDirection = .up
    func setupData(descriptor: MTLRenderPipelineDescriptor) {
        let defaultLibrary = device.makeDefaultLibrary()!
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")!
        let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader")!
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction

        let computeFunction = defaultLibrary.makeFunction(name: "cullMeshesAndEncodeCommands")!
        do {
            computePipelineState = try device.makeComputePipelineState(function: computeFunction)
        } catch {
            fatalError("无法创建计算管线")
        }

        // 构建mesh数据，稍后用于拷贝到一个Metal缓冲区中
        var meshInfo: [Int] = []
        // 创建对象再填充数组
        // vertexBuffer = makeVertexBuffer(info: &meshInfo)

        // 直接填充buffer
        // vertexBuffer = makeVertexBuffer2(info: &meshInfo)

        // 使用C语言方式创建结构体，然后填充buffer
        let tmpInfo = NSMutableArray()
        vertexBuffer = Util.makeVertexBufferAndInfo(tmpInfo, device: device)
        meshInfo = tmpInfo as! [Int]

        // 参数列表，每个齿轮一个参数
        let objectParameterArraySize = meshInfo.count * MemoryLayout<AAPLObjectPerameters>.size
        objectParameterBuffer = device.makeBuffer(length: objectParameterArraySize, options: [])!
        objectParameterBuffer.label = "对象参数数组"
        let params = UnsafeMutableRawBufferPointer(start: objectParameterBuffer.contents(), count: objectParameterArraySize).bindMemory(to: AAPLObjectPerameters.self)
        print("参数个数：\(params.count)")

        // 拷贝数据
        var vertexStartIndex = 0
        for i in 0 ..< params.count {
            var param = params[i]
            let vertexCount = meshInfo[i]
            param.numVertices = UInt32(vertexCount)
            param.startVertex = UInt32(vertexStartIndex)
            let gridPos: vector_float2 = [.init(Int32(i) % AAPLGridWidth), .init(Int32(i) / AAPLGridWidth)]
            param.position = gridPos * Float(AAPLObjecDistance)
            param.boundingRadius = Float(AAPLObjectSize / 2)
            params[i] = param

            vertexStartIndex += vertexCount
        }

        frameStateBuffers = []
        for i in 0 ..< maxFramesInFlight {
            let buffer = device.makeBuffer(length: MemoryLayout<AAPLFrameState>.size, options: .storageModeShared)!
            buffer.label = "帧状态缓冲区 \(i)"
            frameStateBuffers.append(buffer)
        }

        let icbDescriptor = MTLIndirectCommandBufferDescriptor()
        icbDescriptor.commandTypes = .draw
        icbDescriptor.inheritBuffers = false
        icbDescriptor.maxVertexBufferBindCount = 3
        icbDescriptor.maxFragmentBufferBindCount = 0
        if #available(iOS 13.0, *) {
            icbDescriptor.inheritPipelineState = true
        } else {
            // Fallback on earlier versions
        }
        indirectCommandBuffer = device.makeIndirectCommandBuffer(descriptor: icbDescriptor, maxCommandCount: meshInfo.count, options: [])!
        indirectCommandBuffer.label = "Scene ICB"

        let argumentEncoder = computeFunction.makeArgumentEncoder(bufferIndex: Int(AAPLKernelBufferIndexCommandBufferContainer.rawValue))
        icbArgumentBuffer = device.makeBuffer(length: argumentEncoder.encodedLength, options: .storageModeShared)
        print("icbArgumentBuffer length: \(icbArgumentBuffer.length)")
        icbArgumentBuffer.label = "ICB参数缓冲区"
        argumentEncoder.setArgumentBuffer(icbArgumentBuffer, offset: 0)
        argumentEncoder.setIndirectCommandBuffer(indirectCommandBuffer, index: Int(AAPLArgumentBufferIDCommandBuffer.rawValue))
    }

    let objectCount = Int(AAPLNumObjects)

    var inFlightIndex = 0
    var frameNumber = 0
    func updateState() {
        frameNumber += 1
        inFlightIndex = frameNumber % maxFramesInFlight

        let floatObjectDistance = Float(AAPLObjecDistance)
        let floatGridWidth = Float(AAPLGridWidth)
        let floatGridHeight = Float((AAPLNumObjects + AAPLGridWidth - 1) / AAPLGridWidth)
        let rightBounds = floatObjectDistance * floatGridWidth / 2
        let leftBounds = -floatObjectDistance * floatGridWidth / 2
        let upperBounds = floatObjectDistance * floatGridHeight / 2
        let lowerBounds = -floatObjectDistance * floatGridHeight / 2

        if gridCenter.x < leftBounds || gridCenter.x > rightBounds || gridCenter.y < lowerBounds || gridCenter.y > upperBounds {
            objectDirection = MovementDirection(rawValue: (objectDirection.rawValue + 2) % MovementDirection.allCases.count)!
        } else if frameNumber % 300 == 0 {
            objectDirection = MovementDirection(rawValue: .random(in: 0 ..< MovementDirection.allCases.count))!
        }

        switch objectDirection {
        case .right:
            gridCenter.x += movementSpeed
        case .up:
            gridCenter.y += movementSpeed
        case .left:
            gridCenter.x -= movementSpeed
        case .down:
            gridCenter.y -= movementSpeed
        }

        let gridDemensions: vector_float2 = [floatGridWidth, floatGridHeight]

        let frameStatePtr = frameStateBuffers[inFlightIndex].contents()
        var frameState = frameStatePtr.load(as: AAPLFrameState.self)
        frameState.aspectScale = aspectScale
        let offset: vector_float2 = floatObjectDistance / 2 * (gridDemensions - 1)
        frameState.translation = gridCenter - offset
        frameStatePtr.copyMemory(from: &frameState, byteCount: MemoryLayout.size(ofValue: frameState))
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setupAspectScale(size: size)
    }

    func draw(in view: MTKView) {
        inFlightSemaphore.wait()
        updateState()

        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.label = "帧命令缓冲区"
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            guard let self = self else { return }
            self.inFlightSemaphore.signal()
        }

        let objectCount = Int(AAPLNumObjects)
        let resetBlitEncoder = commandBuffer.makeBlitCommandEncoder()!
        resetBlitEncoder.label = "重置ICB Blit编码器"
        resetBlitEncoder.resetCommandsInBuffer(indirectCommandBuffer, range: 0 ..< objectCount)
        resetBlitEncoder.endEncoding()

        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.label = "计算对象可见性"
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setBuffer(frameStateBuffers[inFlightIndex], offset: 0, index: Int(AAPLKernelBufferIndexFrameState.rawValue))
        computeEncoder.setBuffer(objectParameterBuffer, offset: 0, index: Int(AAPLKernelBufferIndexObjectParams.rawValue))
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: Int(AAPLKernelBufferIndexVertices.rawValue))
        computeEncoder.setBuffer(icbArgumentBuffer, offset: 0, index: Int(AAPLKernelBufferIndexCommandBufferContainer.rawValue))
        computeEncoder.useResource(indirectCommandBuffer, usage: .write)
        computeEncoder.dispatchThreads(.init(width: objectCount, height: 1, depth: 1), threadsPerThreadgroup: .init(width: computePipelineState.threadExecutionWidth, height: 1, depth: 1))
        computeEncoder.endEncoding()

        let optimizeBlitEncoder = commandBuffer.makeBlitCommandEncoder()!
        optimizeBlitEncoder.label = "优化ICB转存编码器"
        optimizeBlitEncoder.optimizeIndirectCommandBuffer(indirectCommandBuffer, range: 0 ..< objectCount)
        optimizeBlitEncoder.endEncoding()

        if let passDescriptor = view.currentRenderPassDescriptor {
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
            renderEncoder.label = "渲染编码器"
            renderEncoder.setCullMode(.back)
            renderEncoder.setRenderPipelineState(renderPipelineState)
            renderEncoder.useResource(vertexBuffer, usage: .read)
            renderEncoder.useResource(objectParameterBuffer, usage: .read)
            renderEncoder.useResource(frameStateBuffers[inFlightIndex], usage: .read)
            renderEncoder.executeCommandsInBuffer(indirectCommandBuffer, range: 0 ..< objectCount)
            renderEncoder.endEncoding()

            commandBuffer.present(view.currentDrawable!)
        }
        commandBuffer.commit()
    }
}

extension Renderer {
    enum MovementDirection: Int, CaseIterable { case right, up, left, down }

    struct Mesh {
        var vertices: [AAPLVertex]
    }

    func setupAspectScale(size: CGSize) {
        aspectScale = size.width < size.height ? [1, Float(size.width / size.height)] : [Float(size.height / size.width), 1]
        // aspectScale = [Float(size.height / size.width), 1]
    }

    func makeVertexBuffer(info: inout [Int]) -> MTLBuffer {
        var tempMeshs = [Mesh]()
        for i in 0 ..< objectCount {
            // let numTeeth = Int.random(in: 0 ..< 50) + 3
            // let innerRatio: Float = 0.2 + .random(in: 0 ... 1) * 0.7
            // let toothWidth: Float = 0.1 + .random(in: 0 ... 1) * 0.4
            // let toothSlope: Float = .random(in: 0 ... 1) * 0.2
            let numTeeth = i % 50 + 3
            let innerRatio: Float = 0.8
            let toothWidth: Float = 0.25
            let toothSlope: Float = 0.2
            let mesh = makeGear(numTeeth: numTeeth, innerRatio: innerRatio, toothWidth: toothWidth, toothSlope: toothSlope)
            tempMeshs.append(mesh)
        }

        // 顶点列表
        let bufferSize = tempMeshs.reduce(0) { $0 + $1.vertices.count * MemoryLayout<AAPLVertex>.size }
        print("buffer size: \(bufferSize)")
        let vertexBuffer = device.makeBuffer(length: bufferSize, options: [])!
        vertexBuffer.label = "顶点列表缓冲区"
        let vertces = UnsafeMutableRawBufferPointer(start: vertexBuffer.contents(), count: bufferSize).bindMemory(to: AAPLVertex.self)
        print("顶点个数：\(vertces.count)")

        // 拷贝数据
        info = []
        var vertexStartIndex = 0
        for mesh in tempMeshs {
            for (j, v) in mesh.vertices.enumerated() {
                vertces[vertexStartIndex + j] = v
            }

            vertexStartIndex += mesh.vertices.count
            info.append(mesh.vertices.count)
        }

        return vertexBuffer
    }

    func makeVertexBuffer2(info: inout [Int]) -> MTLBuffer {
        var numTeeths = [Int]()
        let objectVertexCount = 12
        var bufferSize = 0
        info = []
        for i in 0 ..< objectCount {
            // let numTeeth = Int.random(in: 0 ..< 50) + 3
            let numTeeth = i % 50 + 3
            numTeeths.append(numTeeth)
            let vertexCount = numTeeth * objectVertexCount
            info.append(vertexCount)
            bufferSize += vertexCount * MemoryLayout<AAPLVertex>.size
        }

        // 顶点列表
        print("buffer size: \(bufferSize)")
        let vertexBuffer = device.makeBuffer(length: bufferSize, options: [])!
        vertexBuffer.label = "顶点列表缓冲区"

        var start = 0
        for i in 0 ..< numTeeths.count {
            // let innerRatio: Float = 0.2 + .random(in: 0 ... 1) * 0.7
            // let toothWidth: Float = 0.1 + .random(in: 0 ... 1) * 0.4
            // let toothSlope: Float = .random(in: 0 ... 1) * 0.2
            let innerRatio: Float = 0.8
            let toothWidth: Float = 0.25
            let toothSlope: Float = 0.2
            let numTeeth = numTeeths[i]
            let vertices = UnsafeMutableRawBufferPointer(start: vertexBuffer.contents() + start, count: info[i] * MemoryLayout<AAPLVertex>.size).bindMemory(to: AAPLVertex.self)
            fillGear(numTeeth: numTeeth, innerRatio: innerRatio, toothWidth: toothWidth, toothSlope: toothSlope, subVetices: vertices)
            start += numTeeth * objectVertexCount * MemoryLayout<AAPLVertex>.size
        }

        return vertexBuffer
    }

    func fillGear(numTeeth: Int, innerRatio: Float, toothWidth: Float, toothSlope: Float, subVetices: UnsafeMutableBufferPointer<AAPLVertex>) {
        assert(numTeeth >= 3, "至少需要3个齿")
        assert(toothWidth + 2 * toothSlope < 1, "齿轮参数错误")

        let angle: Float = 2 * .pi / Float(numTeeth)
        let origin: packed_float2 = [0, 0]

        var vtx = 0
        for i in 0 ..< numTeeth {
            // 计算齿和槽的角度
            let tooth = Float(i)
            let toothStartAngle = tooth * angle
            let toothTip1Angle = (tooth + toothSlope) * angle
            let toothTip2Angle = (tooth + toothSlope + toothWidth) * angle
            let toothEndAngle = (tooth + 2 * toothSlope + toothWidth) * angle
            let nextToothAngle = (tooth + 1) * angle

            // 计算齿需要的顶点位置
            let groove1: packed_float2 = [sin(toothStartAngle) * innerRatio, cos(toothStartAngle) * innerRatio]
            let tip1: packed_float2 = [sin(toothTip1Angle), cos(toothTip1Angle)]
            let tip2: packed_float2 = [sin(toothTip2Angle), cos(toothTip2Angle)]
            let groove2: packed_float2 = [sin(toothEndAngle) * innerRatio, cos(toothEndAngle) * innerRatio]
            let nextGroove: packed_float2 = [sin(nextToothAngle) * innerRatio, cos(nextToothAngle) * innerRatio]

            // 齿的右上角三角形
            subVetices[vtx] = .init(position: groove1, texcoord: (groove1 + 1) / 2)
            vtx += 1
            subVetices[vtx] = .init(position: tip1, texcoord: (tip1 + 1) / 2)
            vtx += 1
            subVetices[vtx] = .init(position: tip2, texcoord: (tip2 + 1) / 2)
            vtx += 1

            // 齿左下角三角形
            subVetices[vtx] = .init(position: groove1, texcoord: (groove1 + 1) / 2)
            vtx += 1
            subVetices[vtx] = .init(position: tip2, texcoord: (tip2 + 1) / 2)
            vtx += 1
            subVetices[vtx] = .init(position: groove2, texcoord: (groove2 + 1) / 2)
            vtx += 1

            // 从齿底到齿轮中心的圆的切面
            subVetices[vtx] = .init(position: origin, texcoord: (origin + 1) / 2)
            vtx += 1
            subVetices[vtx] = .init(position: groove1, texcoord: (groove1 + 1) / 2)
            vtx += 1
            subVetices[vtx] = .init(position: groove2, texcoord: (groove2 + 1) / 2)
            vtx += 1

            // 从槽到齿轮中心的圆的切面
            subVetices[vtx] = .init(position: origin, texcoord: (origin + 1) / 2)
            vtx += 1
            subVetices[vtx] = .init(position: groove2, texcoord: (groove2 + 1) / 2)
            vtx += 1
            subVetices[vtx] = .init(position: nextGroove, texcoord: (nextGroove + 1) / 2)
            vtx += 1
        }
    }

    func makeGear(numTeeth: Int, innerRatio: Float, toothWidth: Float, toothSlope: Float) -> Mesh {
        assert(numTeeth >= 3, "至少需要3个齿")
        assert(toothWidth + 2 * toothSlope < 1, "齿轮参数错误")

        // let numVertices = numTeeth * 12
        // let meshVertices = NSMutableArray(capacity: numVertices)
        var meshVertices = [AAPLVertex]()

        let angle: Float = 2 * .pi / Float(numTeeth)
        let origin: packed_float2 = [0, 0]

        for i in 0 ..< numTeeth {
            // 计算齿和槽的角度
            let tooth = Float(i)
            let toothStartAngle = tooth * angle
            let toothTip1Angle = (tooth + toothSlope) * angle
            let toothTip2Angle = (tooth + toothSlope + toothWidth) * angle
            let toothEndAngle = (tooth + 2 * toothSlope + toothWidth) * angle
            let nextToothAngle = (tooth + 1) * angle

            // 计算齿需要的顶点位置
            let groove1: packed_float2 = [sin(toothStartAngle) * innerRatio, cos(toothStartAngle) * innerRatio]
            let tip1: packed_float2 = [sin(toothTip1Angle), cos(toothTip1Angle)]
            let tip2: packed_float2 = [sin(toothTip2Angle), cos(toothTip2Angle)]
            let groove2: packed_float2 = [sin(toothEndAngle) * innerRatio, cos(toothEndAngle) * innerRatio]
            let nextGroove: packed_float2 = [sin(nextToothAngle) * innerRatio, cos(nextToothAngle) * innerRatio]

            let vertices: [AAPLVertex] = [
                // 齿的右上角三角形
                .init(position: groove1, texcoord: (groove1 + 1) / 2),
                .init(position: tip1, texcoord: (tip1 + 1) / 2),
                .init(position: tip2, texcoord: (tip2 + 1) / 2),

                // 齿左下角三角形
                .init(position: groove1, texcoord: (groove1 + 1) / 2),
                .init(position: tip2, texcoord: (tip2 + 1) / 2),
                .init(position: groove2, texcoord: (groove2 + 1) / 2),

                // 从齿底到齿轮中心的圆的切面
                .init(position: origin, texcoord: (origin + 1) / 2),
                .init(position: groove1, texcoord: (groove1 + 1) / 2),
                .init(position: groove2, texcoord: (groove2 + 1) / 2),

                // 从槽到齿轮中心的圆的切面
                .init(position: origin, texcoord: (origin + 1) / 2),
                .init(position: groove2, texcoord: (groove2 + 1) / 2),
                .init(position: nextGroove, texcoord: (nextGroove + 1) / 2),
            ]
            // meshVertices.addObjects(from: vertices)
            meshVertices.append(contentsOf: vertices)
        }

        return Mesh(vertices: meshVertices)
    }
}
