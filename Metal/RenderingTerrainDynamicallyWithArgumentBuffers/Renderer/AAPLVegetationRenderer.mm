/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the vegetation renderer which is responsible for the terrain-specific foliage geometry.
*/

#import "AAPLVegetationRenderer.h"
#import "AAPLVegetationRenderer_shared.h"
#import "AAPLTerrainRenderer_shared.h"
#import "AAPLBufferFormats.h"
#import "AAPLTerrainRenderer.h"
#import "AAPLCamera.h"
using namespace simd;

@implementation AAPLVegetationPopulation

-(instancetype) initWithObjMesh:(const AAPLObjMesh*) mesh
{    self = [super init];
    _mesh = mesh;
    return self;
}

@end

@implementation AAPLVegetationRenderer
{
    id<MTLRenderPipelineState>      _vegetationPipeline;
    id<MTLRenderPipelineState>      _vegetationShadowPipeline;
    id<MTLComputePipelineState>     _vegetationComputePipeline;
    AAPLVegetationPopulation*       _populations[kPopulationCount];
    AAPLPopulationRule        _rules[TerrainHabitatTypeCOUNT][kRulesPerHabitat];
    
    id <MTLBuffer>                  _indirectResetBuffer;
    id <MTLBuffer>                  _instanceBuffer;
    id <MTLBuffer>                  _indirectBuffer;
    id <MTLBuffer>                  _ruleBuffer;
    id <MTLBuffer>                  _historyBuffer;
    
    // Utility to load vegetation geometry from disk
    AAPLObjLoader*                  _objLoader;
    
    // The device (aka GPU) we're using to render
    id <MTLDevice>                  _device;

}

// Init the vegetation renderer and load its assets
-(instancetype) initWithDevice:(id<MTLDevice>)device library:(id <MTLLibrary>) library
{
    self = [super init];
    _device = device;
    _objLoader = [[AAPLObjLoader alloc] initWithDevice:device];
    
    [self loadAssetsFromLibrary: library];
    
    bool shadow_only = false;
    MTLFunctionConstantValues *constants = [MTLFunctionConstantValues new];
    [constants setConstantValue:&shadow_only type:MTLDataTypeBool atIndex:0];

    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.sampleCount = BufferFormats::sampleCount;
    pipelineStateDescriptor.label = @"VegetationGeo";
    pipelineStateDescriptor.vertexFunction = [library newFunctionWithName:@"vegetation_vertex" constantValues:constants error:nil];
    pipelineStateDescriptor.fragmentFunction = [library newFunctionWithName:@"vegetation_fragment"];
    assert (pipelineStateDescriptor.vertexFunction != nil && pipelineStateDescriptor.fragmentFunction != nil);

    pipelineStateDescriptor.colorAttachments[0].pixelFormat = BufferFormats::gBuffer0Format;
    pipelineStateDescriptor.colorAttachments[1].pixelFormat = BufferFormats::gBuffer1Format;
#if TARGET_OS_IOS
    pipelineStateDescriptor.colorAttachments[2].pixelFormat = BufferFormats::backBufferformat;
    pipelineStateDescriptor.colorAttachments[3].pixelFormat = BufferFormats::gBufferDepthFormat;
#endif
    pipelineStateDescriptor.depthAttachmentPixelFormat = BufferFormats::depthFormat;
    NSError* error = NULL;
    _vegetationPipeline = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 error:&error];
    shadow_only = true;
    [constants setConstantValue:&shadow_only type:MTLDataTypeBool atIndex:0];
    pipelineStateDescriptor.sampleCount = BufferFormats::sampleCount;
    pipelineStateDescriptor.label = @"VegetationShadow";
    pipelineStateDescriptor.vertexFunction = [library newFunctionWithName:@"vegetation_vertex" constantValues:constants error:nil];
    pipelineStateDescriptor.fragmentFunction = nil;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatInvalid;
    pipelineStateDescriptor.colorAttachments[1].pixelFormat = MTLPixelFormatInvalid;
    
    // - Note: in case it was set for iOS
    pipelineStateDescriptor.colorAttachments[2].pixelFormat = MTLPixelFormatInvalid;
    pipelineStateDescriptor.colorAttachments[3].pixelFormat = MTLPixelFormatInvalid;
    pipelineStateDescriptor.depthAttachmentPixelFormat = BufferFormats::depthFormat;
    
    _vegetationShadowPipeline = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                       error:&error];
    MTLComputePipelineDescriptor* computePipelineStateDescriptor = [[MTLComputePipelineDescriptor alloc] init];
    computePipelineStateDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true;
    
    // Set the main work-horse function that selects and spawns vegetation
    computePipelineStateDescriptor.computeFunction = [library newFunctionWithName:@"vegetation_instanceGenerate"];
    assert (computePipelineStateDescriptor.computeFunction != nil);
    
    _vegetationComputePipeline =
    [device newComputePipelineStateWithDescriptor:computePipelineStateDescriptor
                                          options:0
                                       reflection:nil
                                            error:&error];
    if (!_vegetationComputePipeline) { NSLog(@"Failed to create pipeline state, error %@", error); }

