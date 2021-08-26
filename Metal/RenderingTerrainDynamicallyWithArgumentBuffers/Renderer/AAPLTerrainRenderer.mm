/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the terrain renderer which is responsible for rendering tesselated terrain patches.
*/

#import <stdlib.h>      // for random()

#import "TargetConditionals.h"
#import <type_traits>
#import <array>

#import "AAPLTerrainRenderer.h"
#import "AAPLTerrainRenderer_shared.h"
#import "AAPLParticleRenderer.h"
#import "AAPLBufferFormats.h"
#import "AAPLAllocator.h"

using namespace simd;

struct HabitatTextures
{
    id <MTLTexture> diffSpecTextureArray;
    id <MTLTexture> normalTextureArray;
};
static std::array <HabitatTextures, 4> CreateTerrainTextures (id<MTLDevice> device)
{
    std::array <HabitatTextures, 4> res;
    NSArray<NSString*>* habitatNames = @[ @"sand", @"grass", @"rock", @"snow" ];
    
    for (int curHabIdx = 0; curHabIdx < 4; curHabIdx++)
    {
        NSString* filepath;
        
        // Albedo (rgb) + specular (alpha channel)
        // - specular will be manually de-srgb-ified in the shader
        // - KTX format is used in order to leverage precomputed mips
        filepath = [NSString stringWithFormat:@"Textures/terrain_%@_diffspec_array.ktx", habitatNames[curHabIdx]];

        // The KTX converter used when baking the terrain textures changes pixel values for srgb textures.
        // To counter act this, we convert the source texture in linear space. However, Metal will fetch a
        //  non srgb texture format from the KTX, so instead we create views to maintain hardware color management.
        id<MTLTexture> diffSpec = CreateTextureWithDevice (device,
                                                           filepath,
                                                           false,
                                                           false);
        res [curHabIdx].diffSpecTextureArray =
            [diffSpec newTextureViewWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB];
        
        // Normal:
        filepath = [NSString stringWithFormat:@"Textures/terrain_%@_normal_array.ktx", habitatNames[curHabIdx]];
        res [curHabIdx].normalTextureArray = CreateTextureWithDevice (device,
                                                                      filepath,
                                                                      false,
                                                                      false);
        
        assert ([res [curHabIdx].diffSpecTextureArray arrayLength] == VARIATION_COUNT_PER_HABITAT);
        assert ([res [curHabIdx].normalTextureArray   arrayLength] == VARIATION_COUNT_PER_HABITAT);
    }
    return res;
}

@implementation AAPLTerrainRenderer
{
    // Terrain rendering data
    std::array <HabitatTextures, 4> _terrainTextures;
    id<MTLBuffer> _terrainParamsBuffer;
    id <MTLTexture> _terrainHeight;
    id <MTLTexture> _terrainNormalMap;
    id <MTLTexture> _terrainPropertiesMap;
    id <MTLTexture> _targetHeightmap;
    
    // Tesselation data
    id <MTLBuffer> _visiblePatchesTessFactorBfr;
    id <MTLBuffer> _visiblePatchIndicesBfr;
    float _tessellationScale;
    
    // Render pipelines
    id <MTLRenderPipelineState> _pplRnd_TerrainMainView;
    NSUInteger _iabBufferIndex_PplTerrainMainView;
    id <MTLRenderPipelineState> _pplRnd_TerrainShadow;
    
    // Compute pipelines
    id <MTLComputePipelineState> _pplCmp_FillInTesselationFactors;
    id <MTLComputePipelineState> _pplCmp_BakeNormalsMips;
    id <MTLComputePipelineState> _pplCmp_BakePropertiesMips;
    id <MTLComputePipelineState> _pplCmp_ClearTexture;
    id <MTLComputePipelineState> _pplCmp_UpdateHeightmap;;
}

