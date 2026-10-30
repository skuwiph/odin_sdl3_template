package main 

import "base:runtime"
import "core:log"
import "core:math/linalg"
import sdl "vendor:sdl3"

import im "shared:imgui"
import im_sdl "shared:imgui/imgui_impl_sdl3"
import im_sdlgpu "shared:imgui/imgui_impl_sdlgpu3"

g : Globals

sdl_log :: proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
    context = (transmute(^runtime.Context)userdata)^
	level: log.Level
	switch priority {
	case .INVALID, .TRACE, .VERBOSE, .DEBUG: level = .Debug
	case .INFO: level = .Info
	case .WARN: 
        level = .Warning 
        return // temp
	case .ERROR: level = .Error
	case .CRITICAL: level = .Fatal
	}
	log.logf(level, "SDL {}: {}", category, message)
}

init_sdl :: proc() {
    @static sdl_log_context : runtime.Context
    sdl_log_context = context
    sdl_log_context.logger.options = {.Short_File_Path, .Line, .Procedure}
    sdl.SetLogPriorities(.VERBOSE)
    sdl.SetLogOutputFunction(sdl_log, &sdl_log_context)

    ok := sdl.Init( { .VIDEO })
    if !ok do log.panicf("Could not init SDL: {}", sdl.GetError())

    g.window = sdl.CreateWindow("Hello", 1280, 780, {})
    if g.window == nil do log.panicf("Could not create SDL window: {}", sdl.GetError())

    g.gpu = sdl.CreateGPUDevice({ .SPIRV, .DXIL, .MSL }, true, nil)
    if g.gpu == nil do log.panicf("Could not create GPU device: {}", sdl.GetError())

    ok = sdl.ClaimWindowForGPUDevice(g.gpu, g.window)
    if !ok do log.panicf("Could not claim window for GPU: {}", sdl.GetError())

    // NOTE: was .LINEAR_SDR
    ok = sdl.SetGPUSwapchainParameters(g.gpu, g.window, .SDR_LINEAR, .VSYNC);
    if !ok do log.panicf("Could not SetGPUSwapchainParameters for GPU: {}", sdl.GetError())

    g.swapchain_texture_format = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window)

    // Do on resize
    ok = sdl.GetWindowSize(g.window, &g.window_size.x, &g.window_size.y); sdl_assert(ok)

    g.depth_texture_format = .D16_UNORM
    try_depth_format :: proc(format: sdl.GPUTextureFormat) {
        if sdl.GPUTextureSupportsFormat(g.gpu, format, .D2, {.DEPTH_STENCIL_TARGET}) {
            g.depth_texture_format = format
        }
    }

    try_depth_format(.D32_FLOAT)
    try_depth_format(.D24_UNORM)

    log.debug("Creating depth_texture")

    g.depth_texture = sdl.CreateGPUTexture(g.gpu, {
        format = g.depth_texture_format,
        usage = { .DEPTH_STENCIL_TARGET },
        width = u32(g.window_size.x),
        height = u32(g.window_size.y),
        layer_count_or_depth = 1,
        num_levels = 1,
        // props = properties
    })

    log.debug("Created depth_texture")


    _ = sdl.SetWindowRelativeMouseMode(g.window, true)

    init_imgui()
}

init_imgui :: proc() {
    im.CHECKVERSION()
    im.CreateContext()
    im_sdl.InitForSDLGPU(g.window)
    im_sdlgpu.Init( &{
        Device = g.gpu,
        ColorTargetFormat = g.swapchain_texture_format
    })

    style := im.GetStyle()
    for &color in style.Colors {
        color.rgb = linalg.pow(color.rgb, 2.2)
    }
}


main :: proc() {
    context.logger = log.create_console_logger()

    init_sdl()    
    game_init()

    last_ticks := sdl.GetTicks()

    g.ui_input_mode = !sdl.GetWindowRelativeMouseMode(g.window)
    iterations := 0

    main_loop: for {
        free_all(context.temp_allocator)
        g.mouse_move = {}

        iterations += 1
        new_ticks := sdl.GetTicks()
        delta_time := f32(new_ticks - last_ticks) / 1000
        last_ticks = sdl.GetTicks()
        
        // process events
        ev: sdl.Event
        for sdl.PollEvent(&ev) {
            if g.ui_input_mode do im_sdl.ProcessEvent(&ev)

            #partial switch ev.type {
                case .QUIT:
                    break main_loop
                case .KEY_DOWN:
                    if ev.key.scancode == .ESCAPE do break main_loop

                    if !g.ui_input_mode {
                        g.key_down[ev.key.scancode] = true;
                    }
                case .KEY_UP:
                    if !g.ui_input_mode {
                        g.key_down[ev.key.scancode] = false;
                    }
                case .MOUSE_MOTION:
                    if !g.ui_input_mode {
                        g.mouse_move += {ev.motion.xrel, ev.motion.yrel}
                    }
                case .MOUSE_BUTTON_DOWN:
                    if ev.button.button == 2 {
                        g.ui_input_mode = !g.ui_input_mode
                        _ = sdl.SetWindowRelativeMouseMode(g.window, !g.ui_input_mode)
                    }
            }
        }

        // IMGUI
        im_sdlgpu.NewFrame()
        im_sdl.NewFrame()
        im.NewFrame()
        
        game_update(delta_time)

        // render

        // acquire command buffer
        cmd_buf := sdl.AcquireGPUCommandBuffer(g.gpu);
        
        // acquire swapchain texture
        swapchain_tex: ^sdl.GPUTexture
        ok := sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, g.window, &swapchain_tex, nil, nil); sdl_assert(ok)

        im.Render()
        im_draw_data := im.GetDrawData()

        if swapchain_tex != nil {
            // begin render pass
            game_render(cmd_buf, swapchain_tex)
            
            if im_draw_data.DisplaySize.x > 0 && im_draw_data.DisplaySize.y > 0 {
                im_sdlgpu.PrepareDrawData(im_draw_data, cmd_buf)
                im_color_target := sdl.GPUColorTargetInfo {
                    texture = swapchain_tex,
                    load_op = .LOAD,
                    store_op = .STORE
                }
                im_render_pass := sdl.BeginGPURenderPass(cmd_buf, &im_color_target, 1, nil)
                im_sdlgpu.RenderDrawData(im_draw_data, cmd_buf, im_render_pass)
                sdl.EndGPURenderPass(im_render_pass)
            }
        } else {
            log.debug("Rendering Paused - Minimised/Invis")
        }

        // submit command buffer
        ok = sdl.SubmitGPUCommandBuffer(cmd_buf); sdl_assert(ok)
    }
    
    log.infof("Closing after {} iterations", iterations)

    // TODO: have an asset store of shared resources such 
    // as textures, so we only release once

    for model in g.models {
        sdl.ReleaseGPUBuffer(g.gpu, model.mesh.index_buf)
        sdl.ReleaseGPUBuffer(g.gpu, model.mesh.vertex_buf)
    }    
    sdl.ReleaseGPUTexture(g.gpu, g.models[0].material.diffuse_texture)

    // None of this affects the warns at the end about live objects!
    sdl.ReleaseGPUTexture(g.gpu, g.depth_texture)
    // if model.texture != nil do sdl.ReleaseGPUTexture(gpu, model.texture)
    sdl.ReleaseGPUSampler(g.gpu, g.sampler)
    sdl.ReleaseWindowFromGPUDevice(g.gpu, g.window)
    sdl.DestroyWindow(g.window)
}