#if TARGET_OS_IOS
    const MTLResourceOptions storageMode = MTLResourceStorageModeShared;
#else
    const MTLResourceOptions storageMode = MTLResourceStorageModeManaged;
#endif
    _instanceBuffer         = [device newBufferWithLength:(sizeof(float4x4)*kMaxInstanceCount*kPopulationCount*kCameraCount) options:storageMode];
    _indirectBuffer         = [device newBufferWithLength:(sizeof(MTLDrawIndexedPrimitivesIndirectArguments)*kPopulationCount*kCameraCount) options:storageMode];
    _ruleBuffer             = [device newBufferWithLength:(sizeof(AAPLPopulationRule)*kRulesPerHabitat*TerrainHabitatTypeCOUNT) options:storageMode];
    _indirectResetBuffer    = [device newBufferWithLength:(sizeof(MTLDrawIndexedPrimitivesIndirectArguments)*kPopulationCount*kCameraCount) options:storageMode];
    _historyBuffer          = [device newBufferWithLength:(sizeof(uint32_t)*kGridResolution*kGridResolution) options:MTLResourceStorageModePrivate];


    // Interate over all cameras and all populations and initialize all bins
    MTLDrawIndexedPrimitivesIndirectArguments* args = (MTLDrawIndexedPrimitivesIndirectArguments*)_indirectResetBuffer.contents;
    for (uint cam_idx = 0; cam_idx < kCameraCount; cam_idx++)
    for (uint pop_idx = 0; pop_idx < kPopulationCount; pop_idx++)
    {
        uint b = GetBinFor(pop_idx, cam_idx);
        args[b].baseInstance = b * kMaxInstanceCount;
        args[b].baseVertex = 0;
        args[b].instanceCount = 0;
        args[b].indexCount = (uint32_t) _populations[pop_idx].mesh.indexCount;
        args[b].indexStart = 0;
    }
#if !TARGET_OS_IOS
    [_indirectResetBuffer didModifyRange:NSMakeRange(0, _indirectBuffer.length)];
#endif
    
    
    // Copy the rules over to the rule buffer for run-time evaluation
    AAPLPopulationRule* pph = (AAPLPopulationRule*)_ruleBuffer.contents;
    memcpy(pph, _rules, _ruleBuffer.length);
#if !TARGET_OS_IOS
    [_ruleBuffer didModifyRange:NSMakeRange(0, _ruleBuffer.length)];
#endif
    
    return self;
}

-(void) loadAssetsFromLibrary:(id <MTLLibrary>) library
{
    NSString* population_meshes[kPopulationCount] =
    {
      // Grass is [0..11]
      @"Meshes/Trees/acacia1.obj",
      @"Meshes/Trees/acacia2.obj",
      @"Meshes/Trees/acacia3.obj",
      @"Meshes/Trees/acacia4.obj",
      @"Meshes/Trees/oak1.obj",
      @"Meshes/Trees/oak2.obj",
      @"Meshes/Trees/oak3.obj",
      @"Meshes/Trees/oak4.obj",
      @"Meshes/Trees/cottonwood1.obj",
      @"Meshes/Trees/cottonwood2.obj",
      @"Meshes/Trees/cottonwood3.obj",
      @"Meshes/Trees/cottonwood4.obj",
      
      // Stone/desert/snow is [12..13]
      @"Meshes/Trees/dead_tree1.obj",
      @"Meshes/Trees/dead_tree2.obj",
      
      // Desert is [14..16]
      @"Meshes/Trees/palmtree1.obj",
      @"Meshes/Trees/palmtree2.obj",
      @"Meshes/Trees/palmtree3.obj",
    
      // Snow is [17..20]
      @"Meshes/Trees/pine1.obj",
      @"Meshes/Trees/pine2.obj",
      @"Meshes/Trees/pine3.obj",
      @"Meshes/Trees/pine4.obj",
    };
    
    for (uint pop = 0; pop < kPopulationCount; pop++)
    {
        AAPLObjMesh* mesh = [_objLoader loadFromUrl:[[NSBundle mainBundle] URLForResource:population_meshes[pop] withExtension:@""]];
        _populations[pop] = [[AAPLVegetationPopulation alloc] initWithObjMesh:mesh];
    }
    
    // Rules for different habitats are composed of:
    //  - 1. Scale
    //  - 2. Probability
    //  - 3. Population index
    //  - 4. Population index count
    
    // Acacia tree
    _rules[TerrainHabitatTypeGrass][0] = { 0.30f, 1.0f, 0, 4 };
    
    // Oak tree
    _rules[TerrainHabitatTypeGrass][1] = { 0.30f, 1.0f, 4, 4 };
    
    // Cottonwood tree
    _rules[TerrainHabitatTypeGrass][2] = { 0.35f, 0.7f, 8, 4 };
    
    // Large acacia tree
    _rules[TerrainHabitatTypeGrass][0] = { 0.05f, 2.0f, 0, 4 };
    
    // The two dead trees assets have density 0.1 in rock
    _rules[TerrainHabitatTypeRock][0] =  { 0.1f, 1.0f, 12, 2 };

    // Four types of snow trees
    _rules[TerrainHabitatTypeSnow][0] =  { 0.9f, 1.0f, 17, 4 };
    
    // The two dead trees assets have density 0.1 in snow
    _rules[TerrainHabitatTypeSnow][1] =  { 0.1f, 1.0f, 12, 2 };
    
    // Three types of palmtree in sand; density 0.3
    _rules[TerrainHabitatTypeSand][0] =  { 0.2f, 1.0f, 14, 3 };
    
    // The two dead trees assets have density 0.1 in sand(desert)
    _rules[TerrainHabitatTypeSand][1] =  { 0.1f, 1.0f, 12, 2 };

}