-(float3) terrainWorldBoundsMax
{
    return (float3) { TERRAIN_SCALE / -2.0f, 0, TERRAIN_SCALE / -2.0f };
}

-(float3) terrainWorldBoundsMin
{
    return (float3) { TERRAIN_SCALE / 2.0f, TERRAIN_HEIGHT, TERRAIN_SCALE / 2.0f};
}

-(void) GenerateTerrainNormalMap: (id <MTLCommandBuffer>) commandBuffer
{
    id <MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    
    MTLSize threadsPerThreadgroup = (MTLSize){ 16, 16, 1 };
    assert (((_terrainHeight.width  / 16)*16) == _terrainHeight.width);
    assert (((_terrainHeight.height / 16)*16) == _terrainHeight.height);
    
    [computeEncoder setComputePipelineState:_pplCmp_BakeNormalsMips];
    [computeEncoder setTexture:_terrainHeight atIndex:0];
    [computeEncoder setTexture:_terrainNormalMap atIndex:1];
    [computeEncoder dispatchThreads:MTLSizeMake(_terrainHeight.width, _terrainHeight.height, 1) threadsPerThreadgroup:threadsPerThreadgroup];
    [computeEncoder endEncoding];
}

-(void) GenerateTerrainPropertiesMap: (id <MTLCommandBuffer>) commandBuffer
{
    auto GenerateSamplesBuffer = [] (id<MTLDevice> device, int numSamples)
    {
        std::vector <float2> res;
        
        srandom(12345);
        const float sampleRadius = 32.0f;
        
        for (int i = 0; i < numSamples; i++)
        {
            float u = (float)random() / (float)RAND_MAX;
            float v = (float)random() / (float)RAND_MAX;
            
            float r = sqrtf(u);
            float theta = 2.0f * (float)M_PI * v;
            
            res.push_back ((float2) {cosf(theta), sinf(theta)} * r * sampleRadius);
        }
        
        id<MTLBuffer> buffer = [device newBufferWithBytes:res.data()
                                                   length:res.size()*sizeof(res[0])
#if TARGET_OS_IOS
                                                  options:MTLResourceStorageModeShared];
#else
                                                  options:MTLResourceStorageModeManaged];
#endif
        return buffer;
    };
    static const int numSamples = 256;
    static id<MTLBuffer> sampleBuffer = GenerateSamplesBuffer ([commandBuffer device], numSamples);
    
    id <MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    
    [computeEncoder setComputePipelineState:_pplCmp_BakePropertiesMips];
    [computeEncoder setTexture:_terrainHeight atIndex:0];
    [computeEncoder setTexture:_terrainPropertiesMap atIndex:1];
    [computeEncoder setBuffer:sampleBuffer offset:0 atIndex:0];
    [computeEncoder setBytes:&numSamples length:sizeof(numSamples) atIndex:1];
    
    packed_float2 invSize = {1.f / _terrainHeight.width, 1.f / _terrainHeight.height};
    [computeEncoder setBytes:&invSize length:sizeof(invSize) atIndex:2];
    [computeEncoder dispatchThreads:{_terrainHeight.width, _terrainHeight.height, 1} threadsPerThreadgroup:{16, 16, 1}];
    [computeEncoder endEncoding];
}

static int IabIndexForHabitatParam (TerrainHabitatType habType, TerrainHabitat_MemberIds memberId)
{
    return int (TerrainHabitat_MemberIds::COUNT) * habType + int (memberId);
}
 
template <typename T>
static void EncodeParam (id <MTLArgumentEncoder> paramsEncoder,
                          TerrainHabitatType habType,
                          TerrainHabitat_MemberIds memberId,
                          const T value)
{
    const int index = IabIndexForHabitatParam (habType, memberId);
    T* ptr = (T*) [paramsEncoder constantDataAtIndex:index];
    *ptr = value;
}

