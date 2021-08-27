/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders used for this sample
*/

#include <metal_stdlib>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#include "AAPLShaderTypes.h"

// This is the argument buffer that contains the ICB.
struct ICBContainer
{
    command_buffer commandBuffer [[ id(AAPLArgumentBufferIDCommandBuffer) ]];
};

// Check whether the object at 'objectIndex' is visible and set draw parameters if so.
// Otherwise, reset the command so that nothing is done.
kernel void
cullMeshesAndEncodeCommands(uint                         objectIndex   [[ thread_position_in_grid ]],
                            constant AAPLFrameState     *frame_state   [[ buffer(AAPLKernelBufferIndexFrameState) ]],
                            device AAPLObjectPerameters *object_params [[ buffer(AAPLKernelBufferIndexObjectParams)]],
                            device AAPLVertex           *vertices      [[ buffer(AAPLKernelBufferIndexVertices) ]],
                            device ICBContainer         *icb_container [[ buffer(AAPLKernelBufferIndexCommandBufferContainer) ]])
{
    float2 worldObjectPostion  = frame_state->translation + object_params[objectIndex].position;
    float2 clipObjectPosition  = frame_state->aspectScale * AAPLViewScale * worldObjectPostion;

    const float rightBounds =  1.0;
    const float leftBounds  = -1.0;
    const float upperBounds =  1.0;
    const float lowerBounds = -1.0;

    bool visible = true;

    // Set the bounding radius in the view space.
    const float2 boundingRadius = frame_state->aspectScale * AAPLViewScale * object_params[objectIndex].boundingRadius;

    // Check if the object's bounding circle has moved outside of the view bounds.
    if(clipObjectPosition.x + boundingRadius.x < leftBounds  ||
       clipObjectPosition.x - boundingRadius.x > rightBounds ||
       clipObjectPosition.y + boundingRadius.y < lowerBounds ||
       clipObjectPosition.y - boundingRadius.y > upperBounds)
    {
        visible = false;
    }
    // Get indirect render commnd object from the indirect command buffer given the object's unique
    // index to set parameters for drawing (or not drawing) the object.
    render_command cmd(icb_container->commandBuffer, objectIndex);

    if(visible)
    {
        // Set the buffers and add a draw command.
        cmd.set_vertex_buffer(frame_state, AAPLVertexBufferIndexFrameState);
        cmd.set_vertex_buffer(object_params, AAPLVertexBufferIndexObjectParams);
        cmd.set_vertex_buffer(vertices, AAPLVertexBufferIndexVertices);

        cmd.draw_primitives(primitive_type::triangle,
                            object_params[objectIndex].startVertex,
                            object_params[objectIndex].numVertices, 1,
                            objectIndex);
    }
    
    // If the object is not visible, no draw command will be set since so long as the app has reset
    // the indirect command buffer commands with a blit encoder before encoding the draw.
}

// Vertex shader outputs and per-fragment inputs.
struct RasterizerData
{
    float4 position [[position]];
    float2 tex_coord;
};

vertex RasterizerData
vertexShader(uint                     vertexID                [[ vertex_id ]],
             uint                     objectIndex             [[ instance_id ]],
             const device AAPLVertex* vertices                [[ buffer(AAPLVertexBufferIndexVertices) ]],
             const device AAPLObjectPerameters *object_params [[ buffer(AAPLVertexBufferIndexObjectParams) ]],
             constant AAPLFrameState* frame_state             [[ buffer(AAPLVertexBufferIndexFrameState) ]])
{
    RasterizerData out;

    float2 worldObjectPostion  = frame_state->translation + object_params[objectIndex].position;
    float2 modelVertexPosition = vertices[vertexID].position;
    float2 worldVertexPosition = modelVertexPosition + worldObjectPostion;
    float2 clipVertexPosition  = frame_state->aspectScale * AAPLViewScale * worldVertexPosition;

    out.position = float4(clipVertexPosition.x, clipVertexPosition.y, 0, 1);
    out.tex_coord = float2(vertices[vertexID].texcoord);

    return out;
}

fragment float4
fragmentShader(RasterizerData in [[ stage_in ]])
{
    float4 output_color = float4(in.tex_coord.x, in.tex_coord.y, 0, 1);

    return output_color;
}
