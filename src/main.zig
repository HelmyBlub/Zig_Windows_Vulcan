const std = @import("std");
const zigWin32 = @import("zigwin32");
const zigWin32Everything = zigWin32.everything;
const ui = zigWin32.ui.windows_and_messaging;
const vulcan = @import("vulkan"); // not used, as i do not know how to get win32 plattform stuff
const vk = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", "1");
    @cInclude("vulkan.h");
});
const zigimg = @import("zigimg");

// tasks:
// - problem: image alpha channel not working
// follow vulcan tutorial:
//    - continue https://docs.vulkan.org/tutorial/latest/07_Depth_buffering.html
//      - someone elses repo as refrence: https://github.com/JamDeezCodes/zig-vulkan-tutorial/blob/bac607a08c2c72e404bec6de3053f50afc7f64ed/src/main.zig#L2468
// next goal: draw 10_000 images to screen
//           - want to know some limit with vulcan so i can compare to my sdl version
//
// - problem: zigimg not working with zig 0.14 and loading images
//    - currently fixed by manually changing files only locally without git behind it

const Vk_State = struct {
    window: vk.HWND = undefined,
    hInstance: vk.HINSTANCE = undefined,
    instance: vk.VkInstance = undefined,
    surface: vk.VkSurfaceKHR = undefined,
    graphics_queue_family_idx: u32 = undefined,
    physical_device: vk.VkPhysicalDevice = undefined,
    logicalDevice: vk.VkDevice = undefined,
    queue: vk.VkQueue = undefined,
    swapchain: vk.VkSwapchainKHR = undefined,
    swapchain_info: struct {
        support: SwapChainSupportDetails = undefined,
        format: vk.VkSurfaceFormatKHR = undefined,
        present: vk.VkPresentModeKHR = undefined,
        extent: vk.VkExtent2D = undefined,
        images: []vk.VkImage = &.{},
    } = undefined,
    swapchain_imageviews: []vk.VkImageView = undefined,
    render_pass: vk.VkRenderPass = undefined,
    pipeline_layout: vk.VkPipelineLayout = undefined,
    graphics_pipeline: vk.VkPipeline = undefined,
    framebuffers: []vk.VkFramebuffer = undefined,
    command_pool: vk.VkCommandPool = undefined,
    command_buffer: []vk.VkCommandBuffer = undefined,
    imageAvailableSemaphore: []vk.VkSemaphore = undefined,
    renderFinishedSemaphore: []vk.VkSemaphore = undefined,
    inFlightFence: []vk.VkFence = undefined,
    currentFrame: u16 = 0,
    vertexBuffer: vk.VkBuffer = undefined,
    vertexBufferMemory: vk.VkDeviceMemory = undefined,
    descriptorSetLayout: vk.VkDescriptorSetLayout = undefined,
    uniformBuffers: []vk.VkBuffer = undefined,
    uniformBuffersMemory: []vk.VkDeviceMemory = undefined,
    uniformBuffersMapped: []?*anyopaque = undefined,
    descriptorPool: vk.VkDescriptorPool = undefined,
    descriptorSets: []vk.VkDescriptorSet = undefined,
    textureImage: vk.VkImage = undefined,
    textureImageMemory: vk.VkDeviceMemory = undefined,
    textureImageView: vk.VkImageView = undefined,
    textureSampler: vk.VkSampler = undefined,
    const MAX_FRAMES_IN_FLIGHT: u16 = 2;
};

const UniformBufferObject = struct {
    transform: [4][4]f32,
};

const SwapChainSupportDetails = struct {
    capabilities: vk.VkSurfaceCapabilitiesKHR,
    formats: []vk.VkSurfaceFormatKHR,
    presentModes: []vk.VkPresentModeKHR,
};

const Vertex = struct {
    pos: [2]f32,
    color: [3]f32,
    texCoord: [2]f32,

    fn getBindingDescription() vk.VkVertexInputBindingDescription {
        const bindingDescription: vk.VkVertexInputBindingDescription = .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        return bindingDescription;
    }

    fn getAttributeDescriptions() [3]vk.VkVertexInputAttributeDescription {
        var attributeDescriptions: [3]vk.VkVertexInputAttributeDescription = .{ undefined, undefined, undefined };
        attributeDescriptions[0].binding = 0;
        attributeDescriptions[0].location = 0;
        attributeDescriptions[0].format = vk.VK_FORMAT_R32G32_SFLOAT;
        attributeDescriptions[0].offset = @offsetOf(Vertex, "pos");
        attributeDescriptions[1].binding = 0;
        attributeDescriptions[1].location = 1;
        attributeDescriptions[1].format = vk.VK_FORMAT_R32G32B32_SFLOAT;
        attributeDescriptions[1].offset = @offsetOf(Vertex, "color");
        attributeDescriptions[2].binding = 0;
        attributeDescriptions[2].location = 2;
        attributeDescriptions[2].format = vk.VK_FORMAT_R32G32_SFLOAT;
        attributeDescriptions[2].offset = @offsetOf(Vertex, "texCoord");
        return attributeDescriptions;
    }
};

var vertices: []Vertex = undefined;

pub fn main() !void {
    std.debug.print("start\n", .{});
    std.debug.print("validation layer support: {}\n", .{checkValidationLayerSupport()});
    try setupVertices();
    var vkState: Vk_State = .{};
    try initWindow(&vkState);
    try initVulkan(&vkState);
    try mainLoop(&vkState);
    try destroy(&vkState);
    std.debug.print("done\n", .{});
}

fn setupVertices() !void {
    const rows = 10;
    const columns = 10;
    const triangleCount = rows * columns;
    const vertexCount = triangleCount * 3;
    const triangleSize = 0.1;
    vertices = try std.heap.page_allocator.alloc(Vertex, vertexCount);
    const stepSizeX: f32 = 2.0 / @as(f32, @floatFromInt(columns));
    const stepSizeY: f32 = 2.0 / @as(f32, @floatFromInt(rows));
    for (0..columns) |x| {
        const currX = -1.0 + stepSizeX * @as(f32, @floatFromInt(x));
        for (0..rows) |y| {
            const currY = -1.0 + stepSizeY * @as(f32, @floatFromInt(y));
            vertices[(x * rows + y) * 3] = .{ .pos = .{ currX, currY }, .color = .{ 1.0, 0.0, 0.0 }, .texCoord = .{ 0.3, 0.3 } };
            vertices[(x * rows + y) * 3 + 1] = .{ .pos = .{ currX + triangleSize, currY + triangleSize }, .color = .{ 1.0, 0.0, 0.0 }, .texCoord = .{ 0.7, 0.7 } };
            vertices[(x * rows + y) * 3 + 2] = .{ .pos = .{ currX, currY + triangleSize }, .color = .{ 1.0, 0.0, 0.0 }, .texCoord = .{ 0.3, 0.7 } };
        }
    }
    std.debug.print("verticeCount: {}\n", .{vertices.len});
}

