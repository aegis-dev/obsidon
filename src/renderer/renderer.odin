package renderer

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT :: 2

SHADER_VERT :: #load("shaders/scene.vert.spv")
SHADER_FRAG :: #load("shaders/scene.frag.spv")

// Enables Vulkan debug logging and validation layers.
ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, ODIN_DEBUG)
DEVICE_EXTENSIONS := []cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	// KHR_PORTABILITY_SUBSET_EXTENSION_NAME,
}

Renderer :: struct {
    instance: vk.Instance,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    surface: vk.SurfaceKHR,
    graphics_queue: vk.Queue,
    present_queue: vk.Queue,
    swapchain: vk.SwapchainKHR,
    swapchain_images: []vk.Image,
    swapchain_views: []vk.ImageView,
    swapchain_format: vk.SurfaceFormatKHR,
    swapchain_extent: vk.Extent2D,
    swapchain_frame_buffers: []vk.Framebuffer,
    vert_shader_module: vk.ShaderModule,
    frag_shader_module: vk.ShaderModule,
    shader_stages: [2]vk.PipelineShaderStageCreateInfo,
    render_pass: vk.RenderPass,
    pipeline_layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,
    command_pool: vk.CommandPool,
    command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
    image_available_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    render_finished_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    in_flight_fences: [MAX_FRAMES_IN_FLIGHT]vk.Fence,

    dbg_messenger: vk.DebugUtilsMessengerEXT,
}

