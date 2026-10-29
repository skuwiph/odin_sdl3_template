package main

import "core:mem"
import "core:slice"
import sdl "vendor:sdl3"

upload_mesh :: proc(copy_pass: ^sdl.GPUCopyPass, vertices: []$T, indices: []$S) -> Mesh {
    return upload_mesh_bytes(
        copy_pass,
        slice.to_bytes(vertices),
        slice.to_bytes(indices),
        len(indices)
    )
}

upload_mesh_bytes :: proc(copy_pass: ^sdl.GPUCopyPass, vertices: []byte, indices: []byte, num_indices: int) -> Mesh {
    vertices_byte_size := len(vertices)
    indices_byte_size := len(indices)


    vertex_buf := sdl.CreateGPUBuffer(g.gpu, {
        usage = {.VERTEX},
        size = u32(vertices_byte_size),
    })
    index_buf := sdl.CreateGPUBuffer(g.gpu, {
        usage = {.INDEX},
        size = u32(indices_byte_size),
    })

    // Upload vertex data to the buffer
    transfer_buf := sdl.CreateGPUTransferBuffer(g.gpu, {
        usage = .UPLOAD,
        size = u32(vertices_byte_size + indices_byte_size),       
    })

    // Map memory from CPU to GPU
    transfer_mem := transmute([^]byte) sdl.MapGPUTransferBuffer(g.gpu, transfer_buf, false)
    mem.copy(transfer_mem, raw_data(vertices), vertices_byte_size)
    mem.copy(transfer_mem[vertices_byte_size:], raw_data(indices), indices_byte_size)
    sdl.UnmapGPUTransferBuffer(g.gpu, transfer_buf)
    
    sdl.UploadToGPUBuffer(
        copy_pass, 
        {transfer_buffer = transfer_buf},
        {buffer = vertex_buf, size = u32(vertices_byte_size)},
        false
    )
    sdl.UploadToGPUBuffer(
        copy_pass, 
        {
            transfer_buffer = transfer_buf, 
            offset = u32(vertices_byte_size)
        },
        {buffer = index_buf, size = u32(indices_byte_size)},
        false
    )
    
    sdl.ReleaseGPUTransferBuffer(g.gpu, transfer_buf)

    return {
        vertex_buf = vertex_buf,
        index_buf = index_buf,
        num_indices = u32(num_indices)
    }
}