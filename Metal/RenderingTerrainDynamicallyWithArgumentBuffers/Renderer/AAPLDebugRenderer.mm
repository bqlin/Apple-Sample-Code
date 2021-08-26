/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the Debug Renderer
*/

#import "AAPLDebugRenderer.h"
#import "AAPLBufferFormats.h"
using namespace simd;

const int kDebugVertexCount = 1024 * 32;

@implementation AAPLDebugLine

+(nullable instancetype)      lineFrom:(float3)from
                                    to:(float3)to
                                 color:(float4)color
{
    AAPLDebugLine* d = [[AAPLDebugLine alloc] init];
    d.from = from;
    d.to = to;
    d.color = color;
    return d;
}

@end

@implementation AAPLDebugRenderer
{
    AAPLGpuBuffer<AAPLDebugVertex>                      _vertexBuffer;
    id <MTLRenderPipelineState>                         _pipelineState;
    NSMutableArray<AAPLDebugLine*>*                     _lines;
}

-(nullable instancetype) initWithDevice:(nonnull id<MTLDevice>) device
                                library:(id <MTLLibrary>) library
                              allocator:(nonnull AAPLAllocator*) allocator
{
    self = [super init];
    _vertexBuffer = allocator->allocBuffer<AAPLDebugVertex>(kDebugVertexCount);
    _lines = [NSMutableArray array];
    NSError* error;
    MTLRenderPipelineDescriptor *pipelineStateDescriptor    = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label                           = @"DebugRender";
    pipelineStateDescriptor.vertexFunction                  = [library newFunctionWithName:@"debugVertexShader"];
    pipelineStateDescriptor.fragmentFunction                = [library newFunctionWithName:@"debugFragmentShader"];
    pipelineStateDescriptor.depthAttachmentPixelFormat      = BufferFormats::depthFormat;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = BufferFormats::backBufferformat;
    assert (pipelineStateDescriptor.vertexFunction != nil);
    assert (pipelineStateDescriptor.fragmentFunction != nil);
    
    _pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                            error:&error];
    if (!_pipelineState) { NSLog(@"Failed to create pipeline state, error %@", error); }
    
    return self;
}

- (void)drawWithEncoder:(nonnull id <MTLRenderCommandEncoder>)renderEncoder
                 camera:(const AAPLCamera*)camera
         globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms;

{
    AAPLDebugVertex* dv = new AAPLDebugVertex[kDebugVertexCount];
    
    uint p = 0;
    for (AAPLDebugLine* line in _lines)
    {
        static_assert (kDebugVertexCount > 2, "");
        if (p >= kDebugVertexCount-2) break;
        
        dv[p].color = line.color;
        dv[p++].position = (float4) { line.to.x, line.to.y, line.to.z, 1.0f};
        dv[p].color = line.color;
        dv[p++].position = (float4) { line.from.x, line.from.y, line.from.z, 1.0f};
    }
    _vertexBuffer.fillInWith(dv, p);
    
    [renderEncoder setRenderPipelineState:_pipelineState];
    [renderEncoder setVertexBuffer:globalUniforms.getBuffer() offset:globalUniforms.getOffset() atIndex:1];
    [renderEncoder setVertexBuffer:_vertexBuffer.getBuffer() offset:_vertexBuffer.getOffset() atIndex:0];
    [renderEncoder setFragmentBuffer:globalUniforms.getBuffer() offset:globalUniforms.getOffset() atIndex:0];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:p];
    
    [_lines removeAllObjects];
    
    delete[] dv;
}

- (void) drawLineFrom:(float3)pos0
                   to: (float3)pos1
                   color: (float4)color
{
    if ([_lines count] > kDebugVertexCount/2) return;
    
    AAPLDebugLine* line = [AAPLDebugLine lineFrom:pos0 to: pos1 color:color ];
    [_lines addObject:line];
}

- (void) drawDiscAt:(float3) position
             normal:(float3) normal
             radius:(float) radius
              color:(float4) color
{
    constexpr uint segments = 8;
    float2 prev = float2 {0,radius};
    float3 basisu = normalize(cross(normal, normal.x == 0 ? (float3) {1,0,0} : (float3) {0,1,0} ));
    float3 basisv = cross(basisu, normal);
    
    for (uint f = 1; f < segments + 1; f++)
    {
        float ff = float(f) * 6.282f / float(segments);
        float2 curr = (float2) { sin(ff), cos(ff) } * radius;
        [self drawLineFrom:position + prev.x * basisu + prev.y * basisv to:position + curr.x * basisu + curr.y * basisv color:color];
        prev = curr;
    }
}

- (void) drawPlane:(float4) planeEquation
           atPoint:(float3) point
              size:(float) size
             color:(float4) color

