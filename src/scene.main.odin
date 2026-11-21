package main
import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:slice"

import sdl "vendor:sdl3"
import im "shared:imgui"

init_scene :: proc() {
    log.debug("init_scene()")

    setup_entity_pipeline()
    setup_light_shape_pipeline()
    setup_skybox_pipeline()
    
    // Normally a property of materials
    g.default_sampler = sdl.CreateGPUSampler(g.gpu, {
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        address_mode_u = .REPEAT,
        address_mode_v = .REPEAT,
    })

    copy_cmd_buf := sdl.AcquireGPUCommandBuffer(g.gpu);
    copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)
    
    g.light_shape_mesh = generate_box_mesh(copy_pass, 0.5, 0.5, 0.5)

    g.skybox_multi_texture = load_cubemap_texture_files(copy_pass, {
        .POSITIVEX = "skybox/right.png",
        .NEGATIVEX = "skybox/left.png",
        .POSITIVEY = "skybox/top.png",
        .NEGATIVEY = "skybox/bottom.png",
        .POSITIVEZ = "skybox/front.png",
        .NEGATIVEZ = "skybox/back.png",
    })
    g.skybox_texture = load_cubemap_texture_single(copy_pass, "skybox/daybox.png")

    // Look at mtl  
    g.textures[Texture_Id.Colormap] = load_texture_file(copy_pass, "colormap.png")
    g.textures[Texture_Id.Cobblestone] = load_texture_file(copy_pass, "cobblestone_1.png")
    g.textures[Texture_Id.Prototype] = load_texture_file(copy_pass, "texture_01.png")

    g.models = slice.clone([]Model {
        { load_object_file(copy_pass, "sedan-sports.obj"), { diffuse_texture = g.textures[Texture_Id.Colormap], specular_color = 1, specular_shininess = 160 } },
        { load_object_file(copy_pass, "suv.obj"),          { diffuse_texture = g.textures[Texture_Id.Colormap], specular_color = 0, specular_shininess = 1 } },
        { load_object_file(copy_pass, "delivery.obj"),     { diffuse_texture = g.textures[Texture_Id.Colormap], specular_color = {1,0,0}, specular_shininess = 80 } },

        { generate_plane_mesh(copy_pass, 100, 100), { diffuse_texture = g.textures[Texture_Id.Cobblestone], specular_color = 0, specular_shininess = 1, address_mode = .WRAP}},
        { generate_box_mesh(copy_pass, 1, 1, 1), { diffuse_texture = g.textures[Texture_Id.Prototype], specular_color = 1, specular_shininess = 100}},
    })
    
    sdl.EndGPUCopyPass(copy_pass)
    ok: = sdl.SubmitGPUCommandBuffer(copy_cmd_buf); sdl_assert(ok)
    
    g.entities = slice.clone([]Entity {
        { model_id = 0, position = { 0, 0, 0 }, rotation = linalg.QUATERNIONF32_IDENTITY},
        { model_id = 1, position = { 4, 0, 0 }, rotation = linalg.quaternion_from_euler_angle_y_f32(15 * linalg.RAD_PER_DEG)},
        { model_id = 2, position = { -4, 0, 0 }, rotation = linalg.quaternion_from_euler_angle_y_f32(-15 * linalg.RAD_PER_DEG)},
        { model_id = 3 },
        { model_id = 4, position = { 3, 0.5, 3} },
    })

    g.rotate = true

    // Camera
    g.camera = {
        position = { 0, EYE_HEIGHT, 3 },
        target = { 0, EYE_HEIGHT, 0 }
    }

    g.light_position = { 0, 10, 3 }
    g.light_color = { 1, 1, 1 }
    g.light_intensity = 100
    g.ambient_light_color = { 0.1, 0.1, 0.1 }

    g.initialised = true
}

