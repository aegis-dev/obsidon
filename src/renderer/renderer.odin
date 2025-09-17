package renderer

import "core:image/png"
import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:wgpu"
import "vendor:glfw"
import "vendor:wgpu/glfwglue"

SHADER :: string(#load("shader.wgsl"))

@(private)
instance: struct {
	ctx: 			   runtime.Context,
	window_width: 	   u32,
	window_height: 	   u32,
	buffer_width: 	   u32,
	buffer_height: 	   u32,
	instance:          wgpu.Instance,
	surface:           wgpu.Surface,
	adapter:           wgpu.Adapter,
	device:            wgpu.Device,
	config:            wgpu.SurfaceConfiguration,
	queue:             wgpu.Queue,
	module:            wgpu.ShaderModule,
	bind_group_layout: wgpu.BindGroupLayout,
	pipeline_layout:   wgpu.PipelineLayout,
	pipeline:          wgpu.RenderPipeline,
	sampler: 	 	   wgpu.Sampler,

	clear_color:     	 	 [4]f64,
	black_clear_color:       [4]f64,
	surface_texture: 		 wgpu.SurfaceTexture,
	surface_texture_view:	 wgpu.TextureView,
	command_encoder: 	 	 wgpu.CommandEncoder,
	render_pass_encoder: 	 wgpu.RenderPassEncoder,

	offscreen_quad: TexturedModel,
}

init :: proc(window: glfw.WindowHandle, window_width: u32, window_height: u32, buffer_width: u32, buffer_height: u32) {
	instance.ctx = context
	instance.window_width = window_width
	instance.window_height = window_height
	instance.buffer_width = buffer_width
	instance.buffer_height = buffer_height

	instance.instance = wgpu.CreateInstance(nil)
	if instance.instance == nil {
		panic("WebGPU is not supported")
	}

	instance.surface = glfwglue.GetSurface(instance.instance, window)

	wgpu.InstanceRequestAdapter(instance.instance, &{ compatibleSurface = instance.surface }, { callback = on_adapter })

	on_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: string, userdata1: rawptr, userdata2: rawptr) {
		context = instance.ctx
		if status != .Success || adapter == nil {
			log.panic("request adapter failure: [%v] %s", status, message)
		}
		instance.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, nil, { callback = on_device })
	}

	on_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1: rawptr, userdata2: rawptr) {
		context = instance.ctx
		if status != .Success || device == nil {
			log.panic("request device failure: [%v] %s", status, message)
		}
		instance.device = device 

		instance.config = wgpu.SurfaceConfiguration {
			device      = instance.device,
			usage       = { .RenderAttachment },
			format      = .BGRA8Unorm,
			width       = instance.window_width,
			height      = instance.window_height,
			presentMode = .Fifo,
			alphaMode   = .Opaque,
		}
		wgpu.SurfaceConfigure(instance.surface, &instance.config)

		instance.queue = wgpu.DeviceGetQueue(instance.device)

		instance.module = wgpu.DeviceCreateShaderModule(instance.device, &{
			nextInChain = &wgpu.ShaderSourceWGSL{
				sType = .ShaderSourceWGSL,
				code  = SHADER,
			},
		})

		vertex_attributes := [2]wgpu.VertexAttribute {
			{ format = .Float32x3, offset = 0, shaderLocation = 0 },
			{ format = .Float32x2, offset = size_of(Vec3), shaderLocation = 1 }
		}

		vertex_buffer_layout := wgpu.VertexBufferLayout {
			arrayStride    = size_of(Vec3) + size_of(Vec2), // 3 floats + 2 floats
			stepMode       = .Vertex,
			attributeCount = len(vertex_attributes),
			attributes     = &vertex_attributes[0],
		}
		
		instance.sampler = wgpu.DeviceCreateSampler(instance.device, &{
			magFilter = .Nearest,
			minFilter = .Nearest,
			mipmapFilter = .Nearest,
			lodMinClamp = 1.0,
			lodMaxClamp = 1.0,
			compare = .Undefined,
			maxAnisotropy = 1,
		})

		bind_group_layout_entries := [2]wgpu.BindGroupLayoutEntry {
			{
				binding    = 0,
				visibility = { .Fragment },
				texture    = { sampleType = .Float, viewDimension = ._2D, multisampled = false },
			},
			{
				binding    = 1,
				visibility = { .Fragment },
				sampler    = { type = .Filtering },
			},
		}

		instance.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(instance.device, &wgpu.BindGroupLayoutDescriptor{
			entryCount = len(bind_group_layout_entries),
			entries    = &bind_group_layout_entries[0]
		})

		instance.pipeline_layout = wgpu.DeviceCreatePipelineLayout(instance.device, &{
			bindGroupLayoutCount = 1,
			bindGroupLayouts     = &instance.bind_group_layout,
		})

		instance.pipeline = wgpu.DeviceCreateRenderPipeline(instance.device, &{
			layout = instance.pipeline_layout,
			vertex = {
				module     = instance.module,
				entryPoint = "vs_main",
				bufferCount = 1,
				buffers     = &vertex_buffer_layout,
			},
			fragment = &{
				module      = instance.module,
				entryPoint  = "fs_main",
				targetCount = 1,
				targets     = &wgpu.ColorTargetState{
					format    = .BGRA8Unorm,
					writeMask = wgpu.ColorWriteMaskFlags_All,
				},
			},
			primitive = {
				topology = .TriangleList,

			},
			multisample = {
				count = 1,
				mask  = 0xFFFFFFFF,
			},
		})

		offscreen_quad := []Vertex {
			//      positions               tex coords
			Vertex {Vec3 { 1.0, -1.0, 0.0}, Vec2 {1.0, 1.0}},
			Vertex {Vec3 { 1.0,  1.0, 0.0}, Vec2 {1.0, 0.0}},
			Vertex {Vec3 {-1.0, -1.0, 0.0}, Vec2 {0.0, 1.0}},
			Vertex {Vec3 {-1.0, -1.0, 0.0}, Vec2 {0.0, 1.0}},
			Vertex {Vec3 { 1.0,  1.0, 0.0}, Vec2 {1.0, 0.0}},
			Vertex {Vec3 {-1.0,  1.0, 0.0}, Vec2 {0.0, 0.0}},
		}
		offscreen_quad_buffer := load_vertex_buffer(offscreen_quad)

		offscreen_texture := wgpu.DeviceCreateTexture(instance.device, &{
			size = wgpu.Extent3D{ width = instance.buffer_width, height = instance.buffer_height, depthOrArrayLayers = 1 },
			format = .BGRA8Unorm,
			usage = { .RenderAttachment, .TextureBinding },
			mipLevelCount = 1,
			sampleCount = 1,
		})
		offscreen_texture_view := wgpu.TextureCreateView(offscreen_texture, nil)

		instance.offscreen_quad = TexturedModel {
			model = offscreen_quad_buffer,
			texture = create_texture_from_texture_and_texture_view(
				offscreen_texture,
				offscreen_texture_view,
				instance.buffer_width,
				instance.buffer_height
			)
		}
	}
}

