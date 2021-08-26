/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the AAPLMainRenderer which is responsible for the highest level rendering operations.
*/

#import <MetalKit/MetalKit.h>
#import <ModelIO/ModelIO.h>

#import "AAPLRendererCommon.h"
#import "AAPLBufferFormats.h"
#import "AAPLMainRenderer.h"
#import "AAPLParticleRenderer.h"
#import "AAPLTerrainRenderer.h"
#import "AAPLVegetationRenderer.h"
#import "AAPLObjLoader.h"
#import "AAPLParticleRenderer_shared.h"

using namespace simd;

@implementation AAPLMainRenderer
{
    // The device (aka GPU) we're using to render
    id <MTLDevice>                  _device;
    
    // The command Queue from which we'll obtain command buffers
    id <MTLCommandQueue>            _commandQueue;
    
    // Count the frames. Primarily for option of frame-based times
    // for repeatable results with testing infrastructure.
    NSUInteger _onFrame;            // to count frames, and using frame-based times

    // Marks the start of a frame to keep runtime timing consistent
    NSDate*                         _startTime;
    
    dispatch_semaphore_t            _inFlightSemaphore;
    AAPLAllocator*                  _frameAllocator;
    AAPLGpuBuffer <AAPLUniforms>    _uniforms_gpu;
    AAPLUniforms                    _uniforms_cpu;
    
    MTLRenderPassDescriptor*        _shadowPassDesc;
    MTLRenderPassDescriptor*        _gBufferPassDesc;
#if TARGET_OS_OSX
    MTLRenderPassDescriptor*        _gBufferWithLoadPassDesc;
    MTLRenderPassDescriptor*        _lightingPassDesc;
#endif
    MTLRenderPassDescriptor*        _debugPassDesc;
    
    // Store the render pass descriptors because they are set up once at initialization
    id <MTLDepthStencilState>       _shadowDepthState;
    id <MTLDepthStencilState>       _gBufferDepthState;
    id <MTLDepthStencilState>       _lightingDepthState;
    id <MTLDepthStencilState>       _debugDepthState;
    bool                            _debugPassIsEnabled;
    
    id <MTLTexture>                 _shadowMap;
    id <MTLTexture>                 _depth;
    
    // The geometry buffers
    id <MTLTexture>                 _gBuffer0;
    id <MTLTexture>                 _gBuffer1;
#if TARGET_OS_IOS
    id <MTLTexture>                 _gBufferDepth;
#endif
    id <MTLTexture>                 _skyCubeMap;
    id <MTLTexture>                 _perlinMap;
    
    id <MTLBuffer>                  _mouseBuffer;
    
    // Our render pipeline composed of our vertex and fragment shaders in the .metal shader file
    id <MTLRenderPipelineState>     _lightingPpl;
    id <MTLComputePipelineState>    _mousePositionComputeKnl;
    
    // The individual renderers
    AAPLVegetationRenderer*         _vegetationRenderer;
    AAPLTerrainRenderer*            _terrainRenderer;
#if TARGET_OS_OSX
    AAPLParticleRenderer*           _particleRenderer;
#endif
}

