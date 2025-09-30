// Copyright 2025 Egidijus Vaišvila
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

package renderer

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"
import "core:math"
import "core:math/linalg"

import "vendor:wgpu"
import "vendor:glfw"
import "vendor:wgpu/glfwglue"

SHADER :: string(#load("shader.wgsl"))

@(private)
DrawCallMetadata :: struct #packed {
	mvp: 	   linalg.Matrix4x4f32,
	color: 	   Vec4,
	use_color: f32,
	flip_x:    f32,
	flip_y:    f32,
	_padding:  [1]f32,
}

// Also in shader.wgsl
MAX_DRAW_CALLS :: 8192

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
	storage_buffer:    wgpu.Buffer,

	surface_texture: 		 wgpu.SurfaceTexture,
	surface_texture_view:	 wgpu.TextureView,
	command_encoder: 	 	 wgpu.CommandEncoder,
	render_pass_encoder: 	 wgpu.RenderPassEncoder,
	offscreen_quad: 	     TexturedModel,

	clear_color:       	[4]f64,
	camera_position:   	Vec2,
	camera_angle:      	f32,
	camera_zoom:	   	f32,

	screen_color_override: 	   		Vec4,
	use_screen_color_override: 		bool,

	projection_matrix: 	linalg.Matrix4x4f32,
	draw_call: u64,
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

		required_features := wgpu.FeatureName.VertexWritableStorage // or VERTEX_READ_STORAGE if available

		wgpu.AdapterRequestDevice(adapter, 
			&wgpu.DeviceDescriptor{
				requiredFeatureCount = 1,
				requiredFeatures = &required_features,
			}, 
			{ callback = on_device }
		)
	}

	on_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1: rawptr, userdata2: rawptr) {
		context = instance.ctx
		if status != .Success || device == nil {
			log.panic("request device failure: [%v] %s", status, message)
		}
		instance.device = device 

		when ODIN_OS == .Linux {
			mode := wgpu.PresentMode.Mailbox
		} else {
			mode := wgpu.PresentMode.Immediate
		}

		instance.config = wgpu.SurfaceConfiguration {
			device      = instance.device,
			usage       = { .RenderAttachment },
			format      = .BGRA8Unorm,
			width       = instance.window_width,
			height      = instance.window_height,
			presentMode = mode,
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
			arrayStride    = size_of(Vertex),
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

		instance.storage_buffer = wgpu.DeviceCreateBuffer(instance.device, &{
			size = MAX_DRAW_CALLS * size_of(DrawCallMetadata),
			usage = { .Storage, .CopyDst },
			mappedAtCreation = false,
		})

		bind_group_layout_entries := [3]wgpu.BindGroupLayoutEntry {
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
			{
				binding    = 2,
				visibility = { .Vertex, .Fragment },
				buffer     = { type = .ReadOnlyStorage, hasDynamicOffset = false, minBindingSize = MAX_DRAW_CALLS * size_of(DrawCallMetadata) },
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
					    blend     = &wgpu.BlendState{
						color = wgpu.BlendComponent{
							srcFactor = .SrcAlpha,
							dstFactor = .OneMinusSrcAlpha,
							operation = .Add,
						},
						alpha = wgpu.BlendComponent{
							srcFactor = .One,
							dstFactor = .OneMinusSrcAlpha,
							operation = .Add,
						},
					},
				},
			},
			primitive = {
				topology = .TriangleList,
				stripIndexFormat = .Undefined,
				frontFace = .CCW,
				cullMode = .None,

			},
			multisample = {
				count = 1,
				mask  = 0xFFFFFFFF,
			},
		})

		offscreen_quad := []Vertex {
			//      positions               tex coords
			Vertex {Vec3 { 1.0,  1.0, 0.0}, Vec2 {1.0, 0.0}}, // top-right
			Vertex {Vec3 { 1.0, -1.0, 0.0}, Vec2 {1.0, 1.0}}, // bottom-right
			Vertex {Vec3 {-1.0,  1.0, 0.0}, Vec2 {0.0, 0.0}}, // top-left

			Vertex {Vec3 {-1.0,  1.0, 0.0}, Vec2 {0.0, 0.0}}, // top-left
			Vertex {Vec3 { 1.0, -1.0, 0.0}, Vec2 {1.0, 1.0}}, // bottom-right
			Vertex {Vec3 {-1.0, -1.0, 0.0}, Vec2 {0.0, 1.0}}, // bottom-left
		}
		offscreen_quad_buffer := model_load(offscreen_quad)

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

		instance.camera_position = Vec2{0.0, 0.0}
		instance.camera_angle = 0.0
		instance.camera_zoom = 1.0

		instance.projection_matrix = linalg.matrix_ortho3d_f32(
			0.0, 
			f32(instance.buffer_width), 
			0.0, 
			f32(instance.buffer_height),
			-1000.0, 
			1000.0,
			flip_z_axis=false
		)
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

	instance.draw_call = 0
}

draw :: proc(textured_model: ^TexturedModel, position: Vec2, origin: Vec2, angle: f32, flip: bool, scale: f32) {
	draw_textured_model(
		textured_model, 
		position, 
		origin, 
		angle, 
		flip, 
		scale, 
		instance.camera_zoom,
		Vec4{},
		false
	)
}

draw_colored :: proc(textured_model: ^TexturedModel, position: Vec2, origin: Vec2, angle: f32, flip: bool, scale: f32, color: Vec4) {
	draw_textured_model(
		textured_model, 
		position, 
		origin, 
		angle, 
		flip, 
		scale, 
		instance.camera_zoom,
		color,
		true
	)
}


