package main

import "base:runtime"
import "core:log"
import "core:math/linalg"
import sdl "vendor:sdl3"

import im "shared:imgui"
import im_sdl "shared:imgui/imgui_impl_sdl3"
import im_sdlgpu "shared:imgui/imgui_impl_sdlgpu3"

g: Globals

sdl_log :: proc "c" (
	userdata: rawptr,
	category: sdl.LogCategory,
	priority: sdl.LogPriority,
	message: cstring,
) {
	context = (transmute(^runtime.Context)userdata)^
	level: log.Level
	switch priority {
	case .INVALID, .TRACE, .VERBOSE, .DEBUG:
		level = .Debug
	case .INFO:
		level = .Info
	case .WARN:
		level = .Warning
		// return // temp
	case .ERROR:
		level = .Error
	case .CRITICAL:
		level = .Fatal
	}
	log.logf(level, "SDL {}: {}", category, message)
}

init_sdl :: proc() {
	@(static) sdl_log_context: runtime.Context
	sdl_log_context = context
	sdl_log_context.logger.options = {.Short_File_Path, .Line, .Procedure}
	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(sdl_log, &sdl_log_context)

    // Must be called before Init
    _ = sdl.SetAppMetadata("SDL3", "0.0.1", "com.electricraven.sdl3")

	ok := sdl.Init({ .VIDEO })
	if !ok do log.panicf("Could not init SDL: {}", sdl.GetError())


	g.window = sdl.CreateWindow("SDL3", 1280, 780, {})
	if g.window == nil do log.panicf("Could not create SDL window: {}", sdl.GetError())

	g.gpu = sdl.CreateGPUDevice({.SPIRV, .DXIL, .MSL}, true, nil)
	if g.gpu == nil do log.panicf("Could not create GPU device: {}", sdl.GetError())

	ok = sdl.ClaimWindowForGPUDevice(g.gpu, g.window)
	if !ok do log.panicf("Could not claim window for GPU: {}", sdl.GetError())

	// NOTE: was .SDR_LINEAR
	ok = sdl.SetGPUSwapchainParameters(g.gpu, g.window, .SDR_LINEAR, .VSYNC)
	if !ok do log.panicf("Could not SetGPUSwapchainParameters for GPU: {}", sdl.GetError())

	g.swapchain_texture_format = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window)
    
	g.textures = make(map[Texture_Id]^sdl.GPUTexture)

	init_sdl_window()

	_ = sdl.SetWindowRelativeMouseMode(g.window, true)

	init_imgui()
}

init_sdl_window :: proc() {
	// Do on resize
	ok := sdl.GetWindowSize(g.window, &g.window_size.x, &g.window_size.y); sdl_assert(ok)

	g.depth_texture_format = .D16_UNORM
	try_depth_format :: proc(format: sdl.GPUTextureFormat) {
		if sdl.GPUTextureSupportsFormat(g.gpu, format, .D2, {.DEPTH_STENCIL_TARGET}) {
			g.depth_texture_format = format
		}
	}

	try_depth_format(.D32_FLOAT)
	try_depth_format(.D24_UNORM)

	log.debug("Creating depth_texture")

    props := sdl.CreateProperties()
    defer sdl.DestroyProperties(props)

    sdl.SetFloatProperty(props, sdl.PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_DEPTH_FLOAT, 1.0)

	g.depth_texture = sdl.CreateGPUTexture(
        g.gpu,
        {
            format               = g.depth_texture_format,
            usage                = {.DEPTH_STENCIL_TARGET},
            width                = u32(g.window_size.x),
            height               = u32(g.window_size.y),
            layer_count_or_depth = 1,
            num_levels           = 1,
            props                = props,
        },
	)

	log.debug("Created depth_texture")
}

init_imgui :: proc() {
	im.CHECKVERSION()
	im.CreateContext()
	im_sdl.InitForSDLGPU(g.window)
	im_sdlgpu.Init(&{Device = g.gpu, ColorTargetFormat = g.swapchain_texture_format})

	style := im.GetStyle()
	for &color in style.Colors {
		color.rgb = linalg.pow(color.rgb, 2.2)
	}
}


main :: proc() {
	context.logger = log.create_console_logger()

	init_sdl()

    // TODO: start the default scene
	// game_init()
    // init_scene()

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
			case .WINDOW_RESIZED:
				log.debug("WINDOW RESIZED")
			case .KEY_DOWN:
				if ev.key.scancode == .ESCAPE do break main_loop

				if !g.ui_input_mode {
					g.key_down[ev.key.scancode] = true
				}
			case .KEY_UP:
				if !g.ui_input_mode {
					g.key_down[ev.key.scancode] = false
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

        // Test
        if g.key_down[.KP_ENTER] {
            g.current_scene = .Main
        }

		// IMGUI
		im_sdlgpu.NewFrame()
		im_sdl.NewFrame()
		im.NewFrame()

        switch g.current_scene {
            case Scenes.None:
                break;
            case Scenes.Main:
                if g.initialised {
                    update_scene(delta_time)
                } else {
                    init_scene()
                }
        }

		// render

		// acquire command buffer
        // This command buffer is managed by the implementation and should not be freed by the user
        // SEE: https://wiki.libsdl.org/SDL3/SDL_AcquireGPUCommandBuffer
		cmd_buf := sdl.AcquireGPUCommandBuffer(g.gpu)

		// acquire swapchain texture
        // The swapchain texture is managed by the implementation and must not be freed by the user. 
        // You MUST NOT call this function from any thread other than the one that created the window.
        // SEE: https://wiki.libsdl.org/SDL3/SDL_WaitAndAcquireGPUSwapchainTexture
		swapchain_tex: ^sdl.GPUTexture
		ok := sdl.WaitAndAcquireGPUSwapchainTexture(
			cmd_buf,
			g.window,
			&swapchain_tex,
			nil,
			nil,
		); sdl_assert(ok)

		im.Render()
		im_draw_data := im.GetDrawData()

		if swapchain_tex != nil {
			// begin render pass
			game_render(cmd_buf, swapchain_tex)

			if im_draw_data.DisplaySize.x > 0 && im_draw_data.DisplaySize.y > 0 {
				im_sdlgpu.PrepareDrawData(im_draw_data, cmd_buf)
				im_color_target := sdl.GPUColorTargetInfo {
					texture  = swapchain_tex,
					load_op  = .LOAD,
					store_op = .STORE,
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

    teardown()
}

teardown :: proc() {

    switch g.current_scene {
        case .None:
            break;
        case .Main:
            if g.initialised do cleanup_scene()
    }

    log.debug("Closing!")
    sdl.Quit()
}