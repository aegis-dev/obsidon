package renderer

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
	ctx: 			 runtime.Context,
	buffer_width: 	 u32,
	buffer_height: 	 u32,
	instance:        wgpu.Instance,
	surface:         wgpu.Surface,
	adapter:         wgpu.Adapter,
	device:          wgpu.Device,
	config:          wgpu.SurfaceConfiguration,
	queue:           wgpu.Queue,
	module:          wgpu.ShaderModule,
	pipeline_layout: wgpu.PipelineLayout,
	pipeline:        wgpu.RenderPipeline,

	clear_color:     	 [4]f64,
	surface_texture: 	 wgpu.SurfaceTexture,
	frame:		  	 	 wgpu.TextureView,
	command_encoder: 	 wgpu.CommandEncoder,
	render_pass_encoder: wgpu.RenderPassEncoder,
}

init :: proc(window: glfw.WindowHandle, buffer_width: u32, buffer_height: u32) {
	instance.ctx = context
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
			width       = instance.buffer_width,
			height      = instance.buffer_height,
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

		vertex_attributes := make([^]wgpu.VertexAttribute, 2) // length 2, zero-initialized
		vertex_attributes[0] = wgpu.VertexAttribute{ format = .Float32x3, offset = 0, shaderLocation = 0 }
		vertex_attributes[1] = wgpu.VertexAttribute{ format = .Float32x2, offset = size_of(Vec3), shaderLocation = 1 }

		vertex_buffer_layout := wgpu.VertexBufferLayout {
			arrayStride    = size_of(Vec3) + size_of(Vec2), // 3 floats + 2 floats
			stepMode       = .Vertex,
			attributeCount = 2,
			attributes     = vertex_attributes,
		}

		bind_group_layout_entrys := make([^]wgpu.BindGroupLayoutEntry, 2)
		bind_group_layout_entrys[0] = wgpu.BindGroupLayoutEntry{
			binding    = 0,
			visibility = { .Fragment },
			texture    = { sampleType = .Float, viewDimension = ._2D, multisampled = false },
		}
		bind_group_layout_entrys[1] = wgpu.BindGroupLayoutEntry{
			binding    = 1,
			visibility = { .Fragment },
			sampler    = { type = .Filtering },
		}

		bind_group_layout := wgpu.DeviceCreateBindGroupLayout(instance.device, &wgpu.BindGroupLayoutDescriptor{
			entryCount = 2,
			entries    = bind_group_layout_entrys
		})

		instance.pipeline_layout = wgpu.DeviceCreatePipelineLayout(instance.device, &{
			bindGroupLayoutCount = 1,
			bindGroupLayouts     = &bind_group_layout,
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

	instance.frame = wgpu.TextureCreateView(instance.surface_texture.texture, nil)
	instance.command_encoder = wgpu.DeviceCreateCommandEncoder(instance.device, nil)
	instance.render_pass_encoder = wgpu.CommandEncoderBeginRenderPass(
		instance.command_encoder, &{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment{
				view       = instance.frame,
				loadOp     = .Clear,
				storeOp    = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = instance.clear_color,
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(instance.render_pass_encoder, instance.pipeline)
}

draw :: proc() {
	//wgpu.RenderPassEncoderDraw(instance.render_pass_encoder, vertexCount=3, instanceCount=1, firstVertex=0, firstInstance=0)
}

end_draw_and_present :: proc() {
	wgpu.RenderPassEncoderEnd(instance.render_pass_encoder)
	wgpu.RenderPassEncoderRelease(instance.render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(instance.command_encoder, nil)

	wgpu.QueueSubmit(instance.queue, { command_buffer })
	wgpu.SurfacePresent(instance.surface)

	wgpu.CommandBufferRelease(command_buffer)
	wgpu.CommandEncoderRelease(instance.command_encoder)
	wgpu.TextureViewRelease(instance.frame)
}

@(private)
get_sprite_quad :: proc(width: u32, height: u32) -> (vertice: []f32, indice: []u32) {
	half_width  := f32(width)  / 2.0
	half_height := f32(height) / 2.0

	vertice = []f32 {
		// positions               		  // tex coords
		-half_width, -half_height, 0.0,   0.0, 1.0,
		 half_width, -half_height, 0.0,   1.0, 1.0,
		 half_width,  half_height, 0.0,   1.0, 0.0,
		-half_width,  half_height, 0.0,   0.0, 0.0,
	}

	indice = []u32 {
		0, 1, 2,
		2, 3, 0,
	}

	return
}



cleanup :: proc() {

}