update_scene :: proc(delta_time: f32) {
    if g.ui_input_mode {
        // IMGUI Controls
        if im.Begin("Inspector") {
            im.Checkbox("Rotate", &g.rotate)
            im.Checkbox("Multi-Image Skybox", &g.skybox_use_multi_image)

            im.SeparatorText("Colors")
            im.ColorEdit3("Ambient Color", &g.ambient_light_color, { .Float })           

            im.SeparatorText("Light")
            im.DragFloat3("Position", &g.light_position, 0.1, -10, 500)
            im.ColorEdit3("Color", &g.light_color, {.Float})
            im.DragFloat("Intensity", &g.light_intensity, 0.01, 0, 1000)
            
            for entity, i in g.entities {
                im.PushIDInt(i32(i))

                im.SeparatorText(fmt.ctprintf("Object {}", i + 1))
                model := &g.models[entity.model_id]
                im.ColorEdit3("Specular Color", &model.material.specular_color, {.Float})
                im.DragFloat("Shiniess", &model.material.specular_shininess, 1, 1, 1000)

                im.PopID()
            }
        }
        im.End()
    }

    // update game state
    if g.rotate {
        g.entities[0].rotation *= linalg.quaternion_from_euler_angle_y_f32(ROTATION_SPEED * delta_time)
        g.entities[1].rotation *= linalg.quaternion_from_euler_angle_y_f32(-ROTATION_SPEED * delta_time)
        g.entities[2].rotation *= linalg.quaternion_from_euler_angle_y_f32(-ROTATION_SPEED * delta_time)
    }

    update_camera(delta_time)
}

render_scene :: proc(cmd_buf: ^sdl.GPUCommandBuffer, swapchain_tex: ^sdl.GPUTexture) {

    aspect := f32(g.window_size.x) / f32(g.window_size.y)   
    proj_mat := linalg.matrix4_perspective_f32(linalg.to_radians(f32(70)), aspect, 0.0001, 1000)
    view_mat := linalg.matrix4_look_at_f32(g.camera.position, g.camera.target, {0, 1, 0})
    
    ubo_vert_global := UBO_Vertex_Global { 
        view_projection_mat = proj_mat * view_mat,
        inv_view_mat = linalg.inverse(view_mat),
        inv_projection_mat = linalg.inverse(proj_mat),
    }
    sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo_vert_global, size_of(ubo_vert_global))

    ubo_frag_global := UBO_Fragment_Global {
        lightPosition = g.light_position,
        lightColor = g.light_color,
        lightIntensity = g.light_intensity,
        viewPosition = g.camera.position,
        ambientLightColor = g.ambient_light_color,
    }

    sdl.PushGPUFragmentUniformData(cmd_buf, 0, &ubo_frag_global, size_of(ubo_frag_global))

    clear_color : sdl.FColor = 1
    clear_color.rgb = g.ambient_light_color
    
    color_target := sdl.GPUColorTargetInfo {
        texture = swapchain_tex,
        load_op = .CLEAR,
        clear_color = clear_color,
        store_op = .STORE
    }
    depth_target_info := sdl.GPUDepthStencilTargetInfo {    
        texture = g.depth_texture,
        load_op = .CLEAR,
        clear_depth = 1,
        store_op = .DONT_CARE
    }
    render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, &depth_target_info)

    // Lightshape
    {
        sdl.BindGPUGraphicsPipeline(render_pass, g.light_shape_pipeline)
        model_mat := linalg.matrix4_translate_f32(g.light_position)
        sdl.PushGPUVertexUniformData(cmd_buf, 1, &model_mat, size_of(model_mat))
        sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = g.light_shape_mesh.vertex_buf }), 1)
        sdl.BindGPUIndexBuffer(render_pass, { buffer = g.light_shape_mesh.index_buf }, ._16BIT)
        sdl.DrawGPUIndexedPrimitives(render_pass, g.light_shape_mesh.num_indices, 1, 0, 0, 0)
    }

    sdl.BindGPUGraphicsPipeline(render_pass, g.entity_pipeline)

    for entity in g.entities {
        model_mat := linalg.matrix4_from_trs_f32(entity.position, entity.rotation, 1)
        normal_mat := linalg.inverse_transpose((model_mat))
        
        ubo_vert_local := UBO_Vertex_Local { 
            model_mat = model_mat,
            normal_mat = normal_mat,
            scale = entity.model_id != 3 ? 1.0 : 50.0,
        }

        model := g.models[entity.model_id]
        material := model.material
        
        ubo_frag_local := UBO_Fragment_Local {
            material_specular_color = material.specular_color,
            material_specular_shininess = material.specular_shininess,
        }
        sdl.PushGPUFragmentUniformData(cmd_buf, 1, &ubo_frag_local, size_of(ubo_frag_local))
        
        sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = model.mesh.vertex_buf, offset = 0, }), 1)
        sdl.BindGPUIndexBuffer(render_pass, { buffer = model.mesh.index_buf}, ._16BIT )
        sdl.PushGPUVertexUniformData(cmd_buf, 1, &ubo_vert_local, size_of(ubo_vert_local))
        sdl.BindGPUFragmentSamplers(render_pass, 0, &(sdl.GPUTextureSamplerBinding){texture = material.diffuse_texture, sampler = g.default_sampler}, 1)
        sdl.DrawGPUIndexedPrimitives(render_pass, model.mesh.num_indices, 1, 0, 0, 0 )
   
    }

    // Cubemap
    {
        skybox_tex := g.skybox_use_multi_image ? g.skybox_multi_texture : g.skybox_texture
        sdl.BindGPUGraphicsPipeline(render_pass, g.skybox_pipeline)

        sdl.BindGPUFragmentSamplers(render_pass, 0, &(sdl.GPUTextureSamplerBinding { texture = skybox_tex, sampler = g.default_sampler}), 1)
        sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
    }

    sdl.EndGPURenderPass(render_pass)
}

