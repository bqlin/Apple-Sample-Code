/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation for a simple class that represents a colored triangle object.
*/

#import "AAPLTriangle.h"

@implementation AAPLTriangle

/// Returns the vertices of one triangle.
/// The default position is centered at the origin.
/// The default color is white.
+(const AAPLVertex *)vertices
{
    const float TriangleSize = 64;
    static const AAPLVertex triangleVertices[] =
    {
        // Pixel Positions,                          RGBA colors.
        { { -0.5*TriangleSize, -0.5*TriangleSize },  { 1, 1, 1, 1 } },
        { {  0.0*TriangleSize, +0.5*TriangleSize },  { 1, 1, 1, 1 } },
        { { +0.5*TriangleSize, -0.5*TriangleSize },  { 1, 1, 1, 1 } }
    };
    return triangleVertices;
}

/// Returns the number of vertices for each triangle.
+(const NSUInteger)vertexCount
{
    return 3;
}

@end