fn mainLoop(vkState: *Vk_State) !void {
    std.time.sleep(500_000_000);
    var counter: u32 = 0;
    const startTime = std.time.microTimestamp();
    const maxCounter = 2000;
    try setupVertexDataForGPU(vkState);

    while (counter < maxCounter) {
        counter += 1;
        tick();
        try drawFrame(vkState);
        // std.time.sleep(10_000_000);
    }
    const timePassed = std.time.microTimestamp() - startTime;
    const fps = @divTrunc(maxCounter * 1_000_000, timePassed);
    std.debug.print("fps: {}, timePassed: {}\n", .{ fps, timePassed });
    std.time.sleep(2_000_000_000);
    _ = vk.vkDeviceWaitIdle(vkState.logicalDevice);
}

fn tick() void {
    // vertices[0].pos[0] += 0.0005;
}

fn initWindow(vkState: *Vk_State) !void {
    const hInstance = zigWin32Everything.GetModuleHandleW(null);
    const className = std.unicode.utf8ToUtf16LeStringLiteral("className");
    const title = std.unicode.utf8ToUtf16LeStringLiteral("title");
    {
        const class: ui.WNDCLASSW = .{
            .style = .{},
            .lpfnWndProc = wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hInstance,
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = className,
        };
        if (ui.RegisterClassW(&class) == 0) return error.FailedToRegisterClass;
    }
    const hwnd = ui.CreateWindowExW(
        .{},
        className,
        title,
        .{},
        10,
        10,
        1600,
        800,
        null,
        null,
        hInstance,
        null,
    ) orelse {
        std.debug.print("[!] CreateWindowExW Failed With Error : {}\n", .{zigWin32Everything.GetLastError()});
        return error.Unexpected;
    };

    _ = ui.ShowWindow(hwnd, ui.SW_SHOW);

    vkState.hInstance = vk.GetModuleHandleA(null);
    vkState.window = vk.FindWindowA("className", "title");
}

fn initVulkan(vkState: *Vk_State) !void {
    try createInstance(vkState);
    try createSurface(vkState);
    vkState.physical_device = try pickPhysicalDevice(vkState.instance, vkState);
    try createLogicalDevice(vkState.physical_device, vkState);
    try createSwapChain(vkState);
    try createImageViews(vkState);
    try createRenderPass(vkState);
    try createDescriptorSetLayout(vkState);
    try createGraphicsPipeline(vkState);
    try createFramebuffers(vkState);
    try createCommandPool(vkState);
    try createTextureImage(vkState);
    try createTextureImageView(vkState);
    try createTextureSampler(vkState);
    try createVertexBuffer(vkState);
    try createUniformBuffers(vkState);
    try createDescriptorPool(vkState);
    try createDescriptorSets(vkState);
    try createCommandBuffers(vkState);
    try createSyncObjects(vkState);
}

fn createTextureSampler(vkState: *Vk_State) !void {
    var properties: vk.VkPhysicalDeviceProperties = undefined;
    vk.vkGetPhysicalDeviceProperties(vkState.physical_device, &properties);
    const samplerInfo: vk.VkSamplerCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = vk.VK_FILTER_LINEAR,
        .minFilter = vk.VK_FILTER_LINEAR,
        .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        .anisotropyEnable = vk.VK_TRUE,
        .maxAnisotropy = properties.limits.maxSamplerAnisotropy,
        .borderColor = vk.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = vk.VK_FALSE,
        .compareEnable = vk.VK_FALSE,
        .compareOp = vk.VK_COMPARE_OP_ALWAYS,
        .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .mipLodBias = 0.0,
        .minLod = 0.0,
        .maxLod = 0.0,
    };
    if (vk.vkCreateSampler(vkState.logicalDevice, &samplerInfo, null, &vkState.textureSampler) != vk.VK_SUCCESS) return error.createSampler;
}

fn createTextureImageView(vkState: *Vk_State) !void {
    vkState.textureImageView = try createImageView(vkState.textureImage, vk.VK_FORMAT_R8G8B8A8_SRGB, vkState);
}

fn createImageView(image: vk.VkImage, format: vk.VkFormat, vkState: *Vk_State) !vk.VkImageView {
    const viewInfo: vk.VkImageViewCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var imageView: vk.VkImageView = undefined;
    if (vk.vkCreateImageView(vkState.logicalDevice, &viewInfo, null, &imageView) != vk.VK_SUCCESS) return error.createImageView;
    return imageView;
}

fn createTextureImage(vkState: *Vk_State) !void {
    var image = try zigimg.Image.fromFilePath(std.heap.page_allocator, "src/test.png");
    defer image.deinit();
    try image.convert(.rgba32);

    var stagingBuffer: vk.VkBuffer = undefined;
    var stagingBufferMemory: vk.VkDeviceMemory = undefined;
    try createBuffer(
        image.imageByteSize(),
        vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &stagingBuffer,
        &stagingBufferMemory,
        vkState,
    );

    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, stagingBufferMemory, 0, image.imageByteSize(), 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    @memcpy(
        @as([*]u8, @ptrCast(data))[0..image.imageByteSize()],
        @as([*]u8, @ptrCast(image.pixels.asBytes())),
    );
    vk.vkUnmapMemory(vkState.logicalDevice, stagingBufferMemory);
    const imageWidth: u32 = @intCast(image.width);
    const imageHeight: u32 = @intCast(image.height);
    try createImage(
        imageWidth,
        imageHeight,
        vk.VK_FORMAT_R8G8B8A8_SRGB,
        vk.VK_IMAGE_TILING_OPTIMAL,
        vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
        vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        &vkState.textureImage,
        &vkState.textureImageMemory,
        vkState,
    );

    try transitionImageLayout(vkState.textureImage, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vkState);
    try copyBufferToImage(stagingBuffer, vkState.textureImage, imageWidth, imageHeight, vkState);
    try transitionImageLayout(vkState.textureImage, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, vkState);
    vk.vkDestroyBuffer(vkState.logicalDevice, stagingBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, stagingBufferMemory, null);
}

