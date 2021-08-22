//
//  Renderer.swift
//  BasicTexturing-iOS
//
//  Created by Bq Lin on 2021/5/13.
//  Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import MetalKit

class Renderer: NSObject, MTKViewDelegate {
    init(mtkView: MTKView) {
        device = mtkView.device!
        viewportSize = mtkView.drawableSize.toVector_uint2
        super.init()
        
        texture = loadTexture(fileUrl: Bundle.main.url(forResource: "Image", withExtension: "tga")!)
        
        let quadVertices: [AAPLVertex] = [
            AAPLVertex(position: [+250, -250], textureCoordinate: [1, 1]),
            AAPLVertex(position: [-250, -250], textureCoordinate: [0, 1]),
            AAPLVertex(position: [-250, +250], textureCoordinate: [0, 0]),
            
            AAPLVertex(position: [+250, -250], textureCoordinate: [1, 1]),
            AAPLVertex(position: [-250, +250], textureCoordinate: [0, 0]),
            AAPLVertex(position: [+250, +250], textureCoordinate: [1, 0]),
        ]
        
        vertices = device.makeBuffer(bytes: quadVertices, length: quadVertices.count * MemoryLayout<AAPLVertex>.size, options: .storageModeShared)
        numVertices = quadVertices.count
        
        guard let defaultLibrary = device.makeDefaultLibrary() else {
            fatalError("can not make default library!")
        }
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")
        let fragmentFunction = defaultLibrary.makeFunction(name: "samplingShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "TexturePipeline"
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
        
        mtkView.delegate = self
    }
    
    let device: MTLDevice
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var texture: MTLTexture!
    var vertices: MTLBuffer!
    var numVertices: Int!
    
    func loadTexture(fileUrl: URL) -> MTLTexture! {
        let image = TGAImage(fileURL: fileUrl)
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.width = image.width
        textureDescriptor.height = image.height
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }
        
        let region = MTLRegionMake2D(0, 0, image.width, image.height)
        let bytesPerRow = 4 * image.width
        texture.replace(region: region, mipmapLevel: 0, withBytes: (image.data as NSData).bytes, bytesPerRow: bytesPerRow)
        return texture
    }
    
    // MARK: MTKViewDelegate
    var viewportSize: vector_uint2
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size.toVector_uint2
    }
    
    // 该方法绘制的是一帧的内容
    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "TextureCommandBuffer"
        
        if let passDescriptor = view.currentRenderPassDescriptor {
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
                fatalError("can not make render command encoder!")
            }
            renderEncoder.label = "TextureRenderEncoder"
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertices, offset: 0, index: Int(AAPLVertexInputIndexVertices.rawValue))
            renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout.size(ofValue: viewportSize), index: Int(AAPLVertexInputIndexViewportSize.rawValue))
            renderEncoder.setFragmentTexture(texture, index: Int(AAPLTextureIndexBaseColor.rawValue))

            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: numVertices)
            
            renderEncoder.endEncoding()
            
            commandBuffer.present(view.currentDrawable!)
        }
        
        commandBuffer.commit()
    }
}

extension CGSize {
    var toVector_uint2: vector_uint2 {
        [UInt32(width), UInt32(height)]
    }
}

