struct FragmentInput {
    @location(0) tex_coord: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) @interpolate(flat) texture_index: u32,
}

@group(0) @binding(0) var textures: binding_array<texture_2d<f32>, 4096>;
@group(0) @binding(1) var tex_sampler: sampler;

@fragment
fn fs_main(input: FragmentInput) -> @location(0) vec4<f32> {
    let tex_color = textureSample(
        textures[input.texture_index],
        tex_sampler,
        input.tex_coord,
    );

    return vec4<f32>(
        tex_color.rgb * input.color.rgb,
        tex_color.a * input.color.a,
    );
}