fn copyBufferToImage(buffer: vk.VkBuffer, image: vk.VkImage, width: u32, height: u32, vkState: *Vk_State) !void {
    const commandBuffer: vk.VkCommandBuffer = try beginSingleTimeCommands(vkState);
    const region: vk.VkBufferImageCopy = .{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = width, .height = height, .depth = 1 },
    };
    vk.vkCmdCopyBufferToImage(
        commandBuffer,
        buffer,
        image,
        vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &region,
    );

    try endSingleTimeCommands(commandBuffer, vkState);
}

fn transitionImageLayout(image: vk.VkImage, oldLayout: vk.VkImageLayout, newLayout: vk.VkImageLayout, vkState: *Vk_State) !void {
    const commandBuffer = try beginSingleTimeCommands(vkState);

    var barrier: vk.VkImageMemoryBarrier = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = oldLayout,
        .newLayout = newLayout,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .srcAccessMask = 0, // TODO
        .dstAccessMask = 0, // TODO
    };

    var sourceStage: vk.VkPipelineStageFlags = undefined;
    var destinationStage: vk.VkPipelineStageFlags = undefined;

    if (oldLayout == vk.VK_IMAGE_LAYOUT_UNDEFINED and newLayout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;

        sourceStage = vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destinationStage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (oldLayout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and newLayout == vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;

        sourceStage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
        destinationStage = vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else {
        return error.unsuportetLayoutTransition;
    }

    vk.vkCmdPipelineBarrier(
        commandBuffer,
        0,
        0,
        0,
        0,
        null,
        0,
        null,
        1,
        &barrier,
    );
    try endSingleTimeCommands(commandBuffer, vkState);
}

fn beginSingleTimeCommands(vkState: *Vk_State) !vk.VkCommandBuffer {
    const allocInfo: vk.VkCommandBufferAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandPool = vkState.command_pool,
        .commandBufferCount = 1,
    };

    var commandBuffer: vk.VkCommandBuffer = undefined;
    _ = vk.vkAllocateCommandBuffers(vkState.logicalDevice, &allocInfo, &commandBuffer);

    const beginInfo: vk.VkCommandBufferBeginInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };

    _ = vk.vkBeginCommandBuffer(commandBuffer, &beginInfo);

    return commandBuffer;
}

fn endSingleTimeCommands(commandBuffer: vk.VkCommandBuffer, vkState: *Vk_State) !void {
    _ = vk.vkEndCommandBuffer(commandBuffer);

    const submitInfo: vk.VkSubmitInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &commandBuffer,
    };

    _ = vk.vkQueueSubmit(vkState.queue, 1, &submitInfo, null);
    _ = vk.vkQueueWaitIdle(vkState.queue);

    vk.vkFreeCommandBuffers(vkState.logicalDevice, vkState.command_pool, 1, &commandBuffer);
}

fn createImage(width: u32, height: u32, format: vk.VkFormat, tiling: vk.VkImageTiling, usage: vk.VkImageUsageFlags, properties: vk.VkMemoryPropertyFlags, image: *vk.VkImage, imageMemory: *vk.VkDeviceMemory, vkState: *Vk_State) !void {
    const imageInfo: vk.VkImageCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .extent = .{
            .width = width,
            .height = height,
            .depth = 1,
        },
        .mipLevels = 1,
        .arrayLayers = 1,
        .format = format,
        .tiling = tiling,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .usage = usage,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .flags = 0,
    };

    if (vk.vkCreateImage(vkState.logicalDevice, &imageInfo, null, image) != vk.VK_SUCCESS) return error.createImage;

    var memRequirements: vk.VkMemoryRequirements = undefined;
    vk.vkGetImageMemoryRequirements(vkState.logicalDevice, image.*, &memRequirements);

    const allocInfo: vk.VkMemoryAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = memRequirements.size,
        .memoryTypeIndex = try findMemoryType(memRequirements.memoryTypeBits, properties, vkState),
    };

    if (vk.vkAllocateMemory(vkState.logicalDevice, &allocInfo, null, imageMemory) != vk.VK_SUCCESS) return error.vkAllocateMemory;
    if (vk.vkBindImageMemory(vkState.logicalDevice, image.*, imageMemory.*, 0) != vk.VK_SUCCESS) return error.bindImageMemory;
}

fn createDescriptorSets(vkState: *Vk_State) !void {
    const layouts = [_]vk.VkDescriptorSetLayout{vkState.descriptorSetLayout} ** Vk_State.MAX_FRAMES_IN_FLIGHT;
    const allocInfo: vk.VkDescriptorSetAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = vkState.descriptorPool,
        .descriptorSetCount = Vk_State.MAX_FRAMES_IN_FLIGHT,
        .pSetLayouts = &layouts,
    };
    vkState.descriptorSets = try std.heap.page_allocator.alloc(vk.VkDescriptorSet, Vk_State.MAX_FRAMES_IN_FLIGHT);
    if (vk.vkAllocateDescriptorSets(vkState.logicalDevice, &allocInfo, @ptrCast(vkState.descriptorSets)) != vk.VK_SUCCESS) return error.allocateDescriptorSets;

    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        const bufferInfo: vk.VkDescriptorBufferInfo = .{
            .buffer = vkState.uniformBuffers[i],
            .offset = 0,
            .range = @sizeOf(UniformBufferObject),
        };
        const imageInfo: vk.VkDescriptorImageInfo = .{
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = vkState.textureImageView,
            .sampler = vkState.textureSampler,
        };
        const descriptorWrites = [_]vk.VkWriteDescriptorSet{
            .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = vkState.descriptorSets[i],
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 1,
                .pBufferInfo = &bufferInfo,
                .pImageInfo = null,
                .pTexelBufferView = null,
            },
            .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = vkState.descriptorSets[i],
                .dstBinding = 1,
                .dstArrayElement = 0,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .pImageInfo = &imageInfo,
            },
        };
        vk.vkUpdateDescriptorSets(vkState.logicalDevice, descriptorWrites.len, &descriptorWrites, 0, null);
    }
}

fn createDescriptorPool(vkState: *Vk_State) !void {
    const poolSizes = [_]vk.VkDescriptorPoolSize{
        .{
            .type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = Vk_State.MAX_FRAMES_IN_FLIGHT,
        },
        .{
            .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = Vk_State.MAX_FRAMES_IN_FLIGHT,
        },
    };

    const poolInfo: vk.VkDescriptorPoolCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = poolSizes.len,
        .pPoolSizes = &poolSizes,
        .maxSets = Vk_State.MAX_FRAMES_IN_FLIGHT,
    };
    if (vk.vkCreateDescriptorPool(vkState.logicalDevice, &poolInfo, null, &vkState.descriptorPool) != vk.VK_SUCCESS) return error.descriptionPool;
}

