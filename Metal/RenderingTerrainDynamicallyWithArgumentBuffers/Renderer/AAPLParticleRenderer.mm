/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the AAPLParticleRenderer which is responsible for rendering particles.
*/

#import <MetalKit/MetalKit.h>

#import "AAPLBufferFormats.h"
#import "AAPLParticleRenderer.h"
#import "AAPLParticleRenderer_shared.h"

using namespace simd;

MTKMesh* LoadParticleMesh (id <MTLDevice> device, NSString* path)
{
    MTKMeshBufferAllocator* allocator = [[MTKMeshBufferAllocator alloc] initWithDevice:device];
    NSError *error;
    
    MTLVertexDescriptor *_mtlVertexDescriptor = [[MTLVertexDescriptor alloc] init];
    
    // Positions
    _mtlVertexDescriptor.attributes[0].format = MTLVertexFormatHalf4;
    _mtlVertexDescriptor.attributes[0].offset = 0;
    _mtlVertexDescriptor.attributes[0].bufferIndex = 0;
    
    // Texture coordinates
    _mtlVertexDescriptor.attributes[1].format = MTLVertexFormatHalf2;
    _mtlVertexDescriptor.attributes[1].offset = 8;
    _mtlVertexDescriptor.attributes[1].bufferIndex = 0;
    
    // Normals
    _mtlVertexDescriptor.attributes[2].format = MTLVertexFormatHalf3;
    _mtlVertexDescriptor.attributes[2].offset = 12;
    _mtlVertexDescriptor.attributes[2].bufferIndex = 0;
    
    // Tangents
    _mtlVertexDescriptor.attributes[3].format = MTLVertexFormatHalf3;
    _mtlVertexDescriptor.attributes[3].offset = 18;
    _mtlVertexDescriptor.attributes[3].bufferIndex = 0;
    
    // Bitangents
    _mtlVertexDescriptor.attributes[4].format = MTLVertexFormatHalf3;
    _mtlVertexDescriptor.attributes[4].offset = 24;
    _mtlVertexDescriptor.attributes[4].bufferIndex = 0;
    
    // Position Buffer Layout
    _mtlVertexDescriptor.layouts[0].stride = 32;
    _mtlVertexDescriptor.layouts[0].stepRate = 1;
    _mtlVertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    // Create a ModelIO vertexDescriptor so that we layout our ModelIO geometry's vertices to
    //  fit our Metal render pipeline's vertex descriptor layout
    MDLVertexDescriptor *modelIOVertexDescriptor =
    MTKModelIOVertexDescriptorFromMetal(_mtlVertexDescriptor);
    
    // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
    modelIOVertexDescriptor.attributes[0].name  = MDLVertexAttributePosition;
    modelIOVertexDescriptor.attributes[1].name  = MDLVertexAttributeTextureCoordinate;
    modelIOVertexDescriptor.attributes[2].name    = MDLVertexAttributeNormal;
    modelIOVertexDescriptor.attributes[3].name   = MDLVertexAttributeTangent;
    modelIOVertexDescriptor.attributes[4].name = MDLVertexAttributeBitangent;
    
    NSURL* url = [[NSBundle mainBundle] URLForResource:path withExtension:@""];
    
    MDLAsset *asset = [[MDLAsset alloc] initWithURL:url
                                   vertexDescriptor:modelIOVertexDescriptor
                                    bufferAllocator:allocator];
    
    NSArray<MDLMesh*>* mdlMeshes = nil;
    
    NSArray<MTKMesh*>* meshes = [MTKMesh newMeshesFromAsset:asset device:device sourceMeshes:&mdlMeshes error:&error];
    if([meshes count] == 0 || meshes[0] == nil || error)
    {
        NSLog(@"Error creating MetalKit geometry %@", error.localizedDescription);
        return nil;
    }
    return meshes[0];
}