-(nullable instancetype) initWithDevice:(nonnull id<MTLDevice>) device size:(CGSize) size
{
    self = [super init];
    if (! self) return self;
 
#if TARGET_OS_IOS
    _brushSize = 7000.0f;
#else
    _brushSize = 1000.0f;
#endif
    
    // We allow up to three command buffers to be in flight on GPU before we wait
    static const NSUInteger kMaxBuffersInFlight = 3;
    
    _device             = device;
    _commandQueue       = [_device newCommandQueue];
    _startTime          = [NSDate date];
    _inFlightSemaphore  = dispatch_semaphore_create (kMaxBuffersInFlight);
    _frameAllocator     = new AAPLAllocator (device, 1024 * 1024 * 16, kMaxBuffersInFlight);
    _uniforms_gpu       = _frameAllocator->allocBuffer <AAPLUniforms> (1);
    
    _onFrame            = 0;

#if !USE_CONST_GAME_TIME
    // We need to initialize this value because _uniforms_cpu.frameTime depends on it
    _uniforms_cpu.gameTime = 0.f;
#endif
    
    // Create the shadow map ahead of time in order to fill in the pass descriptor with the its texture pointer
    {
        static const NSUInteger shadowWidth = 1024;
        
        MTLTextureDescriptor *desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:BufferFormats::shadowDepthFormat
                                                           width:shadowWidth
                                                          height:shadowWidth
                                                       mipmapped:NO];
        desc.textureType = MTLTextureType2DArray;
        desc.arrayLength = NUM_CASCADES;
        desc.usage      |= MTLTextureUsageRenderTarget;
        desc.storageMode = MTLStorageModePrivate;
        
        _shadowMap       = [_device newTextureWithDescriptor:desc];
        _shadowMap.label = @"ShadowMap";
    }
    
    MTLDepthStencilDescriptor* depthStateDesc   = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction         = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled            = YES;
    
    // Shadow render pass
    _shadowPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    _shadowPassDesc.depthAttachment.texture             = _shadowMap;
    _shadowPassDesc.depthAttachment.clearDepth          = 1.f;
    _shadowPassDesc.depthAttachment.loadAction          = MTLLoadActionClear;
    _shadowPassDesc.depthAttachment.storeAction         = MTLStoreActionStore;
    _shadowDepthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
    
    // GBuffer pass
    _gBufferPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    _gBufferPassDesc.depthAttachment.clearDepth         = 1.f;
    _gBufferPassDesc.depthAttachment.loadAction         = MTLLoadActionClear;
    _gBufferPassDesc.depthAttachment.storeAction        = MTLStoreActionStore;
#if TARGET_OS_OSX
    // We cannot shade on-chip on macOS, so we need to store the GBuffers
    _gBufferPassDesc.colorAttachments[0].loadAction     = MTLLoadActionDontCare;
    _gBufferPassDesc.colorAttachments[0].storeAction    = MTLStoreActionStore;
    _gBufferPassDesc.colorAttachments[1].loadAction     = MTLLoadActionDontCare;
    _gBufferPassDesc.colorAttachments[1].storeAction    = MTLStoreActionStore;
#else
    // On iOS, we won't need the gbuffer to be stored
    _gBufferPassDesc.colorAttachments[0].loadAction     = MTLLoadActionDontCare;
    _gBufferPassDesc.colorAttachments[0].storeAction    = MTLStoreActionDontCare;
    _gBufferPassDesc.colorAttachments[1].loadAction     = MTLLoadActionDontCare;
    _gBufferPassDesc.colorAttachments[1].storeAction    = MTLStoreActionDontCare;

    // The _gBufferPassDesc.colorAttachments[2].texture receives the backbuffer every frame
    _gBufferPassDesc.colorAttachments[2].loadAction     = MTLLoadActionDontCare;
    _gBufferPassDesc.colorAttachments[2].storeAction    = MTLStoreActionStore;

    // The _gBufferPassDesc.colorAttachments[3].texture receives the on-chip depth value copy
    _gBufferPassDesc.colorAttachments[3].clearColor     = MTLClearColorMake (1.0, 1.0, 1.0, 1.0);
    _gBufferPassDesc.colorAttachments[3].loadAction     = MTLLoadActionClear;
    _gBufferPassDesc.colorAttachments[3].storeAction    = MTLStoreActionDontCare;
#endif
    
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _gBufferDepthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
    
#if TARGET_OS_OSX
    _gBufferWithLoadPassDesc = [_gBufferPassDesc copy];
    _gBufferWithLoadPassDesc.depthAttachment.loadAction     = MTLLoadActionLoad;
    _gBufferWithLoadPassDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;
    _gBufferWithLoadPassDesc.colorAttachments[1].loadAction = MTLLoadActionLoad;
    
    _lightingPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    _lightingPassDesc.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    _lightingPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