template <typename T>
static void EncodeParam (id <MTLArgumentEncoder> paramsEncoder,
                         TerrainParams_MemberIds memberId,
                         const T value)
{
    const int index = int(memberId);
    T* ptr = (T*) [paramsEncoder constantDataAtIndex:index];
    *ptr = value;
}

-(instancetype) initWithDevice:(id <MTLDevice>) device
                       library:(id <MTLLibrary>) library
{
    self = [super init];
    if (!self) return self;
    
    _precomputationCompleted = false;
    id <MTLCommandQueue> queue = [device newCommandQueue];
    id <MTLCommandBuffer> commandBuffer = [queue commandBuffer];
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull)
    {
        self->_precomputationCompleted = true;
    }];
    
    // Loading the textures used by the terrain
    _terrainTextures = CreateTerrainTextures (device);
    
    // Encoding the terrain parameters
    const MTLResourceOptions terrainParamBufferStorage =
#if TARGET_OS_IOS
    MTLResourceStorageModeShared;
#else
    MTLResourceStorageModeManaged;
#endif
    
    id<MTLFunction> terrainShadingFunc = [library newFunctionWithName:@"terrain_fragment"];
    id <MTLArgumentEncoder> paramsEncoder = [terrainShadingFunc newArgumentEncoderWithBufferIndex:1];
    assert (paramsEncoder != nil);
    
    _terrainParamsBuffer = [device newBufferWithLength:[paramsEncoder encodedLength]
                                              options:terrainParamBufferStorage];
    
    [paramsEncoder setArgumentBuffer:_terrainParamsBuffer
                              offset:0];
    
    std::array <const TerrainHabitat::ParticleProperties*, 4> particleProperties =
    [AAPLParticleRenderer GetParticleProperties];
    
    static_assert (TerrainHabitatTypeCOUNT == 4, "");
 
    auto EncodeParamsFromData = [] (id <MTLArgumentEncoder> encoder, TerrainHabitatType curHabitat, const std::array <const TerrainHabitat::ParticleProperties*, 4>& particleProperties, const std::array <HabitatTextures, 4>& terrainTextures)
    {
        EncodeParam (encoder, curHabitat, TerrainHabitat_MemberIds::particle_keyTimePoints,        particleProperties[curHabitat]->keyTimePoints);
        EncodeParam (encoder, curHabitat, TerrainHabitat_MemberIds::particle_scaleFactors,         particleProperties[curHabitat]->scaleFactors);
        EncodeParam (encoder, curHabitat, TerrainHabitat_MemberIds::particle_alphaFactors,         particleProperties[curHabitat]->alphaFactors);
        EncodeParam (encoder, curHabitat, TerrainHabitat_MemberIds::particle_gravity,              particleProperties[curHabitat]->gravity);
        EncodeParam (encoder, curHabitat, TerrainHabitat_MemberIds::particle_lightingCoefficients, particleProperties[curHabitat]->lightingCoefficients);
        EncodeParam (encoder, curHabitat, TerrainHabitat_MemberIds::particle_doesCollide,          particleProperties[curHabitat]->doesCollide);
        EncodeParam (encoder, curHabitat, TerrainHabitat_MemberIds::particle_doesRotate,           particleProperties[curHabitat]->doesRotate);
        EncodeParam (encoder, curHabitat, TerrainHabitat_MemberIds::particle_castShadows,          particleProperties[curHabitat]->castShadows);
        EncodeParam (encoder, curHabitat, TerrainHabitat_MemberIds::particle_distanceDependent,    particleProperties[curHabitat]->distanceDependent);
        [encoder setTexture:terrainTextures[curHabitat].diffSpecTextureArray atIndex:IabIndexForHabitatParam (curHabitat, TerrainHabitat_MemberIds::diffSpecTextureArray)];
        [encoder setTexture:terrainTextures[curHabitat].normalTextureArray   atIndex:IabIndexForHabitatParam (curHabitat, TerrainHabitat_MemberIds::normalTextureArray)];
    };
    
    // Configure the various terrain "habitats."
    // - these are the look-and-feel of visually distinct areas that differ by elevation
    TerrainHabitatType curHabitat;
    
    curHabitat = TerrainHabitatTypeSand;
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::slopeStrength, 100.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::slopeThreshold, 0.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::elevationStrength, 100.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::elevationThreshold, 0.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::specularPower, 32.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::textureScale, 0.001f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::flipNormal, false);
    EncodeParamsFromData (paramsEncoder, curHabitat, particleProperties, _terrainTextures);
    
    curHabitat = TerrainHabitatTypeGrass;
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::slopeStrength, 100.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::slopeThreshold, 0.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::elevationStrength, 40.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::elevationThreshold, 0.146f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::specularPower, 32.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::textureScale, 0.001f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::flipNormal, false);
    EncodeParamsFromData (paramsEncoder, curHabitat, particleProperties, _terrainTextures);
    
    curHabitat = TerrainHabitatTypeRock;
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::slopeStrength, 100.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::slopeThreshold, 0.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::elevationStrength, 40.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::elevationThreshold, 0.28f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::specularPower, 32.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::textureScale, 0.002f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::flipNormal, false);
    EncodeParamsFromData (paramsEncoder, curHabitat, particleProperties, _terrainTextures);
    
    curHabitat = TerrainHabitatTypeSnow;
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::slopeStrength, 43.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::slopeThreshold, 0.612f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::elevationStrength, 100.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::elevationThreshold, 0.39f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::specularPower, 32.f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::textureScale, 0.002f);
    EncodeParam (paramsEncoder, curHabitat, TerrainHabitat_MemberIds::flipNormal, false);
    EncodeParamsFromData (paramsEncoder, curHabitat, particleProperties, _terrainTextures);
    
    EncodeParam (paramsEncoder, TerrainParams_MemberIds::ambientOcclusionScale, 0.f);
    EncodeParam (paramsEncoder, TerrainParams_MemberIds::ambientOcclusionContrast, 0.f);
    EncodeParam (paramsEncoder, TerrainParams_MemberIds::ambientLightScale, 0.f);
    EncodeParam (paramsEncoder, TerrainParams_MemberIds::atmosphereScale, 0.f);

