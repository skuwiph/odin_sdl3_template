package main

import "base:runtime"
import "core:log"
import "core:mem"
import "core:path/filepath"
import "core:strings"

import sdl "vendor:sdl3"
import sdli "vendor:sdl3/image"


load_texture_file :: proc(copy_pass: ^sdl.GPUCopyPass, texture_file: string) -> ^sdl.GPUTexture {
    // Texture loading and set up
    texture_path, _ := filepath.join({ CONTENT_DIR, "textures", texture_file }, context.temp_allocator)
    texture_file := strings.clone_to_cstring(texture_path, context.temp_allocator)

    texture_w := i32(0);
    texture_h := i32(0);
    texture := sdli.LoadGPUTexture(g.gpu, copy_pass, texture_file, &texture_w, &texture_h)
    if texture != nil do log.debugf("{}: Loaded texture with dims {}x{}", texture_file, texture_w, texture_h)

    return texture
}

load_cubemap_texture_single :: proc(copy_pass: ^sdl.GPUCopyPass, texture_file: string) -> ^sdl.GPUTexture {
    texture_path, _ := filepath.join({ CONTENT_DIR, "textures", texture_file }, context.temp_allocator)
    texture_file := strings.clone_to_cstring(texture_path, context.temp_allocator)
    surface := sdli.Load(texture_file)
    if surface == nil {
        log.errorf("Couldn't load {} - {}", texture_file, sdl.GetError())
        assert(false)
    }
    w := surface.w
    h := surface.h
    log.debugf("Skybox: Loaded image: {} of size {}x{}", texture_file, w, h)
    
    pixels := get_surface_bytes(surface)
    texture := upload_cubemap_texture_single(copy_pass, pixels, u32(w), u32(h))
    sdl.DestroySurface(surface)
    return texture
}

load_cubemap_texture_files :: proc(copy_pass: ^sdl.GPUCopyPass, texture_files: [sdl.GPUCubeMapFace]string) -> ^sdl.GPUTexture {
	pixels: [sdl.GPUCubeMapFace][]byte
	size: u32
	for texture_file, side in texture_files {
        texture_path, _ := filepath.join({ CONTENT_DIR, "textures", texture_file }, context.temp_allocator)
        surface_path := strings.clone_to_cstring(texture_path, context.temp_allocator)
        surface := sdli.Load(surface_path)
        if surface == nil {
            log.errorf("Couldn't load {} - {}", surface_path, sdl.GetError())
            return nil
        }
        w := u32(surface.w)
        h := u32(surface.h)
        log.debugf("Skybox: Loaded image: {} of size {}x{}", surface_path, w, h)
        
		//side_pixels, img_size := load_pixels(texture_file)
		pixels[side] = get_surface_bytes(surface)
		assert(w == h)
		if size == 0 {
			size = w
		} else {
			assert(w == size)
		}

        sdl.DestroySurface(surface)
	}

    log.debugf("skybox multi: Got {} pixels of size {}", len(pixels), size)

	texture := upload_cubemap_texture_sides(copy_pass, pixels, size)

	for side_pixels in pixels do delete(side_pixels)

	return texture
}

load_object_file:: proc(copy_pass: ^sdl.GPUCopyPass, mesh_file: string) -> Mesh {
    mesh_path, _    := filepath.join({ CONTENT_DIR, "meshes", mesh_file }, context.temp_allocator)   

    obj_data := obj_load(mesh_path)

    vertices := make([]Vertex_Data, len(obj_data.faces))
    indices := make([]u16, len(obj_data.faces))

	for face, i in obj_data.faces {
		uv := obj_data.uvs[face.uv]
		vertices[i] = {
			pos = obj_data.positions[face.pos],
			color = sdl.FColor { 1, 1, 1, 1 },
			uv = {uv.x, 1-uv.y},
            normal = obj_data.normals[face.normal],
		}
		indices[i] = u16(i)
	}

    obj_destroy(obj_data)

    mesh := upload_mesh(copy_pass, vertices, indices)

    delete(indices)
    delete(vertices)

    return mesh
}