#endif
    
    depthStateDesc.depthCompareFunction = MTLCompareFunctionAlways;
    depthStateDesc.depthWriteEnabled = NO;
    _lightingDepthState = [device newDepthStencilStateWithDescriptor:depthStateDesc];

    // Debug pass
    _debugPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    _debugPassDesc.depthAttachment.loadAction         = MTLLoadActionLoad;
    _debugPassDesc.depthAttachment.storeAction        = MTLStoreActionDontCare;
    _debugPassDesc.colorAttachments[0].loadAction     = MTLLoadActionLoad;
    
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _debugDepthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
    
    _debugPassIsEnabled = false;
    
    // Create the geometry buffers and depth textures
    [self DrawableSizeWillChange:size];
    
    assert (_depth != nil);
    assert (_depth == _gBufferPassDesc.depthAttachment.texture);
    assert (_depth == _debugPassDesc.depthAttachment.texture);
    assert (_gBuffer0 != nil);
    assert (_gBuffer0 == _gBufferPassDesc.colorAttachments[0].texture);
    assert (_gBuffer1 != nil);
    assert (_gBuffer1 == _gBufferPassDesc.colorAttachments[1].texture);
#if TARGET_OS_IOS
    assert (_gBufferDepth != nil);
    assert (_gBufferDepth == _gBufferPassDesc.colorAttachments[3].texture);
#else
    assert (_gBufferPassDesc.depthAttachment.texture     == _gBufferWithLoadPassDesc.depthAttachment.texture);
    assert (_gBufferPassDesc.colorAttachments[0].texture == _gBufferWithLoadPassDesc.colorAttachments[0].texture);
    assert (_gBufferPassDesc.colorAttachments[1].texture == _gBufferWithLoadPassDesc.colorAttachments[1].texture);
#endif
    
    // Load the sky cube map. KTX format is used in order to leverage precomputed mips
    _skyCubeMap = [CreateTextureWithDevice (device, @"Textures/skyCubeMap.ktx", false, false) newTextureViewWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB];
    
    _perlinMap = CreateTextureWithDevice (device, @"Textures/perlinMap.png", false, false);
    
    id <MTLLibrary> library = [device newDefaultLibrary];
    NSError* error = nil;
    // Lighting render pipeline
    {
        MTLRenderPipelineDescriptor* pplDesc = [[MTLRenderPipelineDescriptor alloc] init];
        pplDesc.label = @"Lighting";
        pplDesc.vertexFunction = [library newFunctionWithName:@"LightingVs"];
        pplDesc.fragmentFunction = [library newFunctionWithName:@"LightingPs"];
        pplDesc.sampleCount = BufferFormats::sampleCount;
        assert (pplDesc.vertexFunction != nil && pplDesc.fragmentFunction != nil);
        
#if TARGET_OS_IOS
        
        // On iOS, the lighting pass will use color attachments as geometry buffer data source
        //  We also need to enumerate all the render targets used in the geometry buffer rendering and the lighting
        pplDesc.depthAttachmentPixelFormat = BufferFormats::depthFormat;
        pplDesc.colorAttachments[0].pixelFormat = BufferFormats::gBuffer0Format;
        pplDesc.colorAttachments[1].pixelFormat = BufferFormats::gBuffer1Format;
        pplDesc.colorAttachments[2].pixelFormat = BufferFormats::backBufferformat;
        pplDesc.colorAttachments[3].pixelFormat = BufferFormats::gBufferDepthFormat;
        assert (pplDesc.depthAttachmentPixelFormat      == [_gBufferPassDesc.depthAttachment.texture     pixelFormat]);
        assert (pplDesc.colorAttachments[0].pixelFormat == [_gBufferPassDesc.colorAttachments[0].texture pixelFormat]);
        assert (pplDesc.colorAttachments[1].pixelFormat == [_gBufferPassDesc.colorAttachments[1].texture pixelFormat]);
        assert (pplDesc.colorAttachments[3].pixelFormat == [_gBufferPassDesc.colorAttachments[3].texture pixelFormat]);
#else
        pplDesc.colorAttachments[0].pixelFormat = BufferFormats::backBufferformat;
#endif
        _lightingPpl = [device newRenderPipelineStateWithDescriptor:pplDesc
                                                              error:&error];
        if (!_lightingPpl) { NSLog(@"Failed to create pipeline state, error %@", error); }
    }
    
    // Create pipeline state for mouse-cursor update and its buffers
    {
#if TARGET_OS_IOS
    const MTLResourceOptions storageMode = MTLResourceStorageModeShared;
#else
    const MTLResourceOptions storageMode = MTLResourceStorageModeManaged;
#endif

#if TARGET_OS_IOS
        float4 initialMouseWorldPos = (float4){2000.f, 0.f, 1000.f, 0.f};
#else
        float4 initialMouseWorldPos = (float4){0.f, 0.f, 0.f, 0.f};
#endif
        _mouseBuffer = [device newBufferWithBytes:&initialMouseWorldPos length:sizeof(initialMouseWorldPos) options:storageMode];

        // Store 1 byte buffer for the 3D mouse position after depth read and resolve
        MTLComputePipelineDescriptor *pipelineStateDescriptor = [[MTLComputePipelineDescriptor alloc] init];
        pipelineStateDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = YES;
        pipelineStateDescriptor.computeFunction = [library newFunctionWithName:@"mousePositionUpdate"];
        assert (pipelineStateDescriptor.computeFunction != nil);
    
        _mousePositionComputeKnl = [_device newComputePipelineStateWithDescriptor:pipelineStateDescriptor options:0 reflection:nil error:&error];
        if (!_mousePositionComputeKnl)
        {
            NSLog(@"Error creating Deformation pipeline: %@", error);
        }
    }
    
    _vegetationRenderer = [[AAPLVegetationRenderer alloc] initWithDevice: device
                                                                 library: library];
    
    _terrainRenderer = [[AAPLTerrainRenderer alloc] initWithDevice: device
                                                           library: library];
    