fn createUniformBuffers(vkState: *Vk_State) !void {
    const bufferSize: vk.VkDeviceSize = @sizeOf(UniformBufferObject);

    vkState.uniformBuffers = try std.heap.page_allocator.alloc(vk.VkBuffer, Vk_State.MAX_FRAMES_IN_FLIGHT);
    vkState.uniformBuffersMemory = try std.heap.page_allocator.alloc(vk.VkDeviceMemory, Vk_State.MAX_FRAMES_IN_FLIGHT);
    vkState.uniformBuffersMapped = try std.heap.page_allocator.alloc(?*anyopaque, Vk_State.MAX_FRAMES_IN_FLIGHT);

    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        try createBuffer(
            bufferSize,
            vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &vkState.uniformBuffers[i],
            &vkState.uniformBuffersMemory[i],
            vkState,
        );
        if (vk.vkMapMemory(vkState.logicalDevice, vkState.uniformBuffersMemory[i], 0, bufferSize, 0, &vkState.uniformBuffersMapped[i]) != vk.VK_SUCCESS) return error.uniformMapMemory;
    }
}

fn createDescriptorSetLayout(vkState: *Vk_State) !void {
    const uboLayoutBinding: vk.VkDescriptorSetLayoutBinding = .{
        .binding = 0,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
    };
    const samplerLayoutBinding: vk.VkDescriptorSetLayoutBinding = .{
        .binding = 1,
        .descriptorCount = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImmutableSamplers = null,
        .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const bindings = [_]vk.VkDescriptorSetLayoutBinding{ uboLayoutBinding, samplerLayoutBinding };

    const layoutInfo: vk.VkDescriptorSetLayoutCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = bindings.len,
        .pBindings = &bindings,
    };

    if (vk.vkCreateDescriptorSetLayout(vkState.logicalDevice, &layoutInfo, null, &vkState.descriptorSetLayout) != vk.VK_SUCCESS) return error.createDescriptorSetLayout;
}

fn findMemoryType(typeFilter: u32, properties: vk.VkMemoryPropertyFlags, vkState: *Vk_State) !u32 {
    var memProperties: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.vkGetPhysicalDeviceMemoryProperties(vkState.physical_device, &memProperties);

    for (0..memProperties.memoryTypeCount) |i| {
        if ((typeFilter & (@as(u32, 1) << @as(u5, @intCast(i))) != 0) and (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return @as(u32, @intCast(i));
        }
    }
    return error.findMemoryType;
}

fn createBuffer(size: vk.VkDeviceSize, usage: vk.VkBufferUsageFlags, properties: vk.VkMemoryPropertyFlags, buffer: *vk.VkBuffer, bufferMemory: *vk.VkDeviceMemory, vkState: *Vk_State) !void {
    const bufferInfo: vk.VkBufferCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
    };

    if (vk.vkCreateBuffer(vkState.logicalDevice, &bufferInfo, null, &buffer.*) != vk.VK_SUCCESS) return error.CreateBuffer;
    var memRequirements: vk.VkMemoryRequirements = undefined;
    vk.vkGetBufferMemoryRequirements(vkState.logicalDevice, buffer.*, &memRequirements);

    const allocInfo: vk.VkMemoryAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = memRequirements.size,
        .memoryTypeIndex = try findMemoryType(memRequirements.memoryTypeBits, properties, vkState),
    };
    if (vk.vkAllocateMemory(vkState.logicalDevice, &allocInfo, null, &bufferMemory.*) != vk.VK_SUCCESS) return error.allocateMemory;
    if (vk.vkBindBufferMemory(vkState.logicalDevice, buffer.*, bufferMemory.*, 0) != vk.VK_SUCCESS) return error.bindMemory;
}

fn createVertexBuffer(vkState: *Vk_State) !void {
    try createBuffer(
        @sizeOf(Vertex) * vertices.len,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.vertexBuffer,
        &vkState.vertexBufferMemory,
        vkState,
    );
}

fn destroy(vkState: *Vk_State) !void {
    for (vkState.swapchain_imageviews) |imgvw| {
        vk.vkDestroyImageView(vkState.logicalDevice, imgvw, null);
    }
    for (vkState.framebuffers) |fb| {
        vk.vkDestroyFramebuffer(vkState.logicalDevice, fb, null);
    }
    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        vk.vkDestroySemaphore(vkState.logicalDevice, vkState.imageAvailableSemaphore[i], null);
        vk.vkDestroySemaphore(vkState.logicalDevice, vkState.renderFinishedSemaphore[i], null);
        vk.vkDestroyFence(vkState.logicalDevice, vkState.inFlightFence[i], null);
    }

    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        vk.vkDestroyBuffer(vkState.logicalDevice, vkState.uniformBuffers[i], null);
        vk.vkFreeMemory(vkState.logicalDevice, vkState.uniformBuffersMemory[i], null);
    }
    vk.vkDestroySampler(vkState.logicalDevice, vkState.textureSampler, null);
    vk.vkDestroyImageView(vkState.logicalDevice, vkState.textureImageView, null);
    vk.vkDestroyImage(vkState.logicalDevice, vkState.textureImage, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.textureImageMemory, null);

    vk.vkDestroyDescriptorPool(vkState.logicalDevice, vkState.descriptorPool, null);
    vk.vkDestroyDescriptorSetLayout(vkState.logicalDevice, vkState.descriptorSetLayout, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.vertexBufferMemory, null);
    vk.vkDestroyCommandPool(vkState.logicalDevice, vkState.command_pool, null);
    vk.vkDestroyPipeline(vkState.logicalDevice, vkState.graphics_pipeline, null);
    vk.vkDestroyPipelineLayout(vkState.logicalDevice, vkState.pipeline_layout, null);
    vk.vkDestroyRenderPass(vkState.logicalDevice, vkState.render_pass, null);
    vk.vkDestroySwapchainKHR(vkState.logicalDevice, vkState.swapchain, null);
    vk.vkDestroyDevice(vkState.logicalDevice, null);
    vk.vkDestroySurfaceKHR(vkState.instance, vkState.surface, null);
    vk.vkDestroyInstance(vkState.instance, null);
}

