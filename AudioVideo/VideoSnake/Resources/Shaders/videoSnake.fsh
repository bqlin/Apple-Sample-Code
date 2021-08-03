/*
 <codex>
 <abstract>Fragment shader.</abstract>
 </codex>
 */

precision mediump float;

varying mediump vec2 coordinate;
uniform sampler2D videoframe;
uniform mediump vec4 backgroundcolor;

void main()
{
    if (coordinate.x >= 0.99 || coordinate.x <= 0.01 ||
        coordinate.y >= 0.99 || coordinate.y <= 0.01)
    {
        gl_FragColor = backgroundcolor;
    }
    else
    {
        gl_FragColor = texture2D(videoframe, coordinate);
    }
}