#if TARGET_OS_OSX
    _particleRenderer = [[AAPLParticleRenderer alloc] initWithDevice: device
                                                             library: library];
#endif
    
    // Wait for terrain precomputation to complete
    while (! [_terrainRenderer precomputationCompleted]) { sleep(1); }
    
    return self;
}

// Update the variables which are available to the GPU every frame
-(void) UpdateCpuUniforms
{
    _onFrame++;
    _uniforms_cpu.cameraUniforms                = _camera.uniforms;
    float gameTime = _onFrame * (1.0 / 60.f);
    _uniforms_cpu.frameTime                     = max (0.001f, gameTime - 0);

    _uniforms_cpu.mouseState                    = (float3) { _cursorPosition.x, _cursorPosition.y, float(_mouseButtonMask) };
    _uniforms_cpu.invScreenSize                 = (float2){1.f / [_gBuffer0 width], 1.f / [_gBuffer0 height]};
    _uniforms_cpu.projectionYScale              = 1.73205066;
    // set above; // _uniforms_cpu.gameTime                      = (float) -[_startTime timeIntervalSinceNow];
    _uniforms_cpu.ambientOcclusionContrast      = 3;
    _uniforms_cpu.ambientOcclusionScale         = 0.800000011;
    _uniforms_cpu.ambientLightScale             = 0.699999988;
    _uniforms_cpu.brushSize                     = _brushSize;
    
    // Set up shadows
    //  - to cover as much of our frustum with shadow volumes, we create a simplified 1D model along the frustum center axis.
    //  Our frustum is reduced to a gradient that coincides with our tan(view angle/2). The three shadow volumes are modeled as a three circles
    //  that are packed under the gradient, so that all space is overlapped at least once. We then project the three circles back to 3D spheres
    //  and wrap them in 3 shadow volumes (parallel camera volumes) by constructing an oriented box around them
    {
        const float3 sunDirection       = normalize ((float3) {1,-0.7,0.5});
   
        // Extend view angle to the angle of the corners of the frustum to get the cone angle; we use half-angles in the math
        float tan_half_angle = tanf(_camera.viewAngle * .5f) * sqrtf(2.0);
        float half_angle = atanf(tan_half_angle);
        float sine_half_angle = sinf(half_angle);
        
        // Define three bounding spheres that cover/fill the view cone. These can be optimized by angle, etc., for nice coverage without over spending shadow map space
        float cascade_sizes[NUM_CASCADES] = {400.0f, 1600.0f, 6400.0f };
        
        // Now the centers of the cone in distance to camera can be calulated
        float cascade_distances[NUM_CASCADES];
        cascade_distances[0] = 2 * cascade_sizes[0] * (1.0f - sine_half_angle * sine_half_angle);
        cascade_distances[1] = sqrtf(cascade_sizes[1]*cascade_sizes[1] - cascade_distances[0]*cascade_distances[0]*tan_half_angle*tan_half_angle) + cascade_distances[0];
        cascade_distances[2] = sqrtf(cascade_sizes[2]*cascade_sizes[2] - cascade_distances[1]*cascade_distances[1]*tan_half_angle*tan_half_angle) + cascade_distances[1];
        
        for (uint c = 0; c < NUM_CASCADES; c++)
        {
            // Center of sun cascade back-plane
            float3 center = _camera.position + _camera.direction * cascade_distances[c];
            float size = cascade_sizes[c];
            
            // Stepsize is some multiple of the texel size
            float stepsize = size/64.0f;
            AAPLCamera* shadow_cam  = [[AAPLCamera alloc] initParallelWithPosition:center-sunDirection*size direction:sunDirection up:(float3) { 0, 1, 0} width:size*2.0f height:size*2.0f nearPlane:0.0f farPlane:size*2];
            shadow_cam.position -= fract(dot(center, shadow_cam.up) /stepsize) * shadow_cam.up * stepsize;
            shadow_cam.position -= fract(dot(center, shadow_cam.right) /stepsize) * shadow_cam.right * stepsize;

            _uniforms_cpu.shadowCameraUniforms[c] = shadow_cam.uniforms;
        }
    }
}

