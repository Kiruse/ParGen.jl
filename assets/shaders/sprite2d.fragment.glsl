#version 330 core

in vec2 vecUv;
out vec4 outColor;

uniform vec4 uniTaint;
uniform sampler2D texDiffuse;

void main()
{
    outColor = uniTaint * texture(texDiffuse, vecUv);
}