fn createSurface(vkState: *Vk_State) !void {
    const createInfo = vk.VkWin32SurfaceCreateInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .hinstance = vkState.hInstance,
        .hwnd = vkState.window,
    };
    if (vk.vkCreateWin32SurfaceKHR(vkState.instance, &createInfo, null, &vkState.surface) != vk.VK_SUCCESS) return error.vkCreateWin32;
}

fn createInstance(vkState: *Vk_State) !void {
    var app_info = vk.VkApplicationInfo{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "ZigWindowsVulkan",
        .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = vk.VK_API_VERSION_1_0,
    };
    var instance_create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = &app_info,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = 0,
        .ppEnabledExtensionNames = null,
    };
    const requiredExtensions = [_][*:0]const u8{
        vk.VK_KHR_SURFACE_EXTENSION_NAME,
        vk.VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
    };
    const extension_count: u32 = requiredExtensions.len;
    const extensions: [*][*c]const u8 = @constCast(@ptrCast(&requiredExtensions));
    instance_create_info.enabledExtensionCount = extension_count;
    instance_create_info.ppEnabledExtensionNames = extensions;

    var extension_list = std.ArrayList([*c]const u8).init(std.heap.page_allocator);
    for (requiredExtensions[0..extension_count]) |ext| {
        try extension_list.append(ext);
    }

    try extension_list.append(vk.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    instance_create_info.enabledExtensionCount = @intCast(extension_list.items.len);
    const extensions_ = try extension_list.toOwnedSlice();
    const pp_enabled_layer_names: [*][*c]const u8 = extensions_.ptr;
    instance_create_info.ppEnabledExtensionNames = pp_enabled_layer_names;

    if (vk.vkCreateInstance(&instance_create_info, null, &vkState.instance) != vk.VK_SUCCESS) return error.vkCreateInstance;
}

fn setupVertexDataForGPU(vkState: *Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.vertexBufferMemory, 0, @sizeOf(Vertex) * vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.vertexBufferMemory);
}

fn updateUniformBuffer(vkState: *Vk_State) !void {
    const change: f32 = @as(f32, @floatFromInt(@mod(std.time.milliTimestamp(), 10000))) / 10000.0;
    var ubo: UniformBufferObject = .{
        .transform = .{
            .{ 1.0, change, 0.0, 0.0 },
            .{ -change, 1.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 1, 0.0 },
            .{ 0.0, 0.0, 0.0, 1 },
        },
    };
    if (vkState.uniformBuffersMapped[vkState.currentFrame]) |data| {
        @memcpy(
            @as([*]u8, @ptrCast(data))[0..@sizeOf(UniformBufferObject)],
            @as([*]u8, @ptrCast(&ubo)),
        );
    }
    // const gpu_uniform: [*]UniformBufferObject = @ptrCast(@alignCast(vkState.uniformBuffersMapped[vkState.currentFrame]));
    // @memcpy(gpu_uniform, @as([*]u8, @ptrCast(&ubo)));
}

fn drawFrame(vkState: *Vk_State) !void {
    try updateUniformBuffer(vkState);

    _ = vk.vkWaitForFences(vkState.logicalDevice, 1, &vkState.inFlightFence[vkState.currentFrame], vk.VK_TRUE, std.math.maxInt(u64));
    _ = vk.vkResetFences(vkState.logicalDevice, 1, &vkState.inFlightFence[vkState.currentFrame]);

    var imageIndex: u32 = undefined;
    _ = vk.vkAcquireNextImageKHR(vkState.logicalDevice, vkState.swapchain, std.math.maxInt(u64), vkState.imageAvailableSemaphore[vkState.currentFrame], null, &imageIndex);

    _ = vk.vkResetCommandBuffer(vkState.command_buffer[vkState.currentFrame], 0);
    try recordCommandBuffer(vkState.command_buffer[vkState.currentFrame], imageIndex, vkState);

    var submitInfo = vk.VkSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &[_]vk.VkSemaphore{vkState.imageAvailableSemaphore[vkState.currentFrame]},
        .pWaitDstStageMask = &[_]vk.VkPipelineStageFlags{vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT},
        .commandBufferCount = 1,
        .pCommandBuffers = &vkState.command_buffer[vkState.currentFrame],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &[_]vk.VkSemaphore{vkState.renderFinishedSemaphore[vkState.currentFrame]},
    };
    try vkcheck(vk.vkQueueSubmit(vkState.queue, 1, &submitInfo, vkState.inFlightFence[vkState.currentFrame]), "Failed to Queue Submit.");

    var presentInfo = vk.VkPresentInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &[_]vk.VkSemaphore{vkState.renderFinishedSemaphore[vkState.currentFrame]},
        .swapchainCount = 1,
        .pSwapchains = &[_]vk.VkSwapchainKHR{vkState.swapchain},
        .pImageIndices = &imageIndex,
    };
    try vkcheck(vk.vkQueuePresentKHR(vkState.queue, &presentInfo), "Failed to Queue Present KHR.");
    vkState.currentFrame = (vkState.currentFrame + 1) % Vk_State.MAX_FRAMES_IN_FLIGHT;
}

fn createSyncObjects(vkState: *Vk_State) !void {
    var semaphoreInfo = vk.VkSemaphoreCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    var fenceInfo = vk.VkFenceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    vkState.imageAvailableSemaphore = try std.heap.page_allocator.alloc(vk.VkSemaphore, Vk_State.MAX_FRAMES_IN_FLIGHT);
    vkState.renderFinishedSemaphore = try std.heap.page_allocator.alloc(vk.VkSemaphore, Vk_State.MAX_FRAMES_IN_FLIGHT);
    vkState.inFlightFence = try std.heap.page_allocator.alloc(vk.VkFence, Vk_State.MAX_FRAMES_IN_FLIGHT);

    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        if (vk.vkCreateSemaphore(vkState.logicalDevice, &semaphoreInfo, null, &vkState.imageAvailableSemaphore[i]) != vk.VK_SUCCESS or
            vk.vkCreateSemaphore(vkState.logicalDevice, &semaphoreInfo, null, &vkState.renderFinishedSemaphore[i]) != vk.VK_SUCCESS or
            vk.vkCreateFence(vkState.logicalDevice, &fenceInfo, null, &vkState.inFlightFence[i]) != vk.VK_SUCCESS)
        {
            std.debug.print("Failed to Create Semaphore or Create Fence.\n", .{});
            return error.FailedToCreateSyncObjects;
        }
    }
}

fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, imageIndex: u32, vkState: *Vk_State) !void {
    var beginInfo = vk.VkCommandBufferBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    };
    try vkcheck(vk.vkBeginCommandBuffer(commandBuffer, &beginInfo), "Failed to Begin Command Buffer.");

    const renderPassInfo = vk.VkRenderPassBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = vkState.render_pass,
        .framebuffer = vkState.framebuffers[imageIndex],
        .renderArea = vk.VkRect2D{
            .offset = vk.VkOffset2D{ .x = 0, .y = 0 },
            .extent = vkState.swapchain_info.extent,
        },
        .clearValueCount = 1,
        .pClearValues = &[_]vk.VkClearValue{.{ .color = vk.VkClearColorValue{ .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 } } }},
    };
    vk.vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, vk.VK_SUBPASS_CONTENTS_INLINE);
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.graphics_pipeline);
    var viewport = vk.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(vkState.swapchain_info.extent.width),
        .height = @floatFromInt(vkState.swapchain_info.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vk.vkCmdSetViewport(commandBuffer, 0, 1, &viewport);
    var scissor = vk.VkRect2D{
        .offset = vk.VkOffset2D{ .x = 0, .y = 0 },
        .extent = vkState.swapchain_info.extent,
    };
    vk.vkCmdSetScissor(commandBuffer, 0, 1, &scissor);
    const vertexBuffers: [1]vk.VkBuffer = .{vkState.vertexBuffer};
    const offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdBindDescriptorSets(
        commandBuffer,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        vkState.pipeline_layout,
        0,
        1,
        &vkState.descriptorSets[vkState.currentFrame],
        0,
        null,
    );

    vk.vkCmdDraw(commandBuffer, @intCast(vertices.len), 1, 0, 0);
    vk.vkCmdEndRenderPass(commandBuffer);
    try vkcheck(vk.vkEndCommandBuffer(commandBuffer), "Failed to End Command Buffer.");
}

fn createCommandBuffers(vkState: *Vk_State) !void {
    vkState.command_buffer = try std.heap.page_allocator.alloc(vk.VkCommandBuffer, Vk_State.MAX_FRAMES_IN_FLIGHT);

    var allocInfo = vk.VkCommandBufferAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = vkState.command_pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(vkState.command_buffer.len),
    };
    try vkcheck(vk.vkAllocateCommandBuffers(vkState.logicalDevice, &allocInfo, &vkState.command_buffer[0]), "Failed to create Command Pool.");
    std.debug.print("Command Buffer : {any}\n", .{vkState.command_buffer});
}

fn createCommandPool(vkState: *Vk_State) !void {
    const queueFamilyIndices = try findQueueFamilies(vkState.physical_device, vkState);
    var poolInfo = vk.VkCommandPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queueFamilyIndices.graphicsFamily.?,
    };
    try vkcheck(vk.vkCreateCommandPool(vkState.logicalDevice, &poolInfo, null, &vkState.command_pool), "Failed to create Command Pool.");
    std.debug.print("Command Pool : {any}\n", .{vkState.command_pool});
}

fn createFramebuffers(vkState: *Vk_State) !void {
    vkState.framebuffers = try std.heap.page_allocator.alloc(vk.VkFramebuffer, vkState.swapchain_imageviews.len);

    for (vkState.swapchain_imageviews, 0..) |imageView, i| {
        var attachments = [_]vk.VkImageView{imageView};
        var framebufferInfo = vk.VkFramebufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = vkState.render_pass,
            .attachmentCount = 1,
            .pAttachments = &attachments,
            .width = vkState.swapchain_info.extent.width,
            .height = vkState.swapchain_info.extent.height,
            .layers = 1,
        };
        try vkcheck(vk.vkCreateFramebuffer(vkState.logicalDevice, &framebufferInfo, null, &vkState.framebuffers[i]), "Failed to create Framebuffer.");
        std.debug.print("Framebuffer Created : {any}\n", .{vkState.pipeline_layout});
    }
}

fn createRenderPass(vkState: *Vk_State) !void {
    var colorAttachment = vk.VkAttachmentDescription{
        .format = vkState.swapchain_info.format.format,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    var colorAttachmentRef = vk.VkAttachmentReference{
        .attachment = 0,
        .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    var subpass = vk.VkSubpassDescription{
        .pipelineBindPoint = vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorAttachmentRef,
    };

    var renderPassInfo = vk.VkRenderPassCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &colorAttachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 0,
        .pDependencies = null,
    };
    try vkcheck(vk.vkCreateRenderPass(vkState.logicalDevice, &renderPassInfo, null, &vkState.render_pass), "Failed to create Render Pass.");
    std.debug.print("Render Pass Created : {any}\n", .{vkState.render_pass});
}

fn createGraphicsPipeline(vkState: *Vk_State) !void {
    const vertShaderCode = try readFile("src/vert.spv");
    const fragShaderCode = try readFile("src/frag.spv");
    const vertShaderModule = try createShaderModule(vertShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, vertShaderModule, null);
    const fragShaderModule = try createShaderModule(fragShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, fragShaderModule, null);

    const vertShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertShaderModule,
        .pName = "main",
    };

    const fragShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragShaderModule,
        .pName = "main",
    };

    const shaderStages = [_]vk.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo };
    const bindingDescription = Vertex.getBindingDescription();
    const attributeDescriptions = Vertex.getAttributeDescriptions();
    var vertexInputInfo = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &bindingDescription,
        .vertexAttributeDescriptionCount = attributeDescriptions.len,
        .pVertexAttributeDescriptions = &attributeDescriptions,
    };

    var inputAssembly = vk.VkPipelineInputAssemblyStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = vk.VK_FALSE,
    };

    var viewportState = vk.VkPipelineViewportStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = null,
        .scissorCount = 1,
        .pScissors = null,
    };

    var rasterizer = vk.VkPipelineRasterizationStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = vk.VK_FALSE,
        .rasterizerDiscardEnable = vk.VK_FALSE,
        .polygonMode = vk.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = vk.VK_CULL_MODE_BACK_BIT,
        .frontFace = vk.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = vk.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
    };

    var multisampling = vk.VkPipelineMultisampleStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = vk.VK_FALSE,
        .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = vk.VK_FALSE,
        .alphaToOneEnable = vk.VK_FALSE,
    };

    var colorBlendAttachment = vk.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = vk.VK_FALSE,
    };

    var colorBlending = vk.VkPipelineColorBlendStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = vk.VK_FALSE,
        .logicOp = vk.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &colorBlendAttachment,
        .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    const dynamicStates = [_]vk.VkDynamicState{
        vk.VK_DYNAMIC_STATE_VIEWPORT,
        vk.VK_DYNAMIC_STATE_SCISSOR,
    };

    var dynamicState = vk.VkPipelineDynamicStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamicStates.len,
        .pDynamicStates = &dynamicStates,
    };

    var pipelineLayoutInfo = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &vkState.descriptorSetLayout,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };
    try vkcheck(vk.vkCreatePipelineLayout(vkState.logicalDevice, &pipelineLayoutInfo, null, &vkState.pipeline_layout), "Failed to create pipeline layout.");
    std.debug.print("Pipeline Layout Created : {any}\n", .{vkState.pipeline_layout});

    var pipelineInfo = vk.VkGraphicsPipelineCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = &shaderStages,
        .pVertexInputState = &vertexInputInfo,
        .pInputAssemblyState = &inputAssembly,
        .pViewportState = &viewportState,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pColorBlendState = &colorBlending,
        .pDynamicState = &dynamicState,
        .layout = vkState.pipeline_layout,
        .renderPass = vkState.render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .pNext = null,
    };
    try vkcheck(vk.vkCreateGraphicsPipelines(vkState.logicalDevice, null, 1, &pipelineInfo, null, &vkState.graphics_pipeline), "Failed to create graphics pipeline.");
    std.debug.print("Graphics Pipeline Created : {any}\n", .{vkState.pipeline_layout});
}