// The main rendering method
-(void) UpdateWithDrawable:(id<MTLDrawable> _Nonnull) drawable
      renderPassDescriptor:(MTLRenderPassDescriptor* _Nonnull) renderPassDescriptor
         waitForCompletion:(bool) waitForCompletion
{
    // Per-frame updates here
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Frame CB";

    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
     {
         dispatch_semaphore_signal(block_sema);
     }];

    [self UpdateCpuUniforms];
    _uniforms_gpu.fillInWith (&_uniforms_cpu, 1);

    // We start the frame by doing non-render work
    // Update the terrain tesselation patches so they are more tesselated when closer to the camera
    [_terrainRenderer computeTesselationFactors:commandBuffer
                                 globalUniforms:_uniforms_gpu];
    
#if TARGET_OS_OSX
    // We spawn/update the particles on macOS only
    const uint particleQuantity = _uniforms_cpu.brushSize*_uniforms_cpu.brushSize*0.0001;
    [_particleRenderer spawnParticleWithCommandBuffer:commandBuffer
                                             uniforms:_uniforms_gpu
                                              terrain:_terrainRenderer
                                          mouseBuffer:_mouseBuffer
                                         numParticles:(_mouseButtonMask != 0) ? particleQuantity : 0];
#endif
    
    // Spawn/update the vegetation
    [_vegetationRenderer spawnVegetationWithCommandbuffer:commandBuffer
                                                 uniforms:_uniforms_gpu
                                                  terrain:_terrainRenderer];
    // Do the actual rendering now
    // - Shadow pass
    for (uint32_t iCascade = 0; iCascade < NUM_CASCADES; iCascade++)
    {
        _shadowPassDesc.depthAttachment.slice = iCascade;
        id <MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:_shadowPassDesc];
        encoder.label = [NSString stringWithFormat:@"Shadow Cascade %i", iCascade];
        
        [encoder setCullMode:MTLCullModeFront];
        [encoder setDepthClipMode:MTLDepthClipModeClamp];
        [encoder setDepthStencilState:_shadowDepthState];
        
        [encoder setViewport:MTLViewport{0, 0, (double)_shadowMap.width, (double)_shadowMap.height, 0.f, 1.f}];
        [encoder setScissorRect:MTLScissorRect{0, 0, _shadowMap.width, _shadowMap.height}];
        [encoder setVertexBytes:&_uniforms_cpu.shadowCameraUniforms[iCascade].viewProjectionMatrix
                         length:sizeof(float4x4)
                        atIndex:6];
        
        [_terrainRenderer drawShadowsWithEncoder:encoder
                                  globalUniforms:_uniforms_gpu];

        [_vegetationRenderer drawShadowsWithEncoder:encoder
                                     globalUniforms:_uniforms_gpu
                                        cascadeIndex:iCascade];
        
        [encoder endEncoding];
    }
    
    // Geometry buffer pass
    {
#if TARGET_OS_IOS
        // On iOS, we do all of the rendering on-chip a.k.a., programmable blending
        // - We must add the final lighting destination to the pass too
        _gBufferPassDesc.colorAttachments [2].texture = renderPassDescriptor.colorAttachments [0].texture;
#endif
        id <MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:_gBufferPassDesc];
        
        [renderEncoder setCullMode:MTLCullModeBack];
        [renderEncoder setDepthStencilState:_gBufferDepthState];

        // Draw the terrain geometry using the argument buffer
        [_terrainRenderer drawWithEncoder:renderEncoder
                           globalUniforms:_uniforms_gpu];

