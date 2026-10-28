package main

import "base:runtime"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:encoding/json"

import sdl "vendor:sdl3"

load_shader :: proc(device: ^sdl.GPUDevice, shaderfile: string) -> ^sdl.GPUShader {
    stage: sdl.GPUShaderStage

    switch filepath.ext(shaderfile) {
        case ".vert":
            stage = .VERTEX
        case ".frag":
            stage = .FRAGMENT
    }

    format: sdl.GPUShaderFormatFlag
    format_ext: string
	entrypoint: cstring = "main"

    supported_formats := sdl.GetGPUShaderFormats(g.gpu)
    log.debug(`Supported Formats: {}`, supported_formats)
    if .SPIRV in supported_formats {
        format = .SPIRV
        format_ext = ".spv"
    } else if .MSL in supported_formats {
        format = .MSL
        format_ext = ".msl"
		entrypoint = "main0"
    } else if .DXIL in supported_formats {
        format = .DXIL
        format_ext = ".dxil"
    } else {
        log.panicf("No supported shader format: {}", supported_formats)
    }

    shaderfile, _ := filepath.join({ CONTENT_DIR, "shaders", "out", shaderfile}, context.temp_allocator)

    filename := strings.concatenate({shaderfile, format_ext}, context.temp_allocator)
	code, err := os.read_entire_file_from_path(filename, context.temp_allocator)
    if err != nil {
        log.panicf("File {}: {}", filename, err)
    }

    log.debugf("Read {} bytes from {}", len(code), filename)

	info := load_shader_info(shaderfile)

    log.debugf("Shader Info: {}", info)

	return sdl.CreateGPUShader(device, {
		code_size = len(code),
		code = raw_data(code),
		entrypoint = entrypoint,
		format = {format},
		stage = stage,
		num_uniform_buffers = info.uniform_buffers,
		num_samplers = info.samplers,
		num_storage_buffers = info.storage_buffers,
		num_storage_textures = info.storage_textures,
	})
}

Shader_Info :: struct {
	samplers: u32,
	storage_textures: u32,
	storage_buffers: u32,
	uniform_buffers: u32,
}

load_shader_info :: proc(shaderfile: string) -> Shader_Info {
	json_filename := strings.concatenate({shaderfile, ".json"}, context.temp_allocator)
	json_data, err := os.read_entire_file_from_path(json_filename, context.temp_allocator); 
    if err != nil do log.errorf(`Couldn't read {}: {}`, json_filename, err)
	result: Shader_Info
	uerr := json.unmarshal(json_data, &result, allocator = context.temp_allocator); 
    if uerr != nil do log.errorf(`Couldn't unmarshall {}: {}`, json_filename, uerr)
	return result
}
