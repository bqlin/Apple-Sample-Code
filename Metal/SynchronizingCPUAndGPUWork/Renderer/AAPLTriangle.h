/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for a simple class that represents a colored triangle object.
*/

@import MetalKit;
#import "AAPLShaderTypes.h"

@interface AAPLTriangle : NSObject

@property (nonatomic) vector_float2 position;
@property (nonatomic) vector_float4 color;

+(const AAPLVertex*)vertices;
+(NSUInteger)vertexCount;

@end