#if TARGET_OS_OSX
        [renderEncoder endEncoding];
        
        // On macOS, we need a kernel to update the mouse position in world space.
        // For that, we need the depth, but only containing the terrain. Thus we have to
        // stop the rendering now and resume it after the kernel has finished.
        {
            id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
            [computeEncoder setComputePipelineState:_mousePositionComputeKnl];
            [computeEncoder setTexture:_depth atIndex:0];
            [computeEncoder setBuffer:_uniforms_gpu.getBuffer() offset:_uniforms_gpu.getOffset() atIndex:0];
            [computeEncoder setBuffer:_mouseBuffer offset:0 atIndex:1];
            [computeEncoder dispatchThreads:{1, 1, 1} threadsPerThreadgroup:{64, 1, 1}];
            [computeEncoder endEncoding];
        }
        
        renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:_gBufferWithLoadPassDesc];
        
        [renderEncoder setCullMode:MTLCullModeBack];
        [renderEncoder setDepthStencilState:_gBufferDepthState];
#endif
        
        // Render the vegetation geometry
        [_vegetationRenderer drawVegetationWithEncoder:renderEncoder
                                        globalUniforms:_uniforms_gpu];
        
#if TARGET_OS_OSX
        // Render particles geometry (macOS only - see `README.md`)
        [_particleRenderer drawWithEncoder:renderEncoder
                                  uniforms:_uniforms_gpu
                                 depthDraw:false];
#else
        [renderEncoder setRenderPipelineState:_lightingPpl];
        [renderEncoder setDepthStencilState:_lightingDepthState];
        [renderEncoder setFragmentTexture:_shadowMap atIndex:3];
        [renderEncoder setFragmentTexture:_skyCubeMap atIndex:4];
        [renderEncoder setFragmentTexture:_perlinMap atIndex:5];
        [renderEncoder setFragmentBuffer:_uniforms_gpu.getBuffer() offset:_uniforms_gpu.getOffset() atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
#endif
        
        [renderEncoder endEncoding];
    }

    // Check for mouse input and manipulate the terrain geometry as needed
    if (_mouseButtonMask != 0)
    {
        [_terrainRenderer computeUpdateHeightMap:commandBuffer
                                  globalUniforms:_uniforms_gpu
                                     mouseBuffer:_mouseBuffer];
    }
    