draw_ui :: proc(textured_model: ^TexturedModel, position: Vec2, origin: Vec2, angle: f32, flip: bool, scale: f32) {
		draw_textured_model(
		textured_model, 
		position, 
		origin, 
		angle, 
		flip, 
		scale, 
		1.0,
		Vec4{},
		false
	)
}

draw_ui_colored :: proc(textured_model: ^TexturedModel, position: Vec2, origin: Vec2, angle: f32, flip: bool, scale: f32, color: Vec4) {
	draw_textured_model(
		textured_model, 
		position, 
		origin, 
		angle, 
		flip, 
		scale, 
		1.0,
		color,
		true
	)
}

@(private)
draw_textured_model :: proc(
	textured_model: ^TexturedModel, 
	position: Vec2, 
	origin: Vec2, 
	angle: f32, 
	flip: bool, 
	scale: f32, 
	zoom: f32, 
	color: Vec4, 
	use_color: bool
) {
	assert(textured_model != nil, "draw_textured_model: textured_model is nil")
	assert(textured_model.model.vertex_buffer != nil, "draw_textured_model: textured_model has no model")
	assert(textured_model.texture.texture != nil, "draw_textured_model: textured_model has no texture")

	mvp_matrix := create_mvp_matrix(position, origin, angle, scale, zoom)
	metadata := DrawCallMetadata {
		mvp = mvp_matrix,
		color = color,
		use_color = 1.0 if use_color else 0.0,
		flip_x = 1.0 if flip else 0.0,
		flip_y = 0.0,
	}

	render_textured_model(textured_model, &metadata)
}

@(private)
create_mvp_matrix :: proc(position: Vec2, origin: Vec2, angle: f32, scale: f32, zoom: f32) -> linalg.Matrix4x4f32 {
	RADIAN_MUL: f32 = math.PI / 180.0
	
	// Model = T(position) * Rz(angle) * S(scale) * T(-origin)
	model_matrix := linalg.matrix4_translate_f32(Vec3{position.x, position.y, 0.0})
	model_matrix = linalg.matrix_mul(model_matrix, linalg.matrix4_rotate_f32(angle * RADIAN_MUL, Vec3{0.0, 0.0, 1.0}))
	model_matrix = linalg.matrix_mul(model_matrix, linalg.matrix4_scale_f32(Vec3{scale, scale, 1.0}))
	model_matrix = linalg.matrix_mul(model_matrix, linalg.matrix4_translate_f32(Vec3{-origin.x, -origin.y, 0.0}))

	// View matrix
	frame_buffer_half_width := f32(instance.buffer_width) / 2.0
	frame_buffer_half_height := f32(instance.buffer_height) / 2.0
	view_matrix := linalg.matrix4_translate_f32(Vec3{-instance.camera_position.x + frame_buffer_half_width, -instance.camera_position.y + frame_buffer_half_height, 0.0})
	view_matrix = linalg.matrix_mul(view_matrix, linalg.matrix4_rotate_f32(instance.camera_angle * RADIAN_MUL, Vec3{0.0, 0.0, 1.0}))
	view_matrix = linalg.matrix_mul(view_matrix, linalg.matrix4_scale_f32(Vec3{zoom, zoom, 1.0}))

	// MVP
	mvp_matrix := linalg.matrix_mul(instance.projection_matrix, view_matrix)
	mvp_matrix = linalg.matrix_mul(mvp_matrix, model_matrix)

	return mvp_matrix
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

	wgpu.RenderPassEncoderSetPipeline(instance.render_pass_encoder, instance.pipeline)

	viewport_width, viewport_height := fit_rectangle_in_rectangle(
		f32(instance.buffer_width), f32(instance.buffer_height),
		f32(instance.window_width), f32(instance.window_height)
	)

	set_viewport(u32(viewport_width), u32(viewport_height), instance.window_width, instance.window_height)

	metadata := DrawCallMetadata {
		mvp = linalg.MATRIX4F32_IDENTITY,
		color = instance.screen_color_override,
		use_color = instance.use_screen_color_override ? 1.0 : 0.0,
		flip_x = 0.0,
		flip_y = 0.0,
	}

	// Render offscreen texture quad to screen
	render_textured_model(&instance.offscreen_quad, &metadata)

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
render_textured_model :: proc(textured_model: ^TexturedModel, draw_call_metadata: ^DrawCallMetadata) {
	wgpu.QueueWriteBuffer(
		instance.queue,
		instance.storage_buffer,
		instance.draw_call * size_of(DrawCallMetadata),
		rawptr(draw_call_metadata),
		size_of(DrawCallMetadata)
	)
	
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
		firstInstance=u32(instance.draw_call)
	)

	instance.draw_call += 1
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

set_camera_position :: proc(position: Vec2) {
	instance.camera_position = position
}

set_camera_angle :: proc(angle: f32) {
	instance.camera_angle = angle
}

set_camera_zoom :: proc(zoom: f32) {
	instance.camera_zoom = zoom
}

get_camera_position :: proc() -> Vec2 {
	return instance.camera_position
}

get_camera_angle :: proc() -> f32 {
	return instance.camera_angle
}

get_camera_zoom :: proc() -> f32 {
	return instance.camera_zoom
}

set_screen_color_override :: proc(color: Vec4) {
	instance.screen_color_override = color
	instance.use_screen_color_override = true
}

clear_screen_color_override :: proc() {
	instance.use_screen_color_override = false
}

get_framebuffer_width :: proc() -> u32 {
	return instance.buffer_width
}

get_framebuffer_height :: proc() -> u32 {
	return instance.buffer_height
}

cleanup :: proc() {
	// TODO: like who cares...
}