#if TARGET_OS_OSX
    [_terrainParamsBuffer didModifyRange:NSMakeRange(0, [_terrainParamsBuffer length])];
#endif
    
    // Create the compute pipelines
    //  - this is needed further along in data initialization
    {
        _pplCmp_FillInTesselationFactors =          CreateKernelPipeline (device, library, @"TerrainKnl_FillInTesselationFactors");
        _pplCmp_BakePropertiesMips =                CreateKernelPipeline (device, library, @"TerrainKnl_ComputeOcclusionAndSlopeFromHeightmap");
        _pplCmp_BakeNormalsMips =                   CreateKernelPipeline (device, library, @"TerrainKnl_ComputeNormalsFromHeightmap");
        _pplCmp_ClearTexture =                      CreateKernelPipeline (device, library, @"TerrainKnl_ClearTexture");
        _pplCmp_UpdateHeightmap =                   CreateKernelPipeline (device, library, @"TerrainKnl_UpdateHeightmap");
    }
    
    // Use a height map to define the initial terrain topography
    _targetHeightmap = CreateTextureWithDevice (device, @"Textures/TerrainHeightMap.png", false, false);

    const NSUInteger heightMapWidth = _targetHeightmap.width;
    const NSUInteger heightMapHeight = _targetHeightmap.height;
    
    {
        MTLTextureDescriptor *texDesc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR16Unorm
                                                               width:heightMapWidth
                                                              height:heightMapHeight
                                                           mipmapped:NO];
        texDesc.usage |= MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        texDesc.storageMode = MTLStorageModePrivate;
        _terrainHeight = [device newTextureWithDescriptor:texDesc];
        
        id <MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit copyFromTexture:_targetHeightmap
                  sourceSlice:0
                  sourceLevel:0
                 sourceOrigin:{0,0,0}
                   sourceSize:MTLSizeMake(heightMapWidth, heightMapHeight, 1)
                    toTexture:_terrainHeight
             destinationSlice:0
             destinationLevel:0
            destinationOrigin:{0,0,0}];
        [blit endEncoding];
    }
    
    // Create normals and props textures
    {
        MTLTextureDescriptor* texDesc = [[MTLTextureDescriptor alloc] init];
        texDesc.width = heightMapWidth;
        texDesc.height = heightMapHeight;
        texDesc.pixelFormat = MTLPixelFormatRG11B10Float;
        texDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        texDesc.mipmapLevelCount = std::log2(MAX(heightMapWidth, heightMapHeight)) + 1;
        texDesc.storageMode = MTLStorageModePrivate;
        _terrainNormalMap = [device newTextureWithDescriptor:texDesc];
        [self GenerateTerrainNormalMap:commandBuffer];
        
        texDesc.pixelFormat = MTLPixelFormatRGBA8Unorm;
        _terrainPropertiesMap = [device newTextureWithDescriptor:texDesc];
        
        // We need to clear the properties map as 'GenerateTerrainPropertiesMap' will only fill in specific color channels
        {
            id <MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
            [encoder setComputePipelineState:_pplCmp_ClearTexture];
            [encoder setTexture:_terrainPropertiesMap atIndex:0];
            [encoder dispatchThreads:{heightMapWidth, heightMapHeight, 1} threadsPerThreadgroup:{8, 8, 1}];
            [encoder endEncoding];
        }
        [self GenerateTerrainPropertiesMap:commandBuffer];
        
        {
            id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
            [blit generateMipmapsForTexture:_terrainNormalMap];
            [blit generateMipmapsForTexture:_terrainPropertiesMap];
            [blit endEncoding];
        }
    }
    
    // Loading rendering pipelines
    {
        MTLFunctionConstantValues *constants = [MTLFunctionConstantValues new];
        
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.sampleCount = BufferFormats::sampleCount;
        pipelineStateDescriptor.tessellationFactorFormat = MTLTessellationFactorFormatHalf;
        pipelineStateDescriptor.tessellationPartitionMode = MTLTessellationPartitionModeFractionalOdd;
        pipelineStateDescriptor.tessellationFactorStepFunction = MTLTessellationFactorStepFunctionPerPatch;
        pipelineStateDescriptor.tessellationControlPointIndexType = MTLTessellationControlPointIndexTypeNone;
        pipelineStateDescriptor.maxTessellationFactor = 16;
        
        // Create the regular pipeline. This is used later on
        _iabBufferIndex_PplTerrainMainView = 1;
        
        const bool no = false;
        [constants setConstantValue:&no type:MTLDataTypeBool atIndex:0];
        pipelineStateDescriptor.label = @"Terrain";
        pipelineStateDescriptor.vertexFunction = [library newFunctionWithName:@"terrain_vertex"
                                                               constantValues:constants
                                                                        error:nil];
        pipelineStateDescriptor.fragmentFunction = [library newFunctionWithName:@"terrain_fragment"
                                                                 constantValues:constants
                                                                          error:nil];
        assert (pipelineStateDescriptor.vertexFunction != nil && pipelineStateDescriptor.fragmentFunction != nil);
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = BufferFormats::gBuffer0Format;
        pipelineStateDescriptor.colorAttachments[1].pixelFormat = BufferFormats::gBuffer1Format;
#if TARGET_OS_IOS
        pipelineStateDescriptor.colorAttachments[2].pixelFormat = BufferFormats::backBufferformat;
        pipelineStateDescriptor.colorAttachments[3].pixelFormat = BufferFormats::gBufferDepthFormat;
#endif
        pipelineStateDescriptor.depthAttachmentPixelFormat = BufferFormats::depthFormat;
        
        // A good optimization that improves driver performance is to state when a pipeline will
        // modify an argument buffer or not. Doing this saves cache invalidations and memory fetches.
        // Because we know ahad of time that the terrain parameters Argument Buffer will never be modified, we
        // mark the slot immutable that it will be bound to.
        pipelineStateDescriptor.fragmentBuffers[_iabBufferIndex_PplTerrainMainView].mutability = MTLMutabilityImmutable;
    
        NSError* error = NULL;
        _pplRnd_TerrainMainView = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                         error:&error];
        if (!_pplRnd_TerrainMainView) { NSLog(@"Failed to create pipeline state, error %@", error); }
        
        // Create the depth only pipeline for the shadow view
        const bool yes = true;
        [constants setConstantValue:&yes type:MTLDataTypeBool atIndex:0];
        pipelineStateDescriptor.label = @"Terrain Shadow";
        pipelineStateDescriptor.vertexFunction = [library newFunctionWithName:@"terrain_vertex"
                                                               constantValues:constants
                                                                        error:nil];
        assert (pipelineStateDescriptor.vertexFunction != nil);
        pipelineStateDescriptor.fragmentFunction = nil;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatInvalid;
        pipelineStateDescriptor.colorAttachments[1].pixelFormat = MTLPixelFormatInvalid;
        
        // In case it was set for iOS
        pipelineStateDescriptor.colorAttachments[2].pixelFormat = MTLPixelFormatInvalid;
        pipelineStateDescriptor.colorAttachments[3].pixelFormat = MTLPixelFormatInvalid;
        pipelineStateDescriptor.depthAttachmentPixelFormat = BufferFormats::shadowDepthFormat;
            
        error = nil;
        _pplRnd_TerrainShadow = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                          error:&error];
        if (!_pplRnd_TerrainShadow) { NSLog(@"Failed to create pipeline state, error %@", error); }
    }
    
    _tessellationScale = 25.0f;
    _visiblePatchIndicesBfr = [device newBufferWithLength:sizeof(uint32_t) * TERRAIN_PATCHES * TERRAIN_PATCHES
                                                  options:MTLResourceStorageModePrivate];
    
    _visiblePatchesTessFactorBfr = [device newBufferWithLength:sizeof(MTLQuadTessellationFactorsHalf) * TERRAIN_PATCHES * TERRAIN_PATCHES
                                                       options:MTLResourceStorageModePrivate];
    
    [commandBuffer commit];

    return self;
}

