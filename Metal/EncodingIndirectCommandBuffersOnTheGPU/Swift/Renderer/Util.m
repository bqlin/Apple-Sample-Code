    //
    // Created by Bq Lin on 2021/8/28.
    // Copyright © 2021 Bq. All rights reserved.
    //

#import "Util.h"
#import "AAPLShaderTypes.h"

@implementation Util

typedef struct AAPLObjectMesh {
    AAPLVertex *vertices;
    uint32_t numVerts;
} AAPLObjectMesh;


+ (id<MTLBuffer>)makeVertexBufferAndInfo:(NSMutableArray *)info device:(id<MTLDevice>)device {
    AAPLObjectMesh *tempMeshes;
    {
        tempMeshes = malloc(sizeof(AAPLObjectMesh)*AAPLNumObjects);
        
        for(int objectIdx = 0; objectIdx < AAPLNumObjects; objectIdx++)
        {
            // Choose the parameters to generate a mesh so that each one is unique.
            // uint32_t numTeeth = random() % 50 + 3;
            // float innerRatio = 0.2 + (random() / (1.0 * RAND_MAX)) * 0.7;
            // float toothWidth = 0.1 + (random() / (1.0 * RAND_MAX)) * 0.4;
            // float toothSlope = (random() / (1.0 * RAND_MAX)) * 0.2;
            uint32_t numTeeth = objectIdx % 50 + 3;
            float innerRatio = 0.8;
            float toothWidth = 0.25;
            float toothSlope = 0.2;
            
                // Create a vertex buffer and initialize it with a unique 2D gear mesh.
            tempMeshes[objectIdx] = [self newGearMeshWithNumTeeth:numTeeth
                                                       innerRatio:innerRatio
                                                       toothWidth:toothWidth
                                                       toothSlope:toothSlope];
            [info addObject:@(tempMeshes[objectIdx].numVerts)];
        }
    }
    
    id<MTLBuffer> vertexBuffer;
    {
        size_t bufferSize = 0;
        for(int objectIdx = 0; objectIdx < AAPLNumObjects; objectIdx++)
        {
            size_t meshSize = sizeof(AAPLVertex) * tempMeshes[objectIdx].numVerts;
            bufferSize += meshSize;
        }
        
        vertexBuffer = [device newBufferWithLength:bufferSize options:0];
        vertexBuffer.label = @"Combined Vertex Buffer";
    }
    
    {
        uint32_t currentStartVertex = 0;
        for(int objectIdx = 0; objectIdx < AAPLNumObjects; objectIdx++)
        {
            size_t meshSize = sizeof(AAPLVertex) * tempMeshes[objectIdx].numVerts;
            AAPLVertex* meshStartAddress = ((AAPLVertex*)vertexBuffer.contents) + currentStartVertex;
            memcpy(meshStartAddress, tempMeshes[objectIdx].vertices, meshSize);
            currentStartVertex += tempMeshes[objectIdx].numVerts;
            free(tempMeshes[objectIdx].vertices);
        }
    }
    
    free(tempMeshes);
    return vertexBuffer;
}

+ (AAPLObjectMesh)newGearMeshWithNumTeeth:(uint32_t)numTeeth
                               innerRatio:(float)innerRatio
                               toothWidth:(float)toothWidth
                               toothSlope:(float)toothSlope
{
    NSAssert(numTeeth >= 3, @"Can only build a gear with at least 3 teeth");
    NSAssert(toothWidth + 2 * toothSlope < 1.0, @"Configuration of gear invalid");
    
    AAPLObjectMesh mesh;
    
    uint32_t numVertices = numTeeth * 12;
    uint32_t bufferSize = sizeof(AAPLVertex) * numVertices;
    
    mesh.numVerts = numVertices;
    mesh.vertices = (AAPLVertex*)malloc(bufferSize);
    
    const double angle = 2.0*M_PI/(double)numTeeth;
    static const packed_float2 origin = (packed_float2){0.0, 0.0};
    uint32_t vtx = 0;
    
    for(int tooth = 0; tooth < numTeeth; tooth++)
    {
        const float toothStartAngle = tooth * angle;
        const float toothTip1Angle  = (tooth+toothSlope) * angle;
        const float toothTip2Angle  = (tooth+toothSlope+toothWidth) * angle;;
        const float toothEndAngle   = (tooth+2*toothSlope+toothWidth) * angle;
        const float nextToothAngle  = (tooth+1.0) * angle;
        
        const packed_float2 groove1    = { sin(toothStartAngle)*innerRatio, cos(toothStartAngle)*innerRatio };
        const packed_float2 tip1       = { sin(toothTip1Angle), cos(toothTip1Angle) };
        const packed_float2 tip2       = { sin(toothTip2Angle), cos(toothTip2Angle) };
        const packed_float2 groove2    = { sin(toothEndAngle)*innerRatio, cos(toothEndAngle)*innerRatio };
        const packed_float2 nextGroove = { sin(nextToothAngle)*innerRatio, cos(nextToothAngle)*innerRatio };
        
        // Right top triangle of tooth
        mesh.vertices[vtx].position = groove1;
        mesh.vertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;
        
        mesh.vertices[vtx].position = tip1;
        mesh.vertices[vtx].texcoord = (tip1 + 1.0) / 2.0;
        vtx++;
        
        mesh.vertices[vtx].position = tip2;
        mesh.vertices[vtx].texcoord = (tip2 + 1.0) / 2.0;
        vtx++;
        
        // Left bottom triangle of tooth
        mesh.vertices[vtx].position = groove1;
        mesh.vertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;
        
        mesh.vertices[vtx].position = tip2;
        mesh.vertices[vtx].texcoord = (tip2 + 1.0) / 2.0;
        vtx++;
        
        mesh.vertices[vtx].position = groove2;
        mesh.vertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;
        
        // Slice of circle from bottom of tooth to center of gear
        mesh.vertices[vtx].position = origin;
        mesh.vertices[vtx].texcoord = (origin + 1.0) / 2.0;
        vtx++;
        
        mesh.vertices[vtx].position = groove1;
        mesh.vertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;
        
        mesh.vertices[vtx].position = groove2;
        mesh.vertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;
        
        // Slice of circle from the groove to the center of gear
        mesh.vertices[vtx].position = origin;
        mesh.vertices[vtx].texcoord = (origin + 1.0) / 2.0;
        vtx++;
        
        mesh.vertices[vtx].position = groove2;
        mesh.vertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;
        
        mesh.vertices[vtx].position = nextGroove;
        mesh.vertices[vtx].texcoord = (nextGroove + 1.0) / 2.0;
        vtx++;
    }
    
    return mesh;
}

@end