renderer_init :: proc(window: glfw.WindowHandle, buffer_width: int, buffer_height: int) {
    renderer: Renderer

    vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))

    if vk.CreateInstance == nil {
        log.panic("vk: vulkan function pointers not loaded")
    }

    create_info := vk.InstanceCreateInfo {
		sType            = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &vk.ApplicationInfo {
			sType = .APPLICATION_INFO,
			pApplicationName = "",
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			pEngineName = "No Engine",
			engineVersion = vk.MAKE_VERSION(1, 0, 0),
			apiVersion = vk.API_VERSION_1_0,
		},
	}

    extensions := slice.clone_to_dynamic(glfw.GetRequiredInstanceExtensions(), context.temp_allocator)

    // MacOS is a special snowflake ;)
	when ODIN_OS == .Darwin {
		create_info.flags |= {.ENUMERATE_PORTABILITY_KHR}
		append(&extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

    when ENABLE_VALIDATION_LAYERS {
		create_info.ppEnabledLayerNames = raw_data([]cstring{"VK_LAYER_KHRONOS_validation"})
		create_info.enabledLayerCount = 1

		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		// Severity based on logger level.
		severity: vk.DebugUtilsMessageSeverityFlagsEXT
		if context.logger.lowest_level <= .Error {
			severity |= {.ERROR}
		}
		if context.logger.lowest_level <= .Warning {
			severity |= {.WARNING}
		}
		if context.logger.lowest_level <= .Info {
			severity |= {.INFO}
		}
		if context.logger.lowest_level <= .Debug {
			severity |= {.VERBOSE}
		}

		dbg_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = severity,
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING}, // all of them.
			pfnUserCallback = vk_messenger_callback,
		}
		create_info.pNext = &dbg_create_info
	}

    create_info.enabledExtensionCount = u32(len(extensions))
	create_info.ppEnabledExtensionNames = raw_data(extensions)

    must(vk.CreateInstance(&create_info, nil, &renderer.instance))

    vk.load_proc_addresses_instance(renderer.instance)

    when ENABLE_VALIDATION_LAYERS {
		must(vk.CreateDebugUtilsMessengerEXT(renderer.instance, &dbg_create_info, nil, &renderer.dbg_messenger))
	}

    must(glfw.CreateWindowSurface(renderer.instance, window, nil, &renderer.surface))

    must(pick_physical_device(&renderer))

    indices := find_queue_families(renderer.physical_device, renderer.surface)
	{
		// TODO: this is kinda messy.
		indices_set := make(map[u32]struct {}, allocator = context.temp_allocator)
		indices_set[indices.graphics.?] = {}
		indices_set[indices.present.?] = {}

		queue_create_infos := make([dynamic]vk.DeviceQueueCreateInfo, 0, len(indices_set), context.temp_allocator)
		for _ in indices_set {
			append(
				&queue_create_infos,
				vk.DeviceQueueCreateInfo {
					sType = .DEVICE_QUEUE_CREATE_INFO,
					queueFamilyIndex = indices.graphics.?,
					queueCount = 1,
					pQueuePriorities = raw_data([]f32{1}),
				},// Scheduling priority between 0 and 1.
			)
		}

		device_create_info := vk.DeviceCreateInfo {
			sType                   = .DEVICE_CREATE_INFO,
			pQueueCreateInfos       = raw_data(queue_create_infos),
			queueCreateInfoCount    = u32(len(queue_create_infos)),
			enabledLayerCount       = create_info.enabledLayerCount,
			ppEnabledLayerNames     = create_info.ppEnabledLayerNames,
			ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
			enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
		}

		must(vk.CreateDevice(renderer.physical_device, &device_create_info, nil, &renderer.device))

		vk.GetDeviceQueue(renderer.device, indices.graphics.?, 0, &renderer.graphics_queue)
		vk.GetDeviceQueue(renderer.device, indices.present.?, 0, &renderer.present_queue)
	}

    create_swapchain(&renderer, window)

    // Load shaders.
	{
		renderer.vert_shader_module = create_shader_module(renderer, SHADER_VERT)
		renderer.shader_stages[0] = vk.PipelineShaderStageCreateInfo {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.VERTEX},
			module = renderer.vert_shader_module,
			pName  = "main",
		}

		renderer.frag_shader_module = create_shader_module(renderer, SHADER_FRAG)
		renderer.shader_stages[1] = vk.PipelineShaderStageCreateInfo {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.FRAGMENT},
			module = renderer.frag_shader_module,
			pName  = "main",
		}
	}

    // Set up render pass.
	{
		color_attachment := vk.AttachmentDescription {
			format         = renderer.swapchain_format.format,
			samples        = {._1},
			loadOp         = .CLEAR,
			storeOp        = .STORE,
			stencilLoadOp  = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout  = .UNDEFINED,
			finalLayout    = .PRESENT_SRC_KHR,
		}

		color_attachment_ref := vk.AttachmentReference {
			attachment = 0,
			layout     = .COLOR_ATTACHMENT_OPTIMAL,
		}

		subpass := vk.SubpassDescription {
			pipelineBindPoint    = .GRAPHICS,
			colorAttachmentCount = 1,
			pColorAttachments    = &color_attachment_ref,
		}

		dependency := vk.SubpassDependency {
			srcSubpass    = vk.SUBPASS_EXTERNAL,
			dstSubpass    = 0,
			srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
			srcAccessMask = {},
			dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
			dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		}

		render_pass := vk.RenderPassCreateInfo {
			sType           = .RENDER_PASS_CREATE_INFO,
			attachmentCount = 1,
			pAttachments    = &color_attachment,
			subpassCount    = 1,
			pSubpasses      = &subpass,
			dependencyCount = 1,
			pDependencies   = &dependency,
		}

		must(vk.CreateRenderPass(renderer.device, &render_pass, nil, &renderer.render_pass))
	}

    create_framebuffers(&renderer)

    // Set up pipeline.
	{
		dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
		dynamic_state := vk.PipelineDynamicStateCreateInfo {
			sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			dynamicStateCount = 2,
			pDynamicStates    = raw_data(dynamic_states),
		}

		vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		}

		input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
			sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			topology = .TRIANGLE_LIST,
		}

		viewport_state := vk.PipelineViewportStateCreateInfo {
			sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			viewportCount = 1,
			scissorCount  = 1,
		}

		rasterizer := vk.PipelineRasterizationStateCreateInfo {
			sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			polygonMode = .FILL,
			lineWidth   = 1,
			cullMode    = {.BACK},
			frontFace   = .CLOCKWISE,
		}

		multisampling := vk.PipelineMultisampleStateCreateInfo {
			sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			rasterizationSamples = {._1},
			minSampleShading     = 1,
		}

		color_blend_attachment := vk.PipelineColorBlendAttachmentState {
			colorWriteMask = {.R, .G, .B, .A},
		}

		color_blending := vk.PipelineColorBlendStateCreateInfo {
			sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			attachmentCount = 1,
			pAttachments    = &color_blend_attachment,
		}

		pipeline_layout := vk.PipelineLayoutCreateInfo {
			sType = .PIPELINE_LAYOUT_CREATE_INFO,
		}
		must(vk.CreatePipelineLayout(renderer.device, &pipeline_layout, nil, &renderer.pipeline_layout))

        // TODO:
		pipeline := vk.GraphicsPipelineCreateInfo {
			sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
			stageCount          = 2,
			pStages             = &g_shader_stages[0],
			pVertexInputState   = &vertex_input_info,
			pInputAssemblyState = &input_assembly,
			pViewportState      = &viewport_state,
			pRasterizationState = &rasterizer,
			pMultisampleState   = &multisampling,
			pColorBlendState    = &color_blending,
			pDynamicState       = &dynamic_state,
			layout              = g_pipeline_layout,
			renderPass          = g_render_pass,
			subpass             = 0,
			basePipelineIndex   = -1,
		}
		must(vk.CreateGraphicsPipelines(g_device, 0, 1, &pipeline, nil, &g_pipeline))
	}
}

