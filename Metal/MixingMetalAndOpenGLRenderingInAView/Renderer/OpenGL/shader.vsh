/*
 <samplecode>
 <abstract>
 OpenGL vertex shader used render a quad
 </abstract>
 </samplecode>
 */


#ifdef GL_ES
precision highp float;
#endif

uniform mat4 modelViewProjectionMatrix;

// Declare inputs and outputs
// inPosition : Position attributes from the VAO/VBOs
// inTexcoord : Texcoord attributes from the VAO/VBOs
// varTexcoord : TexCoord we'll pass to the rasterizer
// gl_Position : implicitly declared in all vertex shaders. Clip space position
//               passed to rasterizer used to build the triangles

#if __VERSION__ >= 140
in vec4  inPosition;
in vec2  inTexcoord;
out vec2 varTexcoord;
#else
attribute vec4 inPosition;
attribute vec2 inTexcoord;
varying vec2 varTexcoord;
#endif

void main (void)
{
    gl_Position = modelViewProjectionMatrix * inPosition;

    varTexcoord = inTexcoord;
}
