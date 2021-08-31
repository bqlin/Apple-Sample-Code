/*
 <samplecode>
 <abstract>
 OpenGL fragment shader used to sample from a 2D texture
 </abstract>
 </samplecode>
 */


#ifdef GL_ES
precision highp float;
#endif

// Declare inputs and outputs
// varTexcoord : TexCoord for the fragment computed by the rasterizer based on
//               the varTexcoord values output in the vertex shader.
// gl_FragColor : Implicitly declare in fragments shaders less than 1.40.
//                Output color of our fragment.
// fragColor : Output color of our fragment.  Basically the same as gl_FragColor,
//             but we must explicitly declared this in shaders version 1.40 and
//             above.

#if __VERSION__ >= 140
in vec2      varTexcoord;
out vec4     fragColor;
#else
varying vec2 varTexcoord;
#endif

uniform sampler2D baseMap;
uniform sampler2D labelMap;

void main (void)
{
    #if __VERSION__ >= 140
    vec4 baseColor = texture(baseMap, varTexcoord.st, 0.0);
    vec4 labelColor = texture(labelMap, varTexcoord.st, 0.0);
    fragColor = (baseColor * (1.0 - labelColor.w)) + (labelColor * labelColor.w);
    #else
    vec4 baseColor = texture2D(baseMap, varTexcoord.st, 0.0);
    vec4 labelColor  = texture2D(labelMap, varTexcoord.st, 0.0);
    gl_FragColor = (baseColor * (1.0 - labelColor.w)) + (labelColor * labelColor.w);
    #endif
}
