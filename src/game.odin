package main

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:slice"

import sdl "vendor:sdl3"
import im "shared:imgui"

Vertex_Data :: struct {
    pos: Vec3,
    color: sdl.FColor,
    uv: Vec2,
    normal: Vec3,
}

Model_Id :: distinct int
Entity :: struct {
    model_id: Model_Id,
    position: Vec3,
    rotation: Quat,
}

Mesh :: struct {
    vertex_buf: ^sdl.GPUBuffer,
    index_buf: ^sdl.GPUBuffer,
    num_indices: u32,
}

Model :: struct {
    mesh: Mesh,
    material: Material,
}

Material :: struct {
    diffuse_texture: ^sdl.GPUTexture,
    specular_color: Vec3,
    specular_shininess: f32,
    address_mode: sdl.TextureAddressMode,
}

// NOTE: Data must be aligned
UBO_Vertex_Global :: struct #packed {
    view_projection_mat: Mat4,
    inv_view_mat: Mat4,
    inv_projection_mat: Mat4,
}

UBO_Vertex_Local :: struct #packed {
    model_mat: Mat4,
    normal_mat: Mat4,
    scale: f32,
}

UBO_Fragment_Global :: struct #packed {
    lightPosition : Vec3,
    _ :f32, // Need 4 bytes padding to align the previous 12-byte value to the 16byte "page"
    lightColor : Vec3,
    lightIntensity : f32,
    viewPosition: Vec3,
    _ :f32, // Need 4 bytes padding to align the previous 12-byte value to the 16byte "page"
    ambientLightColor: Vec3,
}

UBO_Fragment_Local :: struct #packed {
    material_specular_color: Vec3,
    material_specular_shininess: f32,
}

Scene_State :: struct {
    initialised : bool,

    // NOTE: usually these are apparently "per-material"
    entity_pipeline : ^sdl.GPUGraphicsPipeline,

    light_shape_pipeline : ^sdl.GPUGraphicsPipeline,
    light_shape_mesh: Mesh,

    default_sampler : ^sdl.GPUSampler,

    ui_input_mode: bool, 
    camera : struct {
        position: Vec3,
        target: Vec3,
    },
    look : struct {
        yaw: f32,
        pitch: f32,
    },
    
    rotate: bool,

    models: []Model,
    entities: []Entity,

    light_position : Vec3,
    light_color : Vec3,
    light_intensity : f32,
    ambient_light_color: Vec3,

    skybox_multi_texture: ^sdl.GPUTexture,
    skybox_texture: ^sdl.GPUTexture,
    skybox_pipeline : ^sdl.GPUGraphicsPipeline,

    skybox_use_multi_image: bool,
}

EYE_HEIGHT :: 1
MOVE_SPEED :: 0.1
LOOK_SENSITIVITY :: 0.01
ROTATION_SPEED :: f32(90) * linalg.RAD_PER_DEG

game_init :: proc() {
    init_scene()
}

game_update :: proc(delta_time: f32) {
    update_scene(delta_time)
}

update_camera :: proc(dt: f32) {
    // get move input
    move_input : Vec2
    if g.key_down[.W] do move_input.y = 1
    else if g.key_down[.S] do move_input.y =-1

    if g.key_down[.A] do move_input.x = -1
    else if g.key_down[.D] do move_input.x = 1

    // get look input + update
    look_input := g.mouse_move + LOOK_SENSITIVITY
    g.look.yaw = math.wrap(g.look.yaw - g.mouse_move.x, 360)
    g.look.pitch = math.clamp(g.look.pitch - g.mouse_move.y, -89, 89) // use quaternions if we need to go beyond 89...

    look_mat := linalg.matrix3_from_yaw_pitch_roll_f32(linalg.to_radians(g.look.yaw), linalg.to_radians(g.look.pitch), 0)

    // calc dir
    forward := look_mat * Vec3 { 0, 0, -1 }
    right := look_mat * Vec3 { 1, 0, 0 }
    move_dir := forward * move_input.y + right * move_input.x

    // calc motion
    motion := linalg.normalize0( move_dir * MOVE_SPEED * dt )

    // apply motion
    g.camera.position += motion

    // update lookat target
    g.camera.target = g.camera.position + forward
}

game_render :: proc(cmd_buf: ^sdl.GPUCommandBuffer, swapchain_tex: ^sdl.GPUTexture) {
    switch g.current_scene {
        case .None:
            break;
        case .Main:
            render_scene(cmd_buf, swapchain_tex)
    }
}

Pipeline_Create :: struct {
    vertex_shader: string,
    vertex_attrs: []sdl.GPUVertexAttribute, 
    fragment_shader: string, 
    primitive_type: sdl.GPUPrimitiveType,               // .TRIANGLELIST
    depth_texture_format: sdl.GPUTextureFormat, 
    depth_stencil_compare: sdl.GPUCompareOp, 
    swapchain_texture_format: sdl.GPUTextureFormat
}



get_pipeline :: proc( pc: Pipeline_Create ) -> ^sdl.GPUGraphicsPipeline {
    vert_shader := load_shader(g.gpu, pc.vertex_shader)
    frag_shader := load_shader(g.gpu, pc.fragment_shader)  
    defer {
        sdl.ReleaseGPUShader(g.gpu, vert_shader)
        sdl.ReleaseGPUShader(g.gpu, frag_shader)
    }

    pci : sdl.GPUGraphicsPipelineCreateInfo = {
        vertex_shader = vert_shader,
        fragment_shader = frag_shader,
		primitive_type = pc.primitive_type,
        rasterizer_state = {
			cull_mode = .BACK,
		},
		depth_stencil_state = {
			enable_depth_test = true,
			enable_depth_write = true,
			compare_op = pc.depth_stencil_compare,
		},
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = &(sdl.GPUColorTargetDescription {
				format = pc.swapchain_texture_format,
			}),
			has_depth_stencil_target = true,
			depth_stencil_format = pc.depth_texture_format,
		}
    }

    if pc.vertex_attrs != nil {
        pci.vertex_input_state = {
            num_vertex_buffers = 1,
			vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
				slot = 0,
				pitch = size_of(Vertex_Data),
			}),
			num_vertex_attributes = u32(len(pc.vertex_attrs)),
			vertex_attributes = raw_data(pc.vertex_attrs)
        }
    }
    
    return sdl.CreateGPUGraphicsPipeline(g.gpu, pci)
}