@implementation AAPLParticleRenderer
#if TARGET_OS_IOS
{}
#else
{
    NSArray<MTKMesh*>* _particleMeshes;

    id<MTLBuffer> _particleDataPool;
    id<MTLBuffer> _aliveIndicesList;
    id<MTLBuffer> _aliveIndicesCount;
    id<MTLBuffer> _unusedIndicesList;
    id<MTLBuffer> _unusedIndicesCount;
    id<MTLBuffer> _nextAliveIndicesList;
    id<MTLBuffer> _nextAliveIndicesCount;
    
    id<MTLBuffer> _drawCurrentFrame;
    id<MTLBuffer> _drawNextFrame;
    
    id<MTLBuffer> _dispatchParams;
    
    id <MTLComputePipelineState> _AnimateAndCleanupKnl;
    id <MTLComputePipelineState> _SpawnKnl;
    
    id <MTLRenderPipelineState>  _shadowsPpl;
    id <MTLRenderPipelineState>  _gBufferPpl;
}

-(id) initWithDevice: (id <MTLDevice>)  device
             library: (id <MTLLibrary>) library
{
    self = [super init];
    if (! self) return self;
    
    // Creating the shadows pass' pipeline state
    {
        NSError* error = nil;
        const bool yes = true;
        MTLFunctionConstantValues* constants = [MTLFunctionConstantValues new];
        [constants setConstantValue:&yes type:MTLDataTypeBool atIndex:0]; // depth only
        
        MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction = [library newFunctionWithName:@"ParticleVs"
                                            constantValues:constants
                                                     error:&error];
        assert (desc.vertexFunction != nil);
        desc.depthAttachmentPixelFormat = BufferFormats::shadowDepthFormat;
        
        _shadowsPpl = [device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (!_shadowsPpl) { NSLog(@"Failed to create pipeline state, error %@", error); }
    }
    
    // Creating the G-buffer pass' pipeline state
    {
        NSError* error = nil;
        const bool no = false;
        MTLFunctionConstantValues* constants = [MTLFunctionConstantValues new];
        [constants setConstantValue:&no type:MTLDataTypeBool atIndex:0]; // not depth only
        
        MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction = [library newFunctionWithName:@"ParticleVs"
                                            constantValues:constants
                                                     error:&error];
        desc.fragmentFunction = [library newFunctionWithName:@"ParticlePs"
                                              constantValues:constants
                                                       error:&error];
        assert (desc.vertexFunction != nil && desc.fragmentFunction != nil);
        desc.colorAttachments[0].pixelFormat = BufferFormats::gBuffer0Format;
        desc.colorAttachments[1].pixelFormat = BufferFormats::gBuffer1Format;
#if TARGET_OS_IOS
        desc.colorAttachments[2].pixelFormat = BufferFormats::backBufferformat;
        desc.colorAttachments[3].pixelFormat = BufferFormats::gBufferDepthFormat;
#endif
        desc.depthAttachmentPixelFormat = BufferFormats::depthFormat;
        
        _gBufferPpl = [device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (!_gBufferPpl) { NSLog(@"Failed to create pipeline state, error %@", error); }
    }
    
    // Creating particles simulation kernel
    {
        _AnimateAndCleanupKnl = CreateKernelPipeline (device, library, @"AnimateAndCleanupOldParticles", false);
        _SpawnKnl = CreateKernelPipeline (device, library, @"SpawnNewParticles", false);
    }
    
    // Loading particle geometry
    _particleMeshes =
    @[
        LoadParticleMesh (device, @"Meshes/Particles/Cloud.obj"),
        LoadParticleMesh (device, @"Meshes/Particles/Rock.obj")
    ];
    
    // Both cloud mesh and rock mesh should have same topology
    // When rendering particles the renderer doesn't know which type of particle it's rendering
    assert(_particleMeshes[0].submeshes[0].indexCount == _particleMeshes[1].submeshes[0].indexCount);
    
    // Creating buffers
    const NSUInteger particleDataSize = [library] ()
    {
        id <MTLFunction> fn = [library newFunctionWithName:@"AnimateAndCleanupOldParticles"];
        id <MTLArgumentEncoder> encoder = [fn newArgumentEncoderWithBufferIndex:0];
        return [encoder encodedLength];
    }();

    const MTLResourceOptions storageMode = MTLResourceStorageModePrivate;
    
    _particleDataPool =      [device newBufferWithLength:MAX_PARTICLES*particleDataSize
                                                    options:storageMode];
    _aliveIndicesList =      [device newBufferWithLength:MAX_PARTICLES*sizeof(uint16_t)
                                                    options:storageMode];
    _aliveIndicesCount =     [device newBufferWithLength:sizeof(uint32_t)
                                                    options:storageMode];
    _unusedIndicesList =     [device newBufferWithLength:MAX_PARTICLES*sizeof(uint16_t)
                                                    options:storageMode];
    _unusedIndicesCount =    [device newBufferWithLength:sizeof(uint32_t)
                                                    options:storageMode];
    _nextAliveIndicesList =  [device newBufferWithLength:MAX_PARTICLES*sizeof(uint16_t)
                                                    options:storageMode];
    _nextAliveIndicesCount = [device newBufferWithLength:sizeof(uint32_t)
                                                    options:storageMode];
    _dispatchParams =        [device newBufferWithLength:sizeof(MTLDispatchThreadgroupsIndirectArguments)
                                                    options:storageMode];
    _drawCurrentFrame =      [device newBufferWithLength:sizeof(MTLDrawIndexedPrimitivesIndirectArguments)
                                                    options:storageMode];
    _drawNextFrame =         [device newBufferWithLength:sizeof(MTLDrawIndexedPrimitivesIndirectArguments)
                                                    options:storageMode];
    
    {
        id <MTLCommandQueue> queue = [device newCommandQueue];
        id <MTLCommandBuffer> commandBuffer = [queue commandBuffer];
        id <MTLBlitCommandEncoder> blit =[commandBuffer blitCommandEncoder];

        [blit fillBuffer:_particleDataPool      range:NSMakeRange(0, [_particleDataPool length])      value:0];
        [blit fillBuffer:_aliveIndicesList      range:NSMakeRange(0, [_aliveIndicesList length])      value:0];
        [blit fillBuffer:_aliveIndicesCount     range:NSMakeRange(0, [_aliveIndicesCount length])     value:0];
        [blit fillBuffer:_nextAliveIndicesList  range:NSMakeRange(0, [_nextAliveIndicesList length])  value:0];
        [blit fillBuffer:_nextAliveIndicesCount range:NSMakeRange(0, [_nextAliveIndicesCount length]) value:0];
    
        id <MTLBuffer> templateBuffer;
        {
            std::vector <uint16_t> freeIndices;
            for (int i = MAX_PARTICLES-1; i >= 0; i--) { freeIndices.push_back (uint16_t(i)); }
            templateBuffer = [device newBufferWithBytes:freeIndices.data()
                                                 length:sizeof(freeIndices[0]) * freeIndices.size()
                                                options:MTLResourceStorageModeManaged];
            
            [blit copyFromBuffer:templateBuffer
                    sourceOffset:0
                        toBuffer:_unusedIndicesList
               destinationOffset:0
                            size:[templateBuffer length]];
        }
        {
            const uint32_t freeIndicesCount = MAX_PARTICLES;
            templateBuffer = [device newBufferWithBytes:&freeIndicesCount
                                                 length:sizeof(freeIndicesCount)
                                                options:MTLResourceStorageModeManaged];
            
            [blit copyFromBuffer:templateBuffer
                    sourceOffset:0
                        toBuffer:_unusedIndicesCount
               destinationOffset:0
                            size:[templateBuffer length]];
        }
        {
            const MTLDrawIndexedPrimitivesIndirectArguments drawTplData =
            {
                (uint32_t)_particleMeshes[0].submeshes[0].indexCount,
                0,
                0,
                0,
                0
            };
            templateBuffer = [device newBufferWithBytes:&drawTplData
                                                 length:sizeof(drawTplData)
                                                options:MTLResourceStorageModeManaged];
            
            [blit copyFromBuffer:templateBuffer
                    sourceOffset:0
                        toBuffer:_drawCurrentFrame
               destinationOffset:0
                            size:[templateBuffer length]];
            
            [blit copyFromBuffer:templateBuffer
                    sourceOffset:0
                        toBuffer:_drawNextFrame
               destinationOffset:0
                            size:[templateBuffer length]];
        }
        {
            const MTLDispatchThreadgroupsIndirectArguments dispatchTplData = {1,1,1};
            templateBuffer = [device newBufferWithBytes:&dispatchTplData
                                                 length:sizeof(dispatchTplData)
                                                options:MTLResourceStorageModeManaged];
            
            [blit copyFromBuffer:templateBuffer
                    sourceOffset:0
                        toBuffer:_dispatchParams
               destinationOffset:0
                            size:[templateBuffer length]];
        }
        
        [blit endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
    }
    
    return self;
}

-(void) spawnParticleWithCommandBuffer: (id <MTLCommandBuffer>) commandBuffer
                              uniforms: (const AAPLGpuBuffer<AAPLUniforms>) uniforms
                               terrain: (AAPLTerrainRenderer*) terrain
                           mouseBuffer: (id <MTLBuffer>) mouseBuffer
                          numParticles: (NSUInteger) numParticles
{
    numParticles = std::min (numParticles, (NSUInteger)MAX_PARTICLES);

    std::swap (_drawCurrentFrame,  _drawNextFrame);
    
    const float4x4 viewMatrix;
    id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
    
    [enc setBuffer:_particleDataPool        offset:0 atIndex:0];
    [enc setBuffer:_aliveIndicesList        offset:0 atIndex:1];
    [enc setBuffer:_aliveIndicesCount       offset:0 atIndex:2];
    [enc setBuffer:_unusedIndicesList       offset:0 atIndex:3];
    [enc setBuffer:_unusedIndicesCount      offset:0 atIndex:4];
    [enc setBuffer:_nextAliveIndicesList    offset:0 atIndex:5];
    [enc setBuffer:_nextAliveIndicesCount   offset:0 atIndex:6];
    [enc setBuffer:_drawCurrentFrame
            offset:offsetof(MTLDrawIndexedPrimitivesIndirectArguments, instanceCount)
           atIndex:7];
    
    [enc setBytes:&numParticles length:sizeof(numParticles) atIndex:8];
    
    [enc setBuffer:_drawNextFrame
            offset:offsetof(MTLDrawIndexedPrimitivesIndirectArguments, instanceCount)
           atIndex:10];
    
    [enc setBuffer:_dispatchParams offset:0 atIndex:11];
    
    [enc setBuffer:uniforms.getBuffer() offset:uniforms.getOffset() atIndex:12];
    [enc setBuffer:[terrain terrainParamsBuffer] offset:0 atIndex:14];
    [enc setBuffer:mouseBuffer offset:0 atIndex:15];
    [enc setTexture:[terrain terrainHeight]        atIndex:0];
    [enc setTexture:[terrain terrainNormalMap]     atIndex:1];
    [enc setTexture:[terrain terrainPropertiesMap] atIndex:2];
    
    [enc setComputePipelineState:_AnimateAndCleanupKnl];
    [enc dispatchThreadgroupsWithIndirectBuffer:_dispatchParams
                           indirectBufferOffset:0
                          threadsPerThreadgroup:MTLSizeMake(PARTICLES_PER_THREADGROUP, 1, 1)];
    
    [enc setComputePipelineState:_SpawnKnl];
    [enc dispatchThreads:MTLSizeMake (1+numParticles, 1, 1)
   threadsPerThreadgroup:MTLSizeMake (PARTICLES_PER_THREADGROUP, 1, 1)];
    
    [enc endEncoding];
    
    // Swapping _drawCurrentFrame and _drawNextFrame will be done after the drawcall
    std::swap (_aliveIndicesList,  _nextAliveIndicesList);
    std::swap (_aliveIndicesCount, _nextAliveIndicesCount);
}

-(void) drawWithEncoder: (id <MTLRenderCommandEncoder>) renderEncoder
               uniforms: (AAPLGpuBuffer <AAPLUniforms>) uniforms
              depthDraw: (bool) depthDraw
{
    if(depthDraw)
    {
        [renderEncoder setRenderPipelineState:_shadowsPpl];
    }
    else
    {
        [renderEncoder setRenderPipelineState:_gBufferPpl];
    }
    
    // Set the per-frame parameters
    [renderEncoder setVertexBuffer:uniforms.getBuffer()
                            offset:uniforms.getOffset()
                           atIndex:0];
    
    [renderEncoder setVertexBuffer:_particleDataPool
                            offset:0
                           atIndex:1];
    
    [renderEncoder setVertexBuffer:_aliveIndicesList
                            offset:0
                           atIndex:2];
    
    if(!depthDraw)
    {
        [renderEncoder setFragmentBuffer:uniforms.getBuffer()
                                  offset:uniforms.getOffset()
                                 atIndex:0];
        
        [renderEncoder setFragmentBuffer:_particleDataPool
                                  offset:0
                                 atIndex:1];
    }
    
    [renderEncoder setVertexBuffer:_particleMeshes[0].vertexBuffers[0].buffer
                            offset:_particleMeshes[0].vertexBuffers[0].offset
                           atIndex:10];
    
    [renderEncoder setVertexBuffer:_particleMeshes[0].vertexBuffers[0].buffer
                            offset:_particleMeshes[0].vertexBuffers[0].offset
                           atIndex:11];
    
    [renderEncoder setVertexBuffer:_particleMeshes[1].vertexBuffers[0].buffer
                            offset:_particleMeshes[1].vertexBuffers[0].offset
                           atIndex:12];
    
    [renderEncoder setVertexBuffer:_particleMeshes[1].vertexBuffers[0].buffer
                            offset:_particleMeshes[1].vertexBuffers[0].offset
                           atIndex:13];
    
    [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                               indexType:_particleMeshes[0].submeshes[0].indexType
                             indexBuffer:_particleMeshes[0].submeshes[0].indexBuffer.buffer
                       indexBufferOffset:_particleMeshes[0].submeshes[0].indexBuffer.offset
                          indirectBuffer:_drawCurrentFrame
                    indirectBufferOffset:0];
}

#endif

+(std::array <const TerrainHabitat::ParticleProperties*, 4>) GetParticleProperties
{
    static TerrainHabitat::ParticleProperties chunkyParticle;
    chunkyParticle.keyTimePoints = (float4){0.0,4.0,5.0,6.0};
    chunkyParticle.scaleFactors = (float4){1.0,1.0,1.0,0.4};
    chunkyParticle.alphaFactors = (float4){1.0,1.0,1.0,0.0};
    chunkyParticle.gravity = (float4){0.0f,-400.0f,0.0f,0.0f}; // includes weight
    chunkyParticle.lightingCoefficients = (float4){1.0f,0.0f,0.0f,0.0f};
    chunkyParticle.doesCollide = 1;
    chunkyParticle.doesRotate = 1;
    chunkyParticle.castShadows = 1;
    chunkyParticle.distanceDependent = 0;
    
    static TerrainHabitat::ParticleProperties puffyParticle;
    puffyParticle.keyTimePoints = (float4){0.0,0.3,0.8,1.2};
    puffyParticle.scaleFactors = ((float4){0.0,0.8,2.0,2.9})*0.3f;
    puffyParticle.alphaFactors = (float4){1.0,1.0,1.0,0.0};
    puffyParticle.gravity = (float4){0.0f,-50.0f,0.0f,0.0}; // includes weight
    puffyParticle.lightingCoefficients = (float4){0.0f,1.0f,0.0f,0.0f};
    puffyParticle.doesCollide = 0;
    puffyParticle.doesRotate = 0;
    puffyParticle.castShadows = 0;
    puffyParticle.distanceDependent = 1;
    
    std::array <const TerrainHabitat::ParticleProperties*, 4> res =
    {
        &puffyParticle,
        &puffyParticle,
        &chunkyParticle,
        &chunkyParticle,
    };
    return res;
}

@end
