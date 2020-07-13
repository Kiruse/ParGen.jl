#version 330 core

in vec4 vecColor;
in vec2 vecUv;
out vec4 outColor;

uniform sampler2D texDiffuse;

void main()
{
    outColor = vecColor * texture(texDiffuse, vecUv);
}
