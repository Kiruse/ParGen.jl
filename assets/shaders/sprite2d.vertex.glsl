#version 330 core

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 inUv;
out vec2 vecUv;

uniform mat3 uniScreenTransform;

void main()
{
    gl_Position = vec4(uniScreenTransform * vec3(inPosition, 1), 1);
    vecUv = inUv;
}
