attribute vec4 inPosition;
attribute vec4 inTexcoord;
varying vec2 varTexcoord;
varying vec2 varPosition;

void main()
{
    gl_Position = inPosition;
    varTexcoord = inTexcoord.xy;
    varPosition = inPosition.xy * 0.5 + 0.5;
}
