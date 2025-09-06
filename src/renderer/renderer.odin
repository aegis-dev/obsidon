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

		vertex_buffer_layout := wgpu.VertexBufferLayout {
			arrayStride    = size_of(Vec3) + size_of(Vec2), // 3 floats + 2 floats
			stepMode       = .Vertex,
			attributeCount = 2,
			attributes     = &[_]wgpu.VertexAttribute{
				wgpu.VertexAttribute{ format = .Float32x3, offset = 0,                                   shaderLocation = 0 },
				wgpu.VertexAttribute{ format = .Float32x2, offset = size_of(Vec3), shaderLocation = 1 },
			},
		}

		instance.pipeline_layout = wgpu.DeviceCreatePipelineLayout(instance.device, &{})
		instance.pipeline = wgpu.DeviceCreateRenderPipeline(instance.device, &{
			layout = instance.pipeline_layout,
			vertex = {
				module     = instance.module,
				entryPoint = "vs_main",
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

cleanup :: proc() {

}