renderer_cleanup :: proc(renderer: Renderer) {
    destroy_framebuffers(renderer);
    vk.DestroyRenderPass(renderer.device, renderer.render_pass, nil)
	vk.DestroyShaderModule(renderer.device, renderer.frag_shader_module, nil)
    vk.DestroyShaderModule(renderer.device, renderer.vert_shader_module, nil)
    destroy_swapchain(renderer)
    vk.DestroyDevice(renderer.device, nil)
    vk.DestroySurfaceKHR(renderer.instance, renderer.surface, nil)
    when ENABLE_VALIDATION_LAYERS {
		vk.DestroyDebugUtilsMessengerEXT(renderer.instance, renderer.dbg_messenger, nil)
	}
    vk.DestroyInstance(renderer.instance, nil)
}

@(private)
@(require_results)
pick_physical_device :: proc(renderer: ^Renderer) -> vk.Result {
	count: u32
	vk.EnumeratePhysicalDevices(renderer.instance, &count, nil) or_return
	if count == 0 {log.panic("vulkan: no GPU found")}

	devices := make([]vk.PhysicalDevice, count, context.temp_allocator)
	vk.EnumeratePhysicalDevices(renderer.instance, &count, raw_data(devices)) or_return

	best_device_score := -1
	for device in devices {
		if score := score_physical_device(device, renderer.surface); score > best_device_score {
			renderer.physical_device = device
			best_device_score = score
		}
	}

	if best_device_score <= 0 {
		log.panic("vulkan: no suitable GPU found")
	}
	return .SUCCESS
}