fn createShaderModule(code: []const u8, vkState: *Vk_State) !vk.VkShaderModule {
    var createInfo = vk.VkShaderModuleCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = @alignCast(@ptrCast(code.ptr)),
    };
    var shaderModule: vk.VkShaderModule = undefined; //std.mem.zeroes(vk.VkShaderModule)
    try vkcheck(vk.vkCreateShaderModule(vkState.logicalDevice, &createInfo, null, &shaderModule), "Failed to create Shader Module.");
    std.debug.print("Shader Module Created : {any}\n", .{shaderModule});
    return shaderModule;
}

fn createImageViews(vkState: *Vk_State) !void {
    vkState.swapchain_imageviews = try std.heap.page_allocator.alloc(vk.VkImageView, vkState.swapchain_info.images.len);
    for (vkState.swapchain_info.images, 0..) |image, i| {
        vkState.swapchain_imageviews[i] = try createImageView(image, vkState.swapchain_info.format.format, vkState);
        std.debug.print("Swapchain ImageView Created : {any}\n", .{vkState.swapchain_imageviews[i]});
    }
}

fn createSwapChain(vkState: *Vk_State) !void {
    vkState.swapchain_info.support = try querySwapChainSupport(vkState);
    vkState.swapchain_info.format = chooseSwapSurfaceFormat(vkState.swapchain_info.support.formats);
    vkState.swapchain_info.present = chooseSwapPresentMode(vkState.swapchain_info.support.presentModes);
    vkState.swapchain_info.extent = chooseSwapExtent(vkState.swapchain_info.support.capabilities, vkState);

    var imageCount = vkState.swapchain_info.support.capabilities.minImageCount + 1;
    if (vkState.swapchain_info.support.capabilities.maxImageCount > 0 and imageCount > vkState.swapchain_info.support.capabilities.maxImageCount) {
        imageCount = vkState.swapchain_info.support.capabilities.maxImageCount;
    }

    var createInfo = vk.VkSwapchainCreateInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = vkState.surface,
        .minImageCount = imageCount,
        .imageFormat = vkState.swapchain_info.format.format,
        .imageColorSpace = vkState.swapchain_info.format.colorSpace,
        .imageExtent = vkState.swapchain_info.extent,
        .imageArrayLayers = 1,
        .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = vkState.swapchain_info.support.capabilities.currentTransform,
        .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = vkState.swapchain_info.present,
        .clipped = vk.VK_TRUE,
        .oldSwapchain = null,
    };

    const indices = try findQueueFamilies(vkState.physical_device, vkState);
    const queueFamilyIndices = [_]u32{ indices.graphicsFamily.?, indices.presentFamily.? };
    if (indices.graphicsFamily != indices.presentFamily) {
        createInfo.imageSharingMode = vk.VK_SHARING_MODE_CONCURRENT;
        createInfo.queueFamilyIndexCount = 2;
        createInfo.pQueueFamilyIndices = &queueFamilyIndices;
    } else {
        createInfo.imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE;
    }

    try vkcheck(vk.vkCreateSwapchainKHR(vkState.logicalDevice, &createInfo, null, &vkState.swapchain), "Failed to create swapchain KHR");
    std.debug.print("Swapchain KHR Created : {any}\n", .{vkState.logicalDevice});

    _ = vk.vkGetSwapchainImagesKHR(vkState.logicalDevice, vkState.swapchain, &imageCount, null);
    vkState.swapchain_info.images = try std.heap.page_allocator.alloc(vk.VkImage, imageCount);
    _ = vk.vkGetSwapchainImagesKHR(vkState.logicalDevice, vkState.swapchain, &imageCount, vkState.swapchain_info.images.ptr);
}

fn querySwapChainSupport(vkState: *Vk_State) !SwapChainSupportDetails {
    var details = SwapChainSupportDetails{
        .capabilities = undefined,
        .formats = &.{},
        .presentModes = &.{},
    };

    var formatCount: u32 = 0;
    var presentModeCount: u32 = 0;
    _ = vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vkState.physical_device, vkState.surface, &details.capabilities);
    _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(vkState.physical_device, vkState.surface, &formatCount, null);
    if (formatCount > 0) {
        details.formats = try std.heap.page_allocator.alloc(vk.VkSurfaceFormatKHR, formatCount);
        _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(vkState.physical_device, vkState.surface, &formatCount, details.formats.ptr);
    }
    _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(vkState.physical_device, vkState.surface, &presentModeCount, null);
    if (presentModeCount > 0) {
        details.presentModes = try std.heap.page_allocator.alloc(vk.VkPresentModeKHR, presentModeCount);
        _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(vkState.physical_device, vkState.surface, &presentModeCount, details.presentModes.ptr);
    }
    return details;
}

