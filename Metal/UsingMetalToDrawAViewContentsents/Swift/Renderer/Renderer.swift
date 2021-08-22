//
// Created by Bq Lin on 2021/8/22.
// Copyright © 2021 Bq. All rights reserved.
//

import MetalKit

class Renderer: NSObject {
    let device: MTLDevice
    var commandQueue: MTLCommandQueue!
    
    init(view: MTKView) {
        device = view.device!
        super.init()
        
        commandQueue = device.makeCommandQueue()!
        view.delegate = self
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        if let passDescriptor = view.currentRenderPassDescriptor {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            
            // Create a render pass and immediately end encoding, causing the drawable to be cleared
            let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
            commandEncoder.endEncoding()
            
            // Request that the drawable texture be presented by the windowing system once drawing is done
            commandBuffer.present(view.currentDrawable!)
            commandBuffer.commit()
        }
    }
}