@(private)
score_physical_device :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (score: int) {
    props: vk.PhysicalDeviceProperties
    vk.GetPhysicalDeviceProperties(device, &props)

    name := byte_arr_str(&props.deviceName)
    log.infof("vulkan: evaluating device %q", name)
    defer log.infof("vulkan: device %q scored %v", name, score)

    features: vk.PhysicalDeviceFeatures
    vk.GetPhysicalDeviceFeatures(device, &features)

    // // App can't function without geometry shaders.
    // if !features.geometryShader {
    // 	log.info("vulkan: device does not support geometry shaders")
    // 	return 0
    // }

    // Need certain extensions supported.
    {
        extensions, result := physical_device_extensions(device, context.temp_allocator)
        if result != .SUCCESS {
            log.infof("vulkan: enumerate device extension properties failed: %v", result)
            return 0
        }

        required_loop: for required in DEVICE_EXTENSIONS {
            for &extension in extensions {
                extension_name := byte_arr_str(&extension.extensionName)
                if extension_name == string(required) {
                    continue required_loop
                }
            }

            log.infof("vulkan: device does not support required extension %q", required)
            return 0
        }
    }

    // Check if swapchain is adequately supported.
    {
        support, result := query_swapchain_support(device, surface, context.temp_allocator)
        if result != .SUCCESS {
            log.infof("vulkan: query swapchain support failure: %v", result)
            return 0
        }

        // Need at least a format and present mode.
        if len(support.formats) == 0 || len(support.presentModes) == 0 {
            log.info("vulkan: device does not support swapchain")
            return 0
        }
    }

    families := find_queue_families(device, surface)
    if _, has_graphics := families.graphics.?; !has_graphics {
        log.info("vulkan: device does not have a graphics queue")
        return 0
    }
    if _, has_present := families.present.?; !has_present {
        log.info("vulkan: device does not have a presentation queue")
        return 0
    }

    // Favor GPUs.
    switch props.deviceType {
    case .DISCRETE_GPU:
        score += 300_000
    case .INTEGRATED_GPU:
        score += 200_000
    case .VIRTUAL_GPU:
        score += 100_000
    case .CPU, .OTHER:
    }
    log.infof("vulkan: scored %i based on device type %v", score, props.deviceType)

    // Maximum texture size.
    score += int(props.limits.maxImageDimension2D)
    log.infof(
        "vulkan: added the max 2D image dimensions (texture size) of %v to the score",
        props.limits.maxImageDimension2D,
    )
    return
}

@(private)
physical_device_extensions :: proc(
	device: vk.PhysicalDevice,
	allocator := context.temp_allocator,
) -> (
	exts: []vk.ExtensionProperties,
	res: vk.Result,
) {
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil) or_return

	exts = make([]vk.ExtensionProperties, count, allocator)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(exts)) or_return

	return
}

@(private)
Queue_Family_Indices :: struct {
	graphics: Maybe(u32),
	present:  Maybe(u32),
}

@(private)
find_queue_families :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (ids: Queue_Family_Indices) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)

	families := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))

	for family, i in families {
		if .GRAPHICS in family.queueFlags {
			ids.graphics = u32(i)
		}

		supported: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &supported)
		if supported {
			ids.present = u32(i)
		}

		// Found all needed queues?
		_, has_graphics := ids.graphics.?
		_, has_present := ids.present.?
		if has_graphics && has_present {
			break
		}
	}

	return
}

@(private)
Swapchain_Support :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
	presentModes: []vk.PresentModeKHR,
}

@(private)
query_swapchain_support :: proc(
	device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
	allocator := context.temp_allocator,
) -> (
	support: Swapchain_Support,
	result: vk.Result,
) {
	// NOTE: looks like a wrong binding with the third arg being a multipointer.
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &support.capabilities) or_return

	{
		count: u32
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, nil) or_return

		support.formats = make([]vk.SurfaceFormatKHR, count, allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, raw_data(support.formats)) or_return
	}

	{
		count: u32
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &count, nil) or_return

		support.presentModes = make([]vk.PresentModeKHR, count, allocator)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &count, raw_data(support.presentModes)) or_return
	}

	return
}

@(private)
choose_swapchain_surface_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for format in formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}

	// Fallback non optimal.
	return formats[0]
}

@(private)
choose_swapchain_present_mode :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	// We would like mailbox for the best tradeoff between tearing and latency.
	for mode in modes {
		if mode == .MAILBOX {
			return .MAILBOX
		}
	}

	// As a fallback, fifo (basically vsync) is always available.
	return .FIFO
}