cleanup_scene :: proc() {
    
    if sdl.WaitForGPUIdle(g.gpu) {
        if g.entity_pipeline != nil {
            log.debug("RELEASE: entity_pipeline")
            sdl.ReleaseGPUGraphicsPipeline(g.gpu, g.entity_pipeline)
        }
        if g.skybox_pipeline != nil {
            log.debug("RELEASE: skybox_pipeline")
            sdl.ReleaseGPUGraphicsPipeline(g.gpu, g.skybox_pipeline)
        }
        if g.light_shape_pipeline != nil {
            log.debug("RELEASE: light_shape_pipeline")
            sdl.ReleaseGPUGraphicsPipeline(g.gpu, g.light_shape_pipeline)
        }
        // None of this affects the warns at the end about live objects!
        if g.depth_texture != nil {
            log.debug("RELEASE: Releasing depth_texture")
            sdl.ReleaseGPUTexture(g.gpu, g.depth_texture)
        } 

        if g.default_sampler != nil {
            log.debug("RELEASE: default_sampler")
            sdl.ReleaseGPUSampler(g.gpu, g.default_sampler)
        }

        if len(g.textures) > 0 {
            log.debugf("Releasing {} textures", len(g.textures))

            for key, texture in g.textures {
                log.debugf("Releasing Texture_Id {}", key)
                sdl.ReleaseGPUTexture(g.gpu, texture)
            }
        }
        defer delete(g.textures)
        
        for model in g.models {
            sdl.ReleaseGPUBuffer(g.gpu, model.mesh.index_buf)
            sdl.ReleaseGPUBuffer(g.gpu, model.mesh.vertex_buf)
        }
    }
}

setup_entity_pipeline :: proc () {
	vertex_attrs := []sdl.GPUVertexAttribute {
		{
			location = 0,
			format = .FLOAT3,
			offset = u32(offset_of(Vertex_Data, pos)),
		},
        {
            location = 1,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data, uv)),
        },
        {
            location = 2,
            format = .FLOAT3,
            offset = u32(offset_of(Vertex_Data, normal)),
        },
        {
            location = 3,
            format = .FLOAT4,
            offset = u32(offset_of(Vertex_Data, color)),
        },
	}

    pc : Pipeline_Create = {
        vertex_shader = "shader.vert",
        fragment_shader = "shader.frag",
        vertex_attrs = vertex_attrs,
        primitive_type = .TRIANGLELIST,
        depth_texture_format = g.depth_texture_format,
        depth_stencil_compare = .LESS,
        swapchain_texture_format = g.swapchain_texture_format,
    }

    g.entity_pipeline = get_pipeline(pc)
}

setup_light_shape_pipeline :: proc() {
    vertex_attrs := []sdl.GPUVertexAttribute {
        {
            location = 0,
            format = .FLOAT3,
            offset = u32(offset_of(Vertex_Data, pos)),
        },
    }

    pc : Pipeline_Create = {
        vertex_shader = "lightshape.vert",
        fragment_shader = "lightshape.frag",
        vertex_attrs = vertex_attrs,
        primitive_type = .TRIANGLELIST,
        depth_texture_format = g.depth_texture_format,
        depth_stencil_compare = .LESS,
        swapchain_texture_format = g.swapchain_texture_format,
    }

    g.light_shape_pipeline = get_pipeline(pc)
}

setup_skybox_pipeline :: proc() {
    pc : Pipeline_Create = {
        vertex_shader = "skybox.vert",
        fragment_shader = "skybox.frag",
        primitive_type = .TRIANGLELIST,
        depth_texture_format = g.depth_texture_format,
        depth_stencil_compare = .EQUAL,
        swapchain_texture_format = g.swapchain_texture_format,
    }

    g.skybox_pipeline = get_pipeline(pc)
}