fn chooseSwapSurfaceFormat(formats: []const vk.VkSurfaceFormatKHR) vk.VkSurfaceFormatKHR {
    for (formats) |format| {
        if (format.format == vk.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }
    return formats[0];
}

fn chooseSwapPresentMode(present_modes: []const vk.VkPresentModeKHR) vk.VkPresentModeKHR {
    for (present_modes) |mode| {
        if (mode == vk.VK_PRESENT_MODE_MAILBOX_KHR) {
            return mode;
        }
    }
    return vk.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseSwapExtent(capabilities: vk.VkSurfaceCapabilitiesKHR, vkState: *Vk_State) vk.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        var rect: vk.RECT = undefined;
        _ = vk.GetClientRect(vkState.window, &rect);
        var actual_extent = vk.VkExtent2D{
            .width = @intCast(rect.right - rect.left),
            .height = @intCast(rect.bottom - rect.top),
        };
        actual_extent.width = std.math.clamp(actual_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
        actual_extent.height = std.math.clamp(actual_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);
        return actual_extent;
    }
}

pub const validation_layers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
pub fn checkValidationLayerSupport() bool {
    var layer_count: u32 = 0;
    _ = vk.vkEnumerateInstanceLayerProperties(&layer_count, null);

    const available_layers = std.heap.page_allocator.alloc(vk.VkLayerProperties, layer_count) catch unreachable;
    defer std.heap.page_allocator.free(available_layers);
    _ = vk.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

    std.debug.print("Validation check, searching: \n", .{});
    for (validation_layers) |layer_name| {
        const layer_name_span = std.mem.span(layer_name);
        const layer_name_len = layer_name_span.len;
        std.debug.print("  {s}\nValidation properties list :\n", .{layer_name_span});
        var found: bool = false;
        for (available_layers) |layer_properties| {
            std.debug.print("  {s}\n", .{layer_properties.layerName});
            const prop_name_len = std.mem.indexOf(u8, layer_properties.layerName[0..], &[_]u8{0}) orelse 256;
            if (layer_name_len == prop_name_len) {
                std.debug.print("Found:\n  {s}\n", .{&layer_properties.layerName});
                if (std.mem.eql(u8, layer_name_span, layer_properties.layerName[0..prop_name_len])) {
                    found = true;
                    break;
                }
            }
        }
        if (!found) return false;
    }
    return true;
}

fn createLogicalDevice(physical_device: vk.VkPhysicalDevice, vkState: *Vk_State) !void {
    var queue_create_info = vk.VkDeviceQueueCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = vkState.graphics_queue_family_idx,
        .queueCount = 1,
        .pQueuePriorities = &[_]f32{1.0},
    };
    var device_features = vk.VkPhysicalDeviceFeatures{
        .samplerAnisotropy = vk.VK_TRUE,
    };
    var device_create_info = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_info,
        .queueCreateInfoCount = 1,
        .pEnabledFeatures = &device_features,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = &[_][*c]const u8{vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME},
    };
    device_create_info.enabledLayerCount = 1;
    device_create_info.ppEnabledLayerNames = &validation_layers;
    try vkcheck(vk.vkCreateDevice(physical_device, &device_create_info, null, &vkState.logicalDevice), "Failed to create logical device");
    std.debug.print("Logical Device Created : {any}\n", .{vkState.logicalDevice});
    vk.vkGetDeviceQueue(vkState.logicalDevice, vkState.graphics_queue_family_idx, 0, &vkState.queue);
    std.debug.print("Queue Obtained : {any}\n", .{vkState.queue});
}

fn wndProc(hwnd: zigWin32.foundation.HWND, msg: u32, wParam: std.os.windows.WPARAM, lParam: std.os.windows.LPARAM) callconv(std.builtin.CallingConvention.winapi) std.os.windows.LRESULT {
    //std.debug.print("wndProc msg:{}\n", .{msg});
    return ui.DefWindowProcW(hwnd, msg, wParam, lParam);
}

fn pickPhysicalDevice(instance: vk.VkInstance, vkState: *Vk_State) !vk.VkPhysicalDevice {
    var device_count: u32 = 0;
    try vkcheck(vk.vkEnumeratePhysicalDevices(instance, &device_count, null), "Failed to enumerate physical devices");
    if (device_count == 0) {
        return error.NoGPUsWithVulkanSupport;
    }

    const devices = try std.heap.page_allocator.alloc(vk.VkPhysicalDevice, device_count);
    defer std.heap.page_allocator.free(devices);
    try vkcheck(vk.vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr), "Failed to enumerate physical devices");

    for (devices) |device| {
        if (try isDeviceSuitable(device, vkState)) {
            return device;
        }
    }
    return error.NoSuitableGPU;
}
fn isDeviceSuitable(device: vk.VkPhysicalDevice, vkState: *Vk_State) !bool {
    const indices: QueueFamilyIndices = try findQueueFamilies(device, vkState);
    vkState.graphics_queue_family_idx = indices.graphicsFamily.?;

    var supportedFeatures: vk.VkPhysicalDeviceFeatures = undefined;
    vk.vkGetPhysicalDeviceFeatures(device, &supportedFeatures);

    return indices.isComplete() and supportedFeatures.samplerAnisotropy != 0;
}

fn findQueueFamilies(device: vk.VkPhysicalDevice, vkState: *Vk_State) !QueueFamilyIndices {
    var indices = QueueFamilyIndices{
        .graphicsFamily = null,
        .presentFamily = null,
    };
    var queueFamilyCount: u32 = 0;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);

    const queueFamilies = try std.heap.page_allocator.alloc(vk.VkQueueFamilyProperties, queueFamilyCount);
    defer std.heap.page_allocator.free(queueFamilies);
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);

    for (queueFamilies, 0..) |queueFamily, i| {
        if (queueFamily.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
            indices.graphicsFamily = @intCast(i);
        }
        var presentSupport: vk.VkBool32 = vk.VK_FALSE;
        _ = vk.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), vkState.surface, &presentSupport);
        if (presentSupport == vk.VK_TRUE) {
            indices.presentFamily = @intCast(i);
        }
        if (indices.isComplete()) {
            break;
        }
    }
    return indices;
}

const QueueFamilyIndices = struct {
    graphicsFamily: ?u32,
    presentFamily: ?u32,

    fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphicsFamily != null;
    }
};

fn vkcheck(result: vk.VkResult, comptime err_msg: []const u8) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error : {s}\n", .{err_msg});
        return error.VulkanError;
    }
}

fn readFile(filename: []const u8) ![]u8 {
    const code = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, filename, std.math.maxInt(usize));
    return code;
}
