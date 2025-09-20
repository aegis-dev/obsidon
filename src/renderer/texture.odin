package renderer

import "core:image/png"
import "core:log"

import "vendor:wgpu"

Texture :: struct {
    width: u32,
    height: u32,
    texture: wgpu.Texture,
    view: wgpu.TextureView,
    bind_group: wgpu.BindGroup,
}

texture_load_from_png_bytes :: proc(png_data: []u8) -> Texture {
	image, err := png.load_from_bytes(png_data)
	if err != nil {
		log.panic("Failed to load PNG image")
	}
	defer png.destroy(image)

	return texture_load_from_raw_pixels(image.pixels.buf[:], u32(image.width), u32(image.height))
}

texture_load_from_raw_pixels :: proc(pixels: []u8, width: u32, height: u32) -> Texture {
    // Create texture
    texture := wgpu.DeviceCreateTexture(instance.device, &{
        size = wgpu.Extent3D{ width = width, height = height, depthOrArrayLayers = 1 },
        format = .RGBA8Unorm,
        usage = { .TextureBinding, .CopyDst },
        mipLevelCount = 1,
        sampleCount = 1,
    })
    texture_view := wgpu.TextureCreateView(texture, nil)

    // Upload texture data
    row_pitch := u32(4 * width) // 4 bytes per pixel (RGBA)
    data_size := row_pitch * height

    destination_info := wgpu.TexelCopyTextureInfo{
        texture   = texture,
        mipLevel  = 0,
        origin    = wgpu.Origin3D{0, 0, 0},
        aspect    = .All,
    }

    data_layout := wgpu.TexelCopyBufferLayout{
        offset        = 0,
        bytesPerRow   = row_pitch,
        rowsPerImage  = height,
    }

    write_size_info := wgpu.Extent3D{
        width         = width,
        height        = height,
        depthOrArrayLayers = 1,
    }

    wgpu.QueueWriteTexture(instance.queue, &destination_info, &pixels[0], uint(data_size), &data_layout, &write_size_info)

    return create_texture_from_texture_and_texture_view(texture, texture_view, width, height)
}

texture_destroy :: proc(texture: ^Texture) {
    wgpu.BindGroupRelease(texture.bind_group)
    wgpu.TextureViewRelease(texture.view)
    wgpu.TextureDestroy(texture.texture)
}

@(private)
create_texture_from_texture_and_texture_view :: proc(texture: wgpu.Texture, texture_view: wgpu.TextureView, width: u32, height: u32) -> Texture {
	// Create a bind group for the texture and sampler
	bind_group_entries := [3]wgpu.BindGroupEntry {
		{
			binding = 0,
			textureView = texture_view,
		},
		{
			binding = 1,
			sampler = instance.sampler,
		},
		{
			binding = 2,
			buffer = instance.storage_buffer,
			offset = 0,
			size   = MAX_DRAW_CALLS * size_of(DrawCallMetadata),
		}
	}

	bind_group := wgpu.DeviceCreateBindGroup(instance.device, &wgpu.BindGroupDescriptor{
		layout = instance.bind_group_layout,
		entryCount = len(bind_group_entries),
		entries = &bind_group_entries[0],
	})

	return Texture {width, height, texture, texture_view, bind_group}
}