@(private)
choose_swapchain_extent :: proc(window: glfw.WindowHandle, capabilities: vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	width, height := glfw.GetFramebufferSize(window)
	return(
		vk.Extent2D {
			width = clamp(u32(width), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
			height = clamp(u32(height), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
		} \
	)
}

@(private)
create_swapchain :: proc(renderer: ^Renderer, window: glfw.WindowHandle) {
	indices := find_queue_families(renderer.physical_device, renderer.surface)

	// Setup swapchain.
	{
		support, result := query_swapchain_support(renderer.physical_device, renderer.surface, context.temp_allocator)
		if result != .SUCCESS {
			log.panicf("vulkan: query swapchain failed: %v", result)
		}

		surface_format := choose_swapchain_surface_format(support.formats)
		present_mode := choose_swapchain_present_mode(support.presentModes)
		extent := choose_swapchain_extent(window, support.capabilities)

		renderer.swapchain_format = surface_format
		renderer.swapchain_extent = extent

		image_count := support.capabilities.minImageCount + 1
		if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
			image_count = support.capabilities.maxImageCount
		}

		create_info := vk.SwapchainCreateInfoKHR {
			sType            = .SWAPCHAIN_CREATE_INFO_KHR,
			surface          = renderer.surface,
			minImageCount    = image_count,
			imageFormat      = surface_format.format,
			imageColorSpace  = surface_format.colorSpace,
			imageExtent      = extent,
			imageArrayLayers = 1,
			imageUsage       = {.COLOR_ATTACHMENT},
			preTransform     = support.capabilities.currentTransform,
			compositeAlpha   = {.OPAQUE},
			presentMode      = present_mode,
			clipped          = true,
		}

		if indices.graphics != indices.present {
			create_info.imageSharingMode = .CONCURRENT
			create_info.queueFamilyIndexCount = 2
			create_info.pQueueFamilyIndices = raw_data([]u32{indices.graphics.?, indices.present.?})
		}

		must(vk.CreateSwapchainKHR(renderer.device, &create_info, nil, &renderer.swapchain))
	}

	// Setup swapchain images.
	{
		count: u32
		must(vk.GetSwapchainImagesKHR(renderer.device, renderer.swapchain, &count, nil))

		renderer.swapchain_images = make([]vk.Image, count)
		renderer.swapchain_views = make([]vk.ImageView, count)
		must(vk.GetSwapchainImagesKHR(renderer.device, renderer.swapchain, &count, raw_data(renderer.swapchain_images)))

		for image, i in renderer.swapchain_images {
			create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = image,
				viewType = .D2,
				format = renderer.swapchain_format.format,
				subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
			}
			must(vk.CreateImageView(renderer.device, &create_info, nil, &renderer.swapchain_views[i]))
		}
	}
}

@(private)
destroy_swapchain :: proc(renderer: Renderer) {
	for view in renderer.swapchain_views {
		vk.DestroyImageView(renderer.device, view, nil)
	}
	delete(renderer.swapchain_views)
	delete(renderer.swapchain_images)
	vk.DestroySwapchainKHR(renderer.device, renderer.swapchain, nil)
}

@(private)
create_shader_module :: proc(renderer: Renderer, code: []byte) -> (module: vk.ShaderModule) {
	as_u32 := slice.reinterpret([]u32, code)

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = raw_data(as_u32),
	}
	must(vk.CreateShaderModule(renderer.device, &create_info, nil, &module))
	return
}

@(private)
create_framebuffers :: proc(renderer: ^Renderer) {
	renderer.swapchain_frame_buffers = make([]vk.Framebuffer, len(renderer.swapchain_views))
	for view, i in renderer.swapchain_views {
		attachments := []vk.ImageView{view}

		frame_buffer := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = renderer.render_pass,
			attachmentCount = 1,
			pAttachments    = raw_data(attachments),
			width           = renderer.swapchain_extent.width,
			height          = renderer.swapchain_extent.height,
			layers          = 1,
		}
		must(vk.CreateFramebuffer(renderer.device, &frame_buffer, nil, &renderer.swapchain_frame_buffers[i]))
	}
}

@(private)
destroy_framebuffers :: proc(renderer: Renderer) {
	for frame_buffer in renderer.swapchain_frame_buffers {vk.DestroyFramebuffer(renderer.device, frame_buffer, nil)}
	delete(renderer.swapchain_frame_buffers)
}

@(private)
byte_arr_str :: proc(arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}

@(private)
must :: proc(result: vk.Result, loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vk: Error: %v", result, location = loc)
	}
}