set_clear_color :: proc(r: f64, g: f64, b: f64, a: f64) {
	instance.clear_color = [4]f64{r, g, b, a}
}

begin_draw :: proc() {
	instance.surface_texture = wgpu.SurfaceGetCurrentTexture(instance.surface)

	switch instance.surface_texture.status {
	case .SuccessOptimal, .SuccessSuboptimal:
		// All good, could handle suboptimal here.
	case .Timeout, .Outdated, .Lost:
		// Skip this frame, and re-configure surface.
		// if instance.surface_texture.texture != nil {
		// 	wgpu.TextureRelease(instance.surface_texture.texture)
		// }
		// resize()
		log.panic("Resize???")
	case .OutOfMemory, .DeviceLost, .Error:
		// Fatal error
		log.panicf("Error: get_current_texture status=%v", instance.surface_texture.status)
	}

	// instance.surface_texture_view = wgpu.TextureCreateView(instance.surface_texture.texture, nil)
	// instance.command_encoder = wgpu.DeviceCreateCommandEncoder(instance.device, nil)
	// instance.render_pass_encoder = wgpu.CommandEncoderBeginRenderPass(
	// 	instance.command_encoder, &{
	// 		colorAttachmentCount = 1,
	// 		colorAttachments = &wgpu.RenderPassColorAttachment{
	// 			view       = instance.surface_texture_view,
	// 			loadOp     = .Clear,
	// 			storeOp    = .Store,
	// 			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
	// 			clearValue = instance.clear_color,
	// 		},
	// 	},
	// )

	instance.command_encoder = wgpu.DeviceCreateCommandEncoder(instance.device, nil)
	instance.render_pass_encoder = wgpu.CommandEncoderBeginRenderPass(
		instance.command_encoder, &{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment{
				view       = instance.offscreen_quad.texture.view,
				loadOp     = .Clear,
				storeOp    = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = instance.clear_color,
			},
		},
	)

	set_viewport(
		instance.offscreen_quad.texture.width, 
		instance.offscreen_quad.texture.height,
		instance.offscreen_quad.texture.width, 
		instance.offscreen_quad.texture.height
	)

	wgpu.RenderPassEncoderSetPipeline(instance.render_pass_encoder, instance.pipeline)
}

