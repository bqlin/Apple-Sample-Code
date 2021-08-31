//
// Created by Bq Lin on 2021/8/30.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import MetalKit

class Renderer: NSObject {
    let maxBuffersInFlight = 3
    let inFlightSemaphore: DispatchSemaphore
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    var renderPipeline: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState!
    var baseColorMap: MTLTexture!
    var normalMap: MTLTexture!
    var specularMap: MTLTexture!
    var dynamicUniformBuffers: [MTLBuffer] = []
    var unifomBufferIndex: Int = 0
    var vertexDescriptor: MTLVertexDescriptor = .init()
    var projectionMatrix: matrix_float4x4 = .init()
    var mesh: MTKMesh!

    init(view: MTKView, device: MTLDevice) {
        inFlightSemaphore = .init(value: maxBuffersInFlight)
        self.device = device
        commandQueue = device.makeCommandQueue()!

        super.init()
        loadMetal(view: view)
        loadAssets()
    }

    func loadMetal(view: MTKView) {
        dynamicUniformBuffers = []
        for i in 0 ..< maxBuffersInFlight {
            let buffer = device.makeBuffer(length: MemoryLayout<AAPLUniforms>.size, options: .storageModeShared)!
            buffer.label = "Uniform Buffer \(i)"
            dynamicUniformBuffers.append(buffer)
        }

        // 顶点
        var attribute = vertexDescriptor.attributes[Int(AAPLVertexAttributePosition.rawValue)]!
        attribute.format = .float3
        attribute.offset = 0
        attribute.bufferIndex = Int(AAPLBufferIndexMeshPositions.rawValue)

        // 纹理坐标
        attribute = vertexDescriptor.attributes[Int(AAPLVertexAttributeTexcoord.rawValue)]!
        attribute.format = .float2
        attribute.offset = 0
        attribute.bufferIndex = Int(AAPLBufferIndexMeshGenerics.rawValue)
        
        // 法线
        attribute = vertexDescriptor.attributes[Int(AAPLVertexAttributeNormal.rawValue)]!
        attribute.format = .half4
        attribute.offset = 8
        attribute.bufferIndex = Int(AAPLBufferIndexMeshGenerics.rawValue)

        // 切线
        attribute = vertexDescriptor.attributes[Int(AAPLVertexAttributeTangent.rawValue)]!
        attribute.format = .half4
        attribute.offset = 16
        attribute.bufferIndex = Int(AAPLBufferIndexMeshGenerics.rawValue)

        // 双切线
        attribute = vertexDescriptor.attributes[Int(AAPLVertexAttributeBitangent.rawValue)]!
        attribute.format = .half4
        attribute.offset = 24
        attribute.bufferIndex = Int(AAPLBufferIndexMeshGenerics.rawValue)

        // 顶点布局
        var layout = vertexDescriptor.layouts[Int(AAPLBufferIndexMeshPositions.rawValue)]!
        layout.stride = 12
        layout.stepRate = 1
        layout.stepFunction = .perVertex

        // 属性布局
        layout = vertexDescriptor.layouts[Int(AAPLBufferIndexMeshGenerics.rawValue)]!
        layout.stride = 32
        layout.stepRate = 1
        layout.stepFunction = .perVertex

        let defaultLibrary = device.makeDefaultLibrary()!
        let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentLighting")
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexTransform")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "渲染管线"
        pipelineDescriptor.sampleCount = view.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat

        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("创建渲染管线失败")
        }
        
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!
    }

    func loadAssets() {
        let modelDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        let attributes = modelDescriptor.attributes as! [MDLVertexAttribute]
        attributes[Int(AAPLVertexAttributePosition.rawValue)].name = MDLVertexAttributePosition
        attributes[Int(AAPLVertexAttributeTexcoord.rawValue)].name = MDLVertexAttributeTextureCoordinate
        attributes[Int(AAPLVertexAttributeNormal.rawValue)].name = MDLVertexAttributeNormal
        attributes[Int(AAPLVertexAttributeTangent.rawValue)].name = MDLVertexAttributeTangent
        attributes[Int(AAPLVertexAttributeBitangent.rawValue)].name = MDLVertexAttributeBitangent

        let allocator = MTKMeshBufferAllocator(device: device)
        let modelMesh = MDLMesh.newCylinder(withHeight: 4, radii: [1.5, 1.5], radialSegments: 60, verticalSegments: 1, geometryType: .triangles, inwardNormals: false, allocator: allocator)
        modelMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, normalAttributeNamed: MDLVertexAttributeNormal, tangentAttributeNamed: MDLVertexAttributeTangent)
        modelMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, tangentAttributeNamed: MDLVertexAttributeTangent, bitangentAttributeNamed: MDLVertexAttributeBitangent)
        modelMesh.vertexDescriptor = modelDescriptor
        do {
            mesh = try .init(mesh: modelMesh, device: device)
        } catch {
            fatalError("创建mesh失败")
        }

        let textureLoader = MTKTextureLoader(device: device)
        let loadOptions: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
        ]
        do {
            baseColorMap = try textureLoader.newTexture(name: "CanBaseColorMap", scaleFactor: 1, bundle: nil, options: loadOptions)
            normalMap = try textureLoader.newTexture(name: "CanNormalMap", scaleFactor: 1, bundle: nil, options: loadOptions)
            specularMap = try textureLoader.newTexture(name: "CanSpecularMap", scaleFactor: 1, bundle: nil, options: loadOptions)
        } catch {
            fatalError("创建纹理失败")
        }
    }

    func updateState(frameNumber: Int) {
        let rotation = Float(frameNumber) * 0.01
        unifomBufferIndex = frameNumber % 3
        var uniform = dynamicUniformBuffers[unifomBufferIndex].contents().load(as: AAPLUniforms.self)
        uniform.directionalLightInvDirection = [0, 0, -1]
        uniform.directionalLightColor = [0.7, 0.7, 0.7]
        uniform.materialShininess = 2

        let modelRotatinAxis: vector_float3 = [1, 0, 0]
        let modelRationMatrix: matrix_float4x4 = matrix4x4_rotation(rotation, modelRotatinAxis)
        let modelMatrix = modelRationMatrix

        let cameraTranslation: vector_float3 = [0, 0, -8]
        let viewMatrix = matrix4x4_translation(-cameraTranslation)
        let viewProjectionMatrix = matrix_multiply(projectionMatrix, viewMatrix)

        uniform.modelMatrix = modelMatrix
        uniform.modelViewProjectionMatrix = matrix_multiply(viewProjectionMatrix, modelMatrix)
        uniform.normalMatrix = matrix3x3_upper_left(modelMatrix)

        dynamicUniformBuffers[unifomBufferIndex].contents().copyMemory(from: &uniform, byteCount: MemoryLayout.size(ofValue: uniform))
    }

    func updateDrawableSize(_ size: CGSize) {
        let aspect = size.width / size.height
        projectionMatrix = matrix_perspective_left_hand(65 * .pi / 180, Float(aspect), 0.1, 100)
    }

    func draw(frameNumber: Int, view: MTKView) {
        inFlightSemaphore.wait()
        updateState(frameNumber: frameNumber)

        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.label = "渲染命令"
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            self?.inFlightSemaphore.signal()
        }

        if let passDescriptor = view.currentRenderPassDescriptor {
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
            renderEncoder.label = "渲染命令编码器"

            renderEncoder.pushDebugGroup("绘制mesh")

            renderEncoder.setCullMode(.back)
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setDepthStencilState(depthState)

            renderEncoder.setVertexBuffer(dynamicUniformBuffers[unifomBufferIndex], offset: 0, index: Int(AAPLBufferIndexUniforms.rawValue))
            renderEncoder.setFragmentBuffer(dynamicUniformBuffers[unifomBufferIndex], offset: 0, index: Int(AAPLBufferIndexUniforms.rawValue))

            for (i, vertexBuffer) in mesh.vertexBuffers.enumerated() {
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: i)
            }
            renderEncoder.setFragmentTexture(baseColorMap, index: Int(AAPLTextureIndexBaseColor.rawValue))
            renderEncoder.setFragmentTexture(normalMap, index: Int(AAPLTextureIndexNormal.rawValue))
            renderEncoder.setFragmentTexture(specularMap, index: Int(AAPLTextureIndexSpecular.rawValue))

            for submesh in mesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset)
            }

            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()
            commandBuffer.present(view.currentDrawable!)
        }
        commandBuffer.commit()
    }
}