-(void) spawnVegetationWithCommandbuffer: (id <MTLCommandBuffer>) commandBuffer
                                uniforms: (AAPLGpuBuffer <AAPLUniforms>) uniforms
                                 terrain: (AAPLTerrainRenderer*) terrain
{

    // Reset counts of all populations by copying the original init buffer over the run-time buffer
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder copyFromBuffer:_indirectResetBuffer sourceOffset:0 toBuffer:_indirectBuffer destinationOffset:0 size:_indirectBuffer.length];
    [blitEncoder endEncoding];
    
    // Run compute to populate all populations
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    [computeEncoder setBuffer:_instanceBuffer offset:0 atIndex:0];
    [computeEncoder setBuffer:_indirectBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:uniforms.getBuffer() offset:uniforms.getOffset() atIndex:2];
    
    [computeEncoder setBuffer:terrain.terrainParamsBuffer offset:0 atIndex:3];

    [computeEncoder setBuffer:_ruleBuffer offset:0 atIndex:4];
    [computeEncoder setBuffer:_historyBuffer offset:0 atIndex:5];

    [computeEncoder setTexture:terrain.terrainHeight atIndex: 0];
    [computeEncoder setTexture:terrain.terrainNormalMap atIndex: 1];
    [computeEncoder setTexture:terrain.terrainPropertiesMap atIndex: 2];
    [computeEncoder setComputePipelineState:_vegetationComputePipeline];
    [computeEncoder dispatchThreadgroups:MTLSizeMake(kGridResolution/8, kGridResolution/8, 1) threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
    [computeEncoder endEncoding];
    
    // Sync all population data back to CPU for stats
    blitEncoder = [commandBuffer blitCommandEncoder];
#if TARGET_OS_OSX
    [blitEncoder synchronizeResource:_indirectBuffer];
#endif
    [blitEncoder endEncoding];
}

-(void)drawVegetationWithEncoder:(id <MTLRenderCommandEncoder>)renderEncoder
                  globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms
{
    [renderEncoder setRenderPipelineState: _vegetationPipeline];
    for (uint pop_idx = 0; pop_idx < kPopulationCount; pop_idx++)
    {
        AAPLVegetationPopulation* pop = _populations[pop_idx];
        
        [renderEncoder setVertexBuffer:pop.mesh.vertexBuffer offset:0 atIndex:0];
        [renderEncoder setVertexBuffer:_instanceBuffer offset:0 atIndex:1];
        [renderEncoder setVertexBuffer:globalUniforms.getBuffer() offset:globalUniforms.getOffset() atIndex:2];
        [renderEncoder setFragmentBuffer:globalUniforms.getBuffer() offset:globalUniforms.getOffset() atIndex:0];
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                   indexType:MTLIndexTypeUInt16
                                 indexBuffer:pop.mesh.indexBuffer
                           indexBufferOffset:0
                              indirectBuffer:_indirectBuffer
                        indirectBufferOffset:GetBinFor(pop_idx, 0)*sizeof(MTLDrawIndexedPrimitivesIndirectArguments)];
    }
}

-(void)drawShadowsWithEncoder:(id <MTLRenderCommandEncoder>)renderEncoder
               globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms
                 cascadeIndex:(uint) cascadeIndex
{
    [renderEncoder setRenderPipelineState: _vegetationShadowPipeline];
    uint cam_idx = cascadeIndex + 1;
    for (uint pop_idx = 0; pop_idx < kPopulationCount; pop_idx++)
    {
        AAPLVegetationPopulation* pop = _populations[pop_idx];
        [renderEncoder setVertexBuffer:pop.mesh.vertexBuffer offset:0 atIndex:0];
        [renderEncoder setVertexBuffer:_instanceBuffer offset:0 atIndex:1];
        [renderEncoder setVertexBuffer:globalUniforms.getBuffer() offset:globalUniforms.getOffset() atIndex:2];
        [renderEncoder setFragmentBuffer:globalUniforms.getBuffer() offset:globalUniforms.getOffset() atIndex:0];
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
        indexType:MTLIndexTypeUInt16
        indexBuffer:pop.mesh.indexBuffer
        indexBufferOffset:0
        indirectBuffer:_indirectBuffer
        indirectBufferOffset:GetBinFor(pop_idx, cam_idx)*sizeof(MTLDrawIndexedPrimitivesIndirectArguments)];
    }
}

@end