draw :: proc() {
	//wgpu.RenderPassEncoderDraw(instance.render_pass_encoder, vertexCount=3, instanceCount=1, firstVertex=0, firstInstance=0)
}

end_draw_and_present :: proc() {
	// Finish offscreen rendering
	wgpu.RenderPassEncoderEnd(instance.render_pass_encoder)
	wgpu.RenderPassEncoderRelease(instance.render_pass_encoder)

	offscreen_command_buffer := wgpu.CommandEncoderFinish(instance.command_encoder, nil)
	defer wgpu.CommandBufferRelease(offscreen_command_buffer)

	wgpu.CommandEncoderRelease(instance.command_encoder)

	// Render to the the screen surface
	instance.surface_texture_view = wgpu.TextureCreateView(instance.surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(instance.surface_texture_view)

	black_clear_color := [4]f64{0.0, 0.0, 0.0, 1.0}

	instance.command_encoder = wgpu.DeviceCreateCommandEncoder(instance.device, nil)
	instance.render_pass_encoder = wgpu.CommandEncoderBeginRenderPass(
		instance.command_encoder, &{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment{
				view       = instance.surface_texture_view,
				loadOp     = .Clear,
				storeOp    = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = black_clear_color,
			},
		},
	)

	viewport_width, viewport_height := fit_rectangle_in_rectangle(
		f32(instance.buffer_width), f32(instance.buffer_height),
		f32(instance.window_width), f32(instance.window_height)
	)

	set_viewport(u32(viewport_width), u32(viewport_height), instance.window_width, instance.window_height)
	
	wgpu.RenderPassEncoderSetPipeline(instance.render_pass_encoder, instance.pipeline)

	// Render offscreen texture quad to screen
	render_textured_model(&instance.offscreen_quad)

	// Finish screen rendering
	wgpu.RenderPassEncoderEnd(instance.render_pass_encoder)
	wgpu.RenderPassEncoderRelease(instance.render_pass_encoder)

	screen_command_buffer := wgpu.CommandEncoderFinish(instance.command_encoder, nil)
	defer wgpu.CommandBufferRelease(screen_command_buffer)

	wgpu.CommandEncoderRelease(instance.command_encoder)

	// Submit and present
	wgpu.QueueSubmit(instance.queue, { offscreen_command_buffer, screen_command_buffer })
	wgpu.SurfacePresent(instance.surface)
}

@(private)
render_textured_model :: proc(textured_model: ^TexturedModel) {
	wgpu.RenderPassEncoderSetVertexBuffer(
		instance.render_pass_encoder, 
		0, 
		textured_model.model.vertex_buffer, 
		0, 
		textured_model.model.buffer_size
	)

	wgpu.RenderPassEncoderSetBindGroup(
		instance.render_pass_encoder,
		0,          
		textured_model.texture.bind_group
	)

	wgpu.RenderPassEncoderDraw(
		instance.render_pass_encoder,
		vertexCount=textured_model.model.vertex_count, 
		instanceCount=1, 
		firstVertex=0, 
		firstInstance=0
	)
}

load_vertex_buffer :: proc(vertices: []Vertex) -> Model {
	vertex_buffer_size := u64(size_of(Vertex) * len(vertices))

	vertex_buffer := wgpu.DeviceCreateBuffer(instance.device, &{
		size  = vertex_buffer_size,
		usage = { .Vertex, .CopyDst },
		mappedAtCreation = false,
	})

	wgpu.QueueWriteBuffer(instance.queue, vertex_buffer, 0, rawptr(&vertices[0]), uint(vertex_buffer_size))

	return Model {vertex_buffer, u32(len(vertices)), vertex_buffer_size}
}

load_texture_from_png :: proc(png_data: []u8) -> Texture {
	image, err := png.load_from_bytes(png_data)
	if err != nil {
		log.panic("Failed to load PNG image")
	}
	defer png.destroy(image)

	// Create texture
	texture := wgpu.DeviceCreateTexture(instance.device, &{
		size = wgpu.Extent3D{ width = u32(image.width), height = u32(image.height), depthOrArrayLayers = 1 },
		format = .RGBA8Unorm,
		usage = { .TextureBinding, .CopyDst },
		mipLevelCount = 1,
		sampleCount = 1,
	})
	texture_view := wgpu.TextureCreateView(texture, nil)

	// Upload texture data
	row_pitch := u32(4 * image.width) // 4 bytes per pixel (RGBA)
	data_size := row_pitch * u32(image.height)

	destination_info := wgpu.TexelCopyTextureInfo{
		texture   = texture,
		mipLevel  = 0,
		origin    = wgpu.Origin3D{0, 0, 0},
		aspect    = .All,
	}

	data_layout := wgpu.TexelCopyBufferLayout{
		offset        = 0,
		bytesPerRow   = row_pitch,
		rowsPerImage  = u32(image.height),
	}

	write_size_info := wgpu.Extent3D{
		width         = u32(image.width),
		height        = u32(image.height),
		depthOrArrayLayers = 1,
	}

	wgpu.QueueWriteTexture(instance.queue, &destination_info, &image.pixels.buf[0], uint(data_size), &data_layout, &write_size_info)

	return create_texture_from_texture_and_texture_view(texture, texture_view, u32(image.width), u32(image.height))
}

@(private)
create_texture_from_texture_and_texture_view :: proc(texture: wgpu.Texture, texture_view: wgpu.TextureView, width: u32, height: u32) -> Texture {
	// Create a bind group for the texture and sampler
	bind_group_entries := [2]wgpu.BindGroupEntry {
		{
			binding = 0,
			textureView = texture_view,
		},
		{
			binding = 1,
			sampler = instance.sampler,
		}
	}

	bind_group := wgpu.DeviceCreateBindGroup(instance.device, &wgpu.BindGroupDescriptor{
		layout = instance.bind_group_layout, // The layout you created in your pipeline
		entryCount = len(bind_group_entries),
		entries = &bind_group_entries[0],
	})

	return Texture {width, height, texture, texture_view, bind_group}
}

@(private)
set_viewport :: proc(viewport_width: u32, viewport_height: u32, window_width: u32, window_height: u32) {
	viewport_width := f32(viewport_width)
	viewport_height := f32(viewport_height)
	window_width := f32(window_width)
	window_height := f32(window_height)

    aspect_ratio := viewport_width / viewport_height
    window_aspect_ratio := window_width / window_height
    tolerance: f32 = 1e-2
    same_aspect_ratio := abs(aspect_ratio - window_aspect_ratio) < tolerance
    narrow := aspect_ratio < window_aspect_ratio

    x: f32 = 0
    y: f32 = 0
    width: f32 = window_width
    height: f32 = window_height

    if same_aspect_ratio {
        x = 0
        y = 0
        width = viewport_width
        height = viewport_height
    } else if narrow {
        min_height := min(viewport_height, window_height)
        max_height := max(viewport_height, window_height)
        modifier := max_height / min_height
        new_width := viewport_width * modifier
        new_height := window_height
        offset := (window_width - new_width) / 2
        x = offset
        y = 0
        width = new_width
        height = new_height
    } else {
        min_width := min(viewport_width, window_width)
        max_width := max(viewport_width, window_width)
        modifier := max_width / min_width
        new_width := window_width
        new_height := viewport_height * modifier
        x = 0
        y = (window_height - new_height) / 2
        width = new_width
        height = new_height
    }
	
    wgpu.RenderPassEncoderSetViewport(
        instance.render_pass_encoder,
        x, y, width, height,
        0.0, 1.0
    )
}

@(private)
fit_rectangle_in_rectangle :: proc(inner_width: f32, inner_height: f32, outer_width: f32, outer_height: f32) -> (f32, f32) {
	inner_aspect := inner_width / inner_height
	outer_aspect := outer_width / outer_height

	if inner_aspect > outer_aspect {
		// Fit to width
		new_width := outer_width
		new_height := outer_width / inner_aspect
		return new_width, new_height
	} else {
		// Fit to height
		new_height := outer_height
		new_width := outer_height * inner_aspect
		return new_width, new_height
	}
}

cleanup :: proc() {

}