#if TARGET_OS_OSX
    // Standalone deferred lighting pass on macOS
    {
        _lightingPassDesc.colorAttachments[0].texture = renderPassDescriptor.colorAttachments [0].texture;
        
        id <MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:_lightingPassDesc];
        [encoder setRenderPipelineState:_lightingPpl];
        [encoder setDepthStencilState:_lightingDepthState];
        [encoder setFragmentTexture:_gBuffer0 atIndex:0];
        [encoder setFragmentTexture:_gBuffer1 atIndex:1];
        [encoder setFragmentTexture:_depth atIndex:2];
        [encoder setFragmentTexture:_shadowMap atIndex:3];
        [encoder setFragmentTexture:_skyCubeMap atIndex:4];
        [encoder setFragmentTexture:_perlinMap atIndex:5];
        [encoder setFragmentBuffer:_uniforms_gpu.getBuffer() offset:_uniforms_gpu.getOffset() atIndex:0];
        [encoder setFragmentBuffer:_mouseBuffer offset:0 atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder endEncoding];
    }
#endif
    
    // Present
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];

    _frameAllocator->switchToNextBufferInRing();
    
    // Always `false` in the case of this sample
    if (waitForCompletion)
    {
        [commandBuffer waitUntilCompleted];
    }
}

-(void) DrawableSizeWillChange:(CGSize) size;
{
    assert (_gBufferPassDesc != nil);
#if TARGET_OS_OSX
    assert (_gBufferWithLoadPassDesc != nil);
#endif

    if (   _gBuffer0 != nil
        && _gBuffer0.width == size.width
        && _gBuffer0.height == size.height)
        return;
    
    // Recreate textures
    MTLTextureDescriptor* texDesc =
    [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:BufferFormats::gBuffer0Format
                                                       width:size.width
                                                      height:size.height
                                                   mipmapped:false];
    texDesc.usage       |= MTLTextureUsageRenderTarget;
    texDesc.sampleCount = BufferFormats::sampleCount;
#if TARGET_OS_IOS
    texDesc.storageMode = MTLStorageModeMemoryless;
#else
    texDesc.storageMode = MTLStorageModePrivate;
#endif
    _gBuffer0           = [_device newTextureWithDescriptor:texDesc];
    texDesc.pixelFormat = BufferFormats::gBuffer1Format;
    _gBuffer1           = [_device newTextureWithDescriptor:texDesc];
#if TARGET_OS_IOS
    texDesc.pixelFormat = BufferFormats::gBufferDepthFormat;
    _gBufferDepth       = [_device newTextureWithDescriptor:texDesc];
#endif
    
    // We reset the storage mode to private in case it was different on iOS
    texDesc.storageMode = MTLStorageModePrivate;
    texDesc.pixelFormat = BufferFormats::depthFormat;
    _depth              = [_device newTextureWithDescriptor:texDesc];
    
    // Update texture pointers in pass descriptors
    _gBufferPassDesc.depthAttachment.texture                = _depth;
    _debugPassDesc.depthAttachment.texture                  = _depth;
    _gBufferPassDesc.colorAttachments[0].texture            = _gBuffer0;
    _gBufferPassDesc.colorAttachments[1].texture            = _gBuffer1;
#if TARGET_OS_IOS
    _gBufferPassDesc.colorAttachments[3].texture            = _gBufferDepth;
#else
    _gBufferWithLoadPassDesc.depthAttachment.texture        = _depth;
    _gBufferWithLoadPassDesc.colorAttachments[0].texture    = _gBuffer0;
    _gBufferWithLoadPassDesc.colorAttachments[1].texture    = _gBuffer1;
#endif
    
    // Update the camera
    _camera.aspectRatio = size.width / (float)size.height;
}

-(void) SwapIsDebugRendererEnabled
{
    _debugPassIsEnabled = !_debugPassIsEnabled;
}

@end
