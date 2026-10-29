package main

import "core:log"
import "core:math/linalg"
import "core:mem"
import "core:slice"
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
    if texture != nil do log.debugf("Loaded texture with dims {}x{}", texture_w, texture_h)

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
			color = linalg.pow(sdl.FColor { 1, 1, 1, 1 }, 2.2),
			uv = {uv.x, 1-uv.y},
		}
		indices[i] = u16(i)
	}

    obj_destroy(obj_data)

    mesh := upload_mesh(copy_pass, vertices, indices)

    delete(indices)
    delete(vertices)

    return mesh
}