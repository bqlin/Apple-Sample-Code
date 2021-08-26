/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declaration of the AAPLObjLoader.
 This class manaully transforms attributes needed for the sample, such as vertex texture coordinates into vertex color.
*/

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import <vector>
#import <unordered_map>
#import <Metal/Metal.h>
#import "AAPLMainRenderer_shared.h"

// Hash function definition for the std::hash protocol to handle our ObjVertex as a hash key
template<> struct std::hash<AAPLObjVertex>
{
    std::size_t operator()(const AAPLObjVertex& k) const
    {
        std::size_t hash = 0;
        for (uint w = 0; w < sizeof(AAPLObjVertex) / sizeof(std::size_t); w++)
            hash ^= (((std::size_t*)&k)[w] ^ (hash << 8) ^ (hash >> 8));
        return hash;
    }
};

// A simple class containing our standardized OBJ geometry
@interface AAPLObjMesh : NSObject
    @property float          boundingRadius;
    @property id <MTLBuffer> vertexBuffer;
    @property id <MTLBuffer> indexBuffer;

-(NSUInteger) indexCount;
-(NSUInteger) vertexCount;
@end

// A small OBJ file loader that generates AAPLObjMesh objects for further use
@interface AAPLObjLoader : NSObject

-(instancetype) initWithDevice:(id<MTLDevice>) device;
-(AAPLObjMesh*) loadFromUrl:(NSURL*) inUrl;

@end
