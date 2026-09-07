#version 450

#extension GL_EXT_nonuniform_qualifier : require

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec4 fragColor;
layout(location = 2) flat in uint fragTextureIndex;

layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D textures[];

void main() {
    vec4 texColor = texture(
        textures[nonuniformEXT(fragTextureIndex)],
        fragTexCoord
    );

    outColor = vec4(
        texColor.rgb * fragColor.rgb,
        texColor.a * fragColor.a
    );
}