-(void) computeTesselationFactors:(id <MTLCommandBuffer>) commandBuffer
                   globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms;
{
    id <MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    
    [computeEncoder setComputePipelineState:_pplCmp_FillInTesselationFactors];
    
    [computeEncoder setBuffer:_visiblePatchesTessFactorBfr offset:0 atIndex:0];
    [computeEncoder setBuffer:_visiblePatchIndicesBfr offset:0 atIndex:2];
    [computeEncoder setBytes:&_tessellationScale length:sizeof(float) atIndex:3];
    [computeEncoder setBuffer:globalUniforms.getBuffer()
                       offset:globalUniforms.getOffset()
                      atIndex:4];
    
    [computeEncoder setTexture:_terrainHeight atIndex:0];
    
    MTLSize threadsPerThreadgroup = { 16, 16, 1 };
    [computeEncoder dispatchThreadgroups:MTLSizeMake(2, 2, 1) threadsPerThreadgroup:threadsPerThreadgroup];
    
    [computeEncoder endEncoding];
}

- (void)drawShadowsWithEncoder:(id <MTLRenderCommandEncoder>)renderEncoder
                globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms
{
    [renderEncoder setRenderPipelineState:_pplRnd_TerrainShadow];
    [renderEncoder setDepthBias:0.001 slopeScale:2 clamp:1];
    
    [renderEncoder setTessellationFactorBuffer:_visiblePatchesTessFactorBfr offset:0 instanceStride:0];
    [renderEncoder setCullMode:MTLCullModeFront];
    
    [renderEncoder setVertexBuffer:globalUniforms.getBuffer() offset:globalUniforms.getOffset() atIndex:1];
    [renderEncoder setVertexTexture:_terrainHeight atIndex:0];
    
    [renderEncoder drawPatches:4
                    patchStart:0
                    patchCount:TERRAIN_PATCHES*TERRAIN_PATCHES
              patchIndexBuffer:_visiblePatchIndicesBfr
        patchIndexBufferOffset:0
                 instanceCount:1
                  baseInstance:0];
}