{
    float3 plane_point = point - (planeEquation.xyz) * (planeEquation.w + dot(point, planeEquation.xyz));
    [self drawLineFrom:plane_point to:point color:color];
    [self drawDiscAt:plane_point normal:planeEquation.xyz radius:size color:color];
    
}

- (void) drawBoxWithTransform:(float4x4) matrix
{
    float3 corners[3][3][3];
    for (uint u = 0; u < 3; u++)
    for (uint v = 0; v < 3; v++)
    for (uint w = 0; w < 3; w++)
    {
        float4 p = simd_mul(matrix, (float4) { -1.0f + float(u), -1.0f + float(v), -1.0f + float(w), 1.0f});
        corners[u][v][w] = p.xyz / p.w;
    }
    

    // Three "rings" on z axis
    for (uint r = 0; r < 3; r++)
    {
        float c0 = r == 1 ? 1.0 : 0.0f;
        [self drawLineFrom:corners[0][0][r] to:corners[0][2][r] color:(float4) {0,0,c0,1}];
        [self drawLineFrom:corners[0][2][r] to:corners[2][2][r] color:(float4) {0,0,c0,1}];
        [self drawLineFrom:corners[2][2][r] to:corners[2][0][r] color:(float4) {0,0,c0,1}];
        [self drawLineFrom:corners[2][0][r] to:corners[0][0][r] color:(float4) {0,0,c0,1}];
    }
    
    // Spokes with the z axis
    [self drawLineFrom:corners[0][0][0] to:corners[0][0][2] color:(float4) {0,0,0,1}];
    [self drawLineFrom:corners[0][2][0] to:corners[0][2][2] color:(float4) {0,0,0,1}];
    [self drawLineFrom:corners[2][2][0] to:corners[2][2][2] color:(float4) {0,0,0,1}];
    [self drawLineFrom:corners[2][0][0] to:corners[2][0][2] color:(float4) {0,0,0,1}];
    
    // The x ring
    [self drawLineFrom:corners[1][0][0] to:corners[1][0][2] color:(float4) {1,0,0,1}];
    [self drawLineFrom:corners[1][0][2] to:corners[1][2][2] color:(float4) {1,0,0,1}];
    [self drawLineFrom:corners[1][2][2] to:corners[1][2][0] color:(float4) {1,0,0,1}];
    [self drawLineFrom:corners[1][2][0] to:corners[1][0][0] color:(float4) {1,0,0,1}];

    // The y ring
    [self drawLineFrom:corners[0][1][0] to:corners[0][1][2] color:(float4) {0,1,0,1}];
    [self drawLineFrom:corners[0][1][2] to:corners[2][1][2] color:(float4) {0,1,0,1}];
    [self drawLineFrom:corners[2][1][2] to:corners[2][1][0] color:(float4) {0,1,0,1}];
    [self drawLineFrom:corners[2][1][0] to:corners[0][1][0] color:(float4) {0,1,0,1}];

}

- (void) drawSphereWithCenter:(float3)center
                       radius:(float)radius
                        color: (float4)color
{
    const uint kSpokes = 8;
    const uint kSlices = 8;
    const float kSpokeRad = M_PI / float(kSpokes) * 2.0f;
    const float kSliceRad = M_PI / float(kSlices+1);
    
    for (uint sp = 0; sp < kSpokes; sp++)
    {
        float2 h_axis0 = (float2) { cosf(float(sp) * kSpokeRad), sinf(float(sp) * kSpokeRad) };
        float2 h_axis1 = (float2) { cosf(float(sp+1) * kSpokeRad), sinf(float(sp+1) * kSpokeRad) };
        
        for (uint sl = 0; sl <= kSlices; sl++)
        {
            float2 v_axis0 = (float2) { cosf(float(sl+0) * kSliceRad), sinf(float(sl+0) * kSliceRad) };
            float2 v_axis1 = (float2) { cosf(float(sl+1) * kSliceRad), sinf(float(sl+1) * kSliceRad) };
            
            [self drawLineFrom: center + (float3) { h_axis0.x * v_axis0.y, v_axis0.x, h_axis0.y * v_axis0.y } * radius
                            to: center + (float3) { h_axis1.x * v_axis0.y, v_axis0.x, h_axis1.y * v_axis0.y } * radius color: (float4)color];
            
            [self drawLineFrom: center + (float3) { h_axis0.x * v_axis0.y, v_axis0.x, h_axis0.y * v_axis0.y } * radius
                            to: center + (float3) { h_axis0.x * v_axis1.y, v_axis1.x, h_axis0.y * v_axis1.y } * radius color: (float4)color];
        }
    }
    
}

@end
