/*
 <codex>
 <abstract>Vertex shader.</abstract>
 </codex>
 */

attribute vec4 position;
attribute mediump vec4 texturecoordinate;

uniform mat4 amodelview;
uniform mat4 aprojection;

varying mediump vec2 coordinate;

void main()
{
    gl_Position = aprojection * amodelview * position;
	coordinate = texturecoordinate.xy;
}