// The terrain main rendering pass
- (void)drawWithEncoder:(id <MTLRenderCommandEncoder>)renderEncoder
         globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms
{
    [renderEncoder setRenderPipelineState:_pplRnd_TerrainMainView];
    
    // - Note: depth stencil state is already set by the main renderer
    
    // Indicate to Metal that these resources will be accessed by the GPU and therefore
    //   must be mapped to the GPU's address space
    for (int i = 0; i < _terrainTextures.size(); i++)
    {
        [renderEncoder useResource: _terrainTextures[i].diffSpecTextureArray
                             usage: MTLResourceUsageSample | MTLResourceUsageRead];
        [renderEncoder useResource: _terrainTextures[i].normalTextureArray
                             usage: MTLResourceUsageSample | MTLResourceUsageRead];
    }

    [renderEncoder setTessellationFactorBuffer:_visiblePatchesTessFactorBfr offset:0 instanceStride:0];
    [renderEncoder setVertexBuffer:globalUniforms.getBuffer() offset:globalUniforms.getOffset() atIndex:1];
    [renderEncoder setVertexTexture:_terrainHeight atIndex:0];

    // Set the argument buffer
    [renderEncoder setFragmentBuffer:_terrainParamsBuffer offset:0 atIndex:_iabBufferIndex_PplTerrainMainView];

    [renderEncoder setFragmentBuffer:globalUniforms.getBuffer() offset:globalUniforms.getOffset() atIndex:2];
    [renderEncoder setFragmentTexture:_terrainHeight atIndex:0];
    [renderEncoder setFragmentTexture:_terrainNormalMap atIndex:1];
    [renderEncoder setFragmentTexture:_terrainPropertiesMap atIndex:2];
    
    [renderEncoder drawPatches:4
                    patchStart:0
                    patchCount:TERRAIN_PATCHES*TERRAIN_PATCHES
              patchIndexBuffer:_visiblePatchIndicesBfr
        patchIndexBufferOffset:0
                 instanceCount:1
                  baseInstance:0];
}


-(void) computeUpdateHeightMap:(id <MTLCommandBuffer>) commandBuffer
                   globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms
                      mouseBuffer:(id<MTLBuffer>) mouseBuffer
;
{
    id <MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    
    [computeEncoder setComputePipelineState:_pplCmp_UpdateHeightmap];
    [computeEncoder setTexture:_terrainHeight atIndex:0];
    [computeEncoder setBuffer:mouseBuffer offset:0 atIndex:0];
    [computeEncoder setBuffer:globalUniforms.getBuffer() offset:globalUniforms.getOffset() atIndex:1];
    [computeEncoder dispatchThreadgroups:MTLSizeMake(_terrainHeight.width/8, _terrainHeight.height/8, 1) threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
    [computeEncoder endEncoding];
    
    [self GenerateTerrainNormalMap:commandBuffer];
    [self GenerateTerrainPropertiesMap:commandBuffer];
    
    id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
    [blit generateMipmapsForTexture:_terrainNormalMap];
    [blit generateMipmapsForTexture:_terrainPropertiesMap];
    [blit endEncoding];
}

@end
