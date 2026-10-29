package main

import "core:log"
import sdl "vendor:sdl3"

CONTENT_DIR :: "content"

Vec3 :: [3]f32
Vec2 :: [2]f32
Mat4 :: matrix[4,4]f32
Quat :: quaternion128

Globals :: struct {
    gpu : ^sdl.GPUDevice,
    window : ^sdl.Window,
    window_size : [2]i32,
    pipeline : ^sdl.GPUGraphicsPipeline,
    sampler : ^sdl.GPUSampler,
    depth_texture: ^sdl.GPUTexture,
    depth_texture_format: sdl.GPUTextureFormat,
    swapchain_texture_format: sdl.GPUTextureFormat,
    camera : struct {
        position: Vec3,
        target: Vec3,
    },
    look : struct {
        yaw: f32,
        pitch: f32,
    },
    key_down : #sparse [sdl.Scancode]bool,
    mouse_move : Vec2,
    ui_input_mode: bool, 
    
    clear_color: sdl.FColor,
    rotate: bool,

    models: []Model,
    entities: []Entity,
}

sdl_assert :: proc(ok: bool) {
    if !ok do log.panicf("SDL Error: {}", sdl.GetError())
}