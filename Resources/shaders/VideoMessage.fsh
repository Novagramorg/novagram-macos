varying vec2 varTexcoord;
varying vec2 varPosition;
uniform sampler2D texture;
uniform sampler2D previousTexture;
uniform sampler2D watermarkTexture;
uniform sampler2D planeTexture;
uniform float opacity;
uniform float aspectRatio;
uniform float noMirror;
uniform float decorated;
uniform float planeFrame;
uniform float planeFrameCount;

vec4 sourceOver(vec4 overlay, vec4 background)
{
    return vec4(overlay.rgb + background.rgb * (1.0 - overlay.a), 1.0);
}

void main()
{
    vec2 texcoord = vec2(1.0 - varTexcoord.x * noMirror + clamp(noMirror, -1.0, 0.0), varTexcoord.y);
    vec2 prevTexcoord = vec2(texcoord.x, 1.0 - texcoord.y);
    
    vec4 color = texture2D(texture, texcoord);
    vec4 previousColor = texture2D(previousTexture, prevTexcoord);
    
    color.rgb = mix(color.rgb, previousColor.rgb, opacity);
    
    vec4 background = vec4(texture2D(texture, texcoord, 5.5).rgb * 0.25, 1.0);
    
    if (decorated > 0.5)
    {
        float watermarkSize = 0.25;
        vec2 watermarkOrigin = vec2(1.0 - watermarkSize);
        if (varPosition.x >= watermarkOrigin.x && varPosition.y >= watermarkOrigin.y)
        {
            background = sourceOver(texture2D(watermarkTexture, (varPosition - watermarkOrigin) / watermarkSize), background);
        }
        
        float planeSize = 0.17;
        vec2 planeOrigin = vec2(0.0, 1.0 - planeSize);
        if (varPosition.x < planeSize && varPosition.y >= planeOrigin.y)
        {
            vec2 planeCoordinate = (varPosition - planeOrigin) / planeSize;
            background = sourceOver(texture2D(planeTexture, vec2(planeCoordinate.x, (planeFrame + planeCoordinate.y) / planeFrameCount)), background);
        }
    }
    
    vec2 c = vec2((varTexcoord.x * 2.0 - 1.0) * aspectRatio, varTexcoord.y * 2.0 - 1.0) * 0.996;
    vec2 c1 = c - 0.005;
    vec2 c2 = c + 0.005;
    vec2 c3 = vec2(c1.x, c2.y);
    vec2 c4 = vec2(c2.x, c1.y);
    float s1 = step(1.0, dot(c1, c1));
    float s2 = step(1.0, dot(c2, c2));
    float s3 = step(1.0, dot(c3, c3));
    float s4 = step(1.0, dot(c4, c4));
    
    gl_FragColor = mix(color, background, (s1 + s2 + s3 + s4) * 0.25);
}
