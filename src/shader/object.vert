#version 450

layout(location = 0) in vec4 inColor;
layout(location = 1) in vec2 inPosition;
layout(location = 2) in vec2 inScale;
layout(location = 3) in float inRotation;
layout(location = 4) in uint inTextureIndex;

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out vec4 fragColor;
layout(location = 2) flat out uint fragTextureIndex;

layout(push_constant) uniform PushConstants {
    mat4 transform;
} pc;

const vec2 POSITIONS[6] = vec2[](
    vec2(-0.5, -0.5),
    vec2( 0.5, -0.5),
    vec2( 0.5,  0.5),
    vec2( 0.5,  0.5),
    vec2(-0.5,  0.5),
    vec2(-0.5, -0.5)
);

const vec2 UVS[6] = vec2[](
    vec2(0.0, 0.0),
    vec2(1.0, 0.0),
    vec2(1.0, 1.0),
    vec2(1.0, 1.0),
    vec2(0.0, 1.0),
    vec2(0.0, 0.0)
);

void main() {
    vec2 position = POSITIONS[gl_VertexIndex] * inScale;

    float sin_r = sin(inRotation);
    float cos_r = cos(inRotation);

    position = vec2(
        position.x * cos_r - position.y * sin_r,
        position.x * sin_r + position.y * cos_r
    );

    position += inPosition;

    gl_Position = pc.transform * vec4(position, 0.0, 1.0);

    fragTexCoord = UVS[gl_VertexIndex];
    fragColor = inColor;
    fragTextureIndex = inTextureIndex;
}