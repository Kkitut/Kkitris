struct PushConstants {
    transform: mat4x4<f32>,
}

var<immediate> pc: PushConstants;

struct VertexInput {
    @location(0) color: vec4<f32>,
    @location(1) position: vec2<f32>,
    @location(2) scale: vec2<f32>,
    @location(3) rotation: f32,
    @location(4) texture_index: u32,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) tex_coord: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) @interpolate(flat) texture_index: u32,
}

@vertex
fn vs_main(
    input: VertexInput,
    @builtin(vertex_index) vertex_index: u32,
) -> VertexOutput {
    var output: VertexOutput;

    let positions: array<vec2<f32>, 6> = array<vec2<f32>, 6>(
        vec2<f32>(-0.5, -0.5),
        vec2<f32>(0.5, -0.5),
        vec2<f32>(0.5, 0.5),
        vec2<f32>(0.5, 0.5),
        vec2<f32>(-0.5, 0.5),
        vec2<f32>(-0.5, -0.5),
    );

    let uvs: array<vec2<f32>, 6> = array<vec2<f32>, 6>(
        vec2<f32>(0.0, 0.0),
        vec2<f32>(1.0, 0.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(0.0, 1.0),
        vec2<f32>(0.0, 0.0),
    );

    var position = positions[vertex_index] * input.scale;

    let sin_r = sin(input.rotation);
    let cos_r = cos(input.rotation);

    position = vec2<f32>(
        position.x * cos_r - position.y * sin_r,
        position.x * sin_r + position.y * cos_r,
    );

    position += input.position;

    output.clip_position = pc.transform * vec4<f32>(position, 0.0, 1.0);
    output.tex_coord = uvs[vertex_index];
    output.color = input.color;
    output.texture_index = input.texture_index;

    return output;
}
