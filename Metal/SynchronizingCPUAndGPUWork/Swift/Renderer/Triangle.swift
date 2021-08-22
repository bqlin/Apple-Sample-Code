//
//  Triangle.swift
//  CPU-GPU-Synchronization
//
//  Created by Bq Lin on 2021/5/13.
//  Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import simd

struct Triangle {
    var position: vector_float2
    var color: vector_float4
    
    static let TriangleSize: Float = 64
    static let vertices: [AAPLVertex] = [
        AAPLVertex(position: [-0.5 * TriangleSize, -0.5 * TriangleSize], color: [1, 1, 1, 1]),
        AAPLVertex(position: [+0.0 * TriangleSize, +0.5 * TriangleSize], color: [1, 1, 1, 1]),
        AAPLVertex(position: [+0.5 * TriangleSize, -0.5 * TriangleSize], color: [1, 1, 1, 1]),
    ]
}
