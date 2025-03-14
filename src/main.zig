const std = @import("std");
const zigWin32 = @import("zigwin32");
const zigWin32Everything = zigWin32.everything;
const ui = zigWin32.ui.windows_and_messaging;
const vulcan = @import("vulkan");
const vk = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", "1");
    @cInclude("vulkan.h");
});

// tasks:
// follow vulcan tutorial:
//    - continue https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/03_Drawing/00_Framebuffers.html
//
// next goal: draw 10_000 images to screen
//           - want to know some limit with vulcan so i can compare to my sdl version

const Vk_State = struct {
    window: vk.HWND = undefined,
    hInstance: vk.HINSTANCE = undefined,
    window_width: c_int = 1280,
    window_height: c_int = 720,

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
        imageformat: vk.VkFormat = undefined,
    } = undefined,
    swapchain_imageviews: []vk.VkImageView = undefined,
    render_pass: vk.VkRenderPass = undefined,
    pipeline_layout: vk.VkPipelineLayout = undefined,
    graphics_pipeline: vk.VkPipeline = undefined,
    framebuffers: []vk.VkFramebuffer = undefined,
    command_pool: vk.VkCommandPool = undefined,
    command_buffer: vk.VkCommandBuffer = undefined,

    imageAvailableSemaphore: vk.VkSemaphore = undefined,
    renderFinishedSemaphore: vk.VkSemaphore = undefined,
    inFlightFence: vk.VkFence = undefined,
};

const SwapChainSupportDetails = struct {
    capabilities: vk.VkSurfaceCapabilitiesKHR,
    formats: []vk.VkSurfaceFormatKHR,
    presentModes: []vk.VkPresentModeKHR,
};
var vk_state_global: Vk_State = .{};

pub fn main() !void {
    std.debug.print("start\n", .{});
    std.debug.print("validation layer support: {}\n", .{checkValidationLayerSupport()});
    try initWindow(&vk_state_global);
    try initVulkan();
    try mainLoop();
    try destroy();
    std.debug.print("done\n", .{});
}

fn mainLoop() !void {
    // keep running for 2sec
    var counter: u32 = 0;
    const startTime = std.time.microTimestamp();
    const maxCounter = 2000;
    while (counter < maxCounter) {
        counter += 1;
        try drawFrame();
        //std.time.sleep(100_000_000);
    }
    const timePassed = std.time.microTimestamp() - startTime;
    const fps = @divTrunc(maxCounter * 1_000_000, timePassed);
    std.debug.print("fps: {}, timePassed: {}", .{ fps, timePassed });
    _ = vk.vkDeviceWaitIdle(vk_state_global.logicalDevice);
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

fn initVulkan() !void {
    try createInstance();
    try createSurface();
    vk_state_global.physical_device = try pickPhysicalDevice(vk_state_global.instance);
    try createLogicalDevice(vk_state_global.physical_device);
    try createSwapChain();
    try createImageViews();
    try createRenderPass();
    try createGraphicsPipeline();
    try createFramebuffers();
    try createCommandPool();
    try createCommandBuffer();
    try createSyncObjects();
}

fn destroy() !void {
    for (vk_state_global.swapchain_imageviews) |imgvw| {
        vk.vkDestroyImageView(vk_state_global.logicalDevice, imgvw, null);
    }
    for (vk_state_global.framebuffers) |fb| {
        vk.vkDestroyFramebuffer(vk_state_global.logicalDevice, fb, null);
    }
    vk.vkDestroySemaphore(vk_state_global.logicalDevice, vk_state_global.imageAvailableSemaphore, null);
    vk.vkDestroySemaphore(vk_state_global.logicalDevice, vk_state_global.renderFinishedSemaphore, null);
    vk.vkDestroyFence(vk_state_global.logicalDevice, vk_state_global.inFlightFence, null);
    vk.vkDestroyCommandPool(vk_state_global.logicalDevice, vk_state_global.command_pool, null);
    vk.vkDestroyPipeline(vk_state_global.logicalDevice, vk_state_global.graphics_pipeline, null);
    vk.vkDestroyPipelineLayout(vk_state_global.logicalDevice, vk_state_global.pipeline_layout, null);
    vk.vkDestroyRenderPass(vk_state_global.logicalDevice, vk_state_global.render_pass, null);
    vk.vkDestroySwapchainKHR(vk_state_global.logicalDevice, vk_state_global.swapchain, null);
    vk.vkDestroyDevice(vk_state_global.logicalDevice, null);
    vk.vkDestroySurfaceKHR(vk_state_global.instance, vk_state_global.surface, null);
    vk.vkDestroyInstance(vk_state_global.instance, null);
}

fn createSurface() !void {
    const createInfo = vk.VkWin32SurfaceCreateInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .hinstance = vk_state_global.hInstance,
        .hwnd = vk_state_global.window,
    };
    if (vk.vkCreateWin32SurfaceKHR(vk_state_global.instance, &createInfo, null, &vk_state_global.surface) != vk.VK_SUCCESS) return error.vkCreateWin32;
}

fn createInstance() !void {
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

    if (vk.vkCreateInstance(&instance_create_info, null, &vk_state_global.instance) != vk.VK_SUCCESS) return error.vkCreateInstance;
}

fn drawFrame() !void {
    _ = vk.vkWaitForFences(vk_state_global.logicalDevice, 1, &vk_state_global.inFlightFence, vk.VK_TRUE, std.math.maxInt(u64));
    _ = vk.vkResetFences(vk_state_global.logicalDevice, 1, &vk_state_global.inFlightFence);

    var imageIndex: u32 = undefined;
    _ = vk.vkAcquireNextImageKHR(vk_state_global.logicalDevice, vk_state_global.swapchain, std.math.maxInt(u64), vk_state_global.imageAvailableSemaphore, null, &imageIndex);

    _ = vk.vkResetCommandBuffer(vk_state_global.command_buffer, 0);
    try recordCommandBuffer(vk_state_global.command_buffer, imageIndex);

    var submitInfo = vk.VkSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &[_]vk.VkSemaphore{vk_state_global.imageAvailableSemaphore},
        .pWaitDstStageMask = &[_]vk.VkPipelineStageFlags{vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT},
        .commandBufferCount = 1,
        .pCommandBuffers = &vk_state_global.command_buffer,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &[_]vk.VkSemaphore{vk_state_global.renderFinishedSemaphore},
    };
    try vkcheck(vk.vkQueueSubmit(vk_state_global.queue, 1, &submitInfo, vk_state_global.inFlightFence), "Failed to Queue Submit.");

    var presentInfo = vk.VkPresentInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &[_]vk.VkSemaphore{vk_state_global.renderFinishedSemaphore},
        .swapchainCount = 1,
        .pSwapchains = &[_]vk.VkSwapchainKHR{vk_state_global.swapchain},
        .pImageIndices = &imageIndex,
    };
    try vkcheck(vk.vkQueuePresentKHR(vk_state_global.queue, &presentInfo), "Failed to Queue Present KHR.");
}

fn createSyncObjects() !void {
    var semaphoreInfo = vk.VkSemaphoreCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    var fenceInfo = vk.VkFenceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    if (vk.vkCreateSemaphore(vk_state_global.logicalDevice, &semaphoreInfo, null, &vk_state_global.imageAvailableSemaphore) != vk.VK_SUCCESS or
        vk.vkCreateSemaphore(vk_state_global.logicalDevice, &semaphoreInfo, null, &vk_state_global.renderFinishedSemaphore) != vk.VK_SUCCESS or
        vk.vkCreateFence(vk_state_global.logicalDevice, &fenceInfo, null, &vk_state_global.inFlightFence) != vk.VK_SUCCESS)
    {
        std.debug.print("Failed to Create Semaphore or Create Fence.\n", .{});
        return error.FailedToCreateSyncObjects;
    }
}

fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, imageIndex: u32) !void {
    var beginInfo = vk.VkCommandBufferBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    };
    try vkcheck(vk.vkBeginCommandBuffer(vk_state_global.command_buffer, &beginInfo), "Failed to Begin Command Buffer.");

    const renderPassInfo = vk.VkRenderPassBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = vk_state_global.render_pass,
        .framebuffer = vk_state_global.framebuffers[imageIndex],
        .renderArea = vk.VkRect2D{
            .offset = vk.VkOffset2D{ .x = 0, .y = 0 },
            .extent = vk_state_global.swapchain_info.extent,
        },
        .clearValueCount = 1,
        .pClearValues = &[_]vk.VkClearValue{.{ .color = vk.VkClearColorValue{ .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 } } }},
    };
    vk.vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, vk.VK_SUBPASS_CONTENTS_INLINE);
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vk_state_global.graphics_pipeline);
    var viewport = vk.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(vk_state_global.swapchain_info.extent.width),
        .height = @floatFromInt(vk_state_global.swapchain_info.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vk.vkCmdSetViewport(commandBuffer, 0, 1, &viewport);
    var scissor = vk.VkRect2D{
        .offset = vk.VkOffset2D{ .x = 0, .y = 0 },
        .extent = vk_state_global.swapchain_info.extent,
    };
    vk.vkCmdSetScissor(commandBuffer, 0, 1, &scissor);
    vk.vkCmdDraw(commandBuffer, 3, 1, 0, 0);
    vk.vkCmdEndRenderPass(commandBuffer);
    try vkcheck(vk.vkEndCommandBuffer(vk_state_global.command_buffer), "Failed to End Command Buffer.");
}

fn createCommandBuffer() !void {
    var allocInfo = vk.VkCommandBufferAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = vk_state_global.command_pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    try vkcheck(vk.vkAllocateCommandBuffers(vk_state_global.logicalDevice, &allocInfo, &vk_state_global.command_buffer), "Failed to create Command Pool.");
    std.debug.print("Command Buffer : {any}\n", .{vk_state_global.command_buffer});
}

fn createCommandPool() !void {
    const queueFamilyIndices = try findQueueFamilies(vk_state_global.physical_device);
    var poolInfo = vk.VkCommandPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queueFamilyIndices.graphicsFamily.?,
    };
    try vkcheck(vk.vkCreateCommandPool(vk_state_global.logicalDevice, &poolInfo, null, &vk_state_global.command_pool), "Failed to create Command Pool.");
    std.debug.print("Command Pool : {any}\n", .{vk_state_global.command_pool});
}

fn createFramebuffers() !void {
    vk_state_global.framebuffers = try std.heap.page_allocator.alloc(vk.VkFramebuffer, vk_state_global.swapchain_imageviews.len);

    for (vk_state_global.swapchain_imageviews, 0..) |imageView, i| {
        var attachments = [_]vk.VkImageView{imageView};
        var framebufferInfo = vk.VkFramebufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = vk_state_global.render_pass,
            .attachmentCount = 1,
            .pAttachments = &attachments,
            .width = vk_state_global.swapchain_info.extent.width,
            .height = vk_state_global.swapchain_info.extent.height,
            .layers = 1,
        };
        try vkcheck(vk.vkCreateFramebuffer(vk_state_global.logicalDevice, &framebufferInfo, null, &vk_state_global.framebuffers[i]), "Failed to create Framebuffer.");
        std.debug.print("Framebuffer Created : {any}\n", .{vk_state_global.pipeline_layout});
    }
}

fn createRenderPass() !void {
    var colorAttachment = vk.VkAttachmentDescription{
        .format = vk_state_global.swapchain_info.format.format,
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
    try vkcheck(vk.vkCreateRenderPass(vk_state_global.logicalDevice, &renderPassInfo, null, &vk_state_global.render_pass), "Failed to create Render Pass.");
    std.debug.print("Render Pass Created : {any}\n", .{vk_state_global.render_pass});
}

fn createGraphicsPipeline() !void {
    const vertShaderCode = try readFile("src/vert.spv");
    const fragShaderCode = try readFile("src/frag.spv");
    const vertShaderModule = try createShaderModule(vertShaderCode);
    defer vk.vkDestroyShaderModule(vk_state_global.logicalDevice, vertShaderModule, null);
    const fragShaderModule = try createShaderModule(fragShaderCode);
    defer vk.vkDestroyShaderModule(vk_state_global.logicalDevice, fragShaderModule, null);

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

    var vertexInputInfo = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
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
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };
    try vkcheck(vk.vkCreatePipelineLayout(vk_state_global.logicalDevice, &pipelineLayoutInfo, null, &vk_state_global.pipeline_layout), "Failed to create pipeline layout.");
    std.debug.print("Pipeline Layout Created : {any}\n", .{vk_state_global.pipeline_layout});

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
        .layout = vk_state_global.pipeline_layout,
        .renderPass = vk_state_global.render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .pNext = null,
    };
    try vkcheck(vk.vkCreateGraphicsPipelines(vk_state_global.logicalDevice, null, 1, &pipelineInfo, null, &vk_state_global.graphics_pipeline), "Failed to create graphics pipeline.");
    std.debug.print("Graphics Pipeline Created : {any}\n", .{vk_state_global.pipeline_layout});
}

fn createShaderModule(code: []const u8) !vk.VkShaderModule {
    var createInfo = vk.VkShaderModuleCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = @alignCast(@ptrCast(code.ptr)),
    };
    var shaderModule: vk.VkShaderModule = undefined; //std.mem.zeroes(vk.VkShaderModule)
    try vkcheck(vk.vkCreateShaderModule(vk_state_global.logicalDevice, &createInfo, null, &shaderModule), "Failed to create Shader Module.");
    std.debug.print("Shader Module Created : {any}\n", .{shaderModule});
    return shaderModule;
}

fn createImageViews() !void {
    vk_state_global.swapchain_imageviews = try std.heap.page_allocator.alloc(vk.VkImageView, vk_state_global.swapchain_info.images.len);
    for (vk_state_global.swapchain_info.images, 0..) |image, i| {
        var createInfo = vk.VkImageViewCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = vk_state_global.swapchain_info.format.format,
            .components = vk.VkComponentMapping{
                .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = vk.VkImageSubresourceRange{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        try vkcheck(vk.vkCreateImageView(vk_state_global.logicalDevice, &createInfo, null, &vk_state_global.swapchain_imageviews[i]), "Failed to create swapchain image views.");
        std.debug.print("Swapchain ImageView Created : {any}\n", .{vk_state_global.swapchain_imageviews[i]});
    }
}

fn createSwapChain() !void {
    vk_state_global.swapchain_info.support = try querySwapChainSupport();
    vk_state_global.swapchain_info.format = chooseSwapSurfaceFormat(vk_state_global.swapchain_info.support.formats);
    vk_state_global.swapchain_info.present = chooseSwapPresentMode(vk_state_global.swapchain_info.support.presentModes);
    vk_state_global.swapchain_info.extent = chooseSwapExtent(vk_state_global.swapchain_info.support.capabilities);

    var imageCount = vk_state_global.swapchain_info.support.capabilities.minImageCount + 1;
    if (vk_state_global.swapchain_info.support.capabilities.maxImageCount > 0 and imageCount > vk_state_global.swapchain_info.support.capabilities.maxImageCount) {
        imageCount = vk_state_global.swapchain_info.support.capabilities.maxImageCount;
    }

    var createInfo = vk.VkSwapchainCreateInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = vk_state_global.surface,
        .minImageCount = imageCount,
        .imageFormat = vk_state_global.swapchain_info.format.format,
        .imageColorSpace = vk_state_global.swapchain_info.format.colorSpace,
        .imageExtent = vk_state_global.swapchain_info.extent,
        .imageArrayLayers = 1,
        .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = vk_state_global.swapchain_info.support.capabilities.currentTransform,
        .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = vk_state_global.swapchain_info.present,
        .clipped = vk.VK_TRUE,
        .oldSwapchain = null,
    };

    const indices = try findQueueFamilies(vk_state_global.physical_device);
    const queueFamilyIndices = [_]u32{ indices.graphicsFamily.?, indices.presentFamily.? };
    if (indices.graphicsFamily != indices.presentFamily) {
        createInfo.imageSharingMode = vk.VK_SHARING_MODE_CONCURRENT;
        createInfo.queueFamilyIndexCount = 2;
        createInfo.pQueueFamilyIndices = &queueFamilyIndices;
    } else {
        createInfo.imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE;
    }

    try vkcheck(vk.vkCreateSwapchainKHR(vk_state_global.logicalDevice, &createInfo, null, &vk_state_global.swapchain), "Failed to create swapchain KHR");
    std.debug.print("Swapchain KHR Created : {any}\n", .{vk_state_global.logicalDevice});

    _ = vk.vkGetSwapchainImagesKHR(vk_state_global.logicalDevice, vk_state_global.swapchain, &imageCount, null);
    vk_state_global.swapchain_info.images = try std.heap.page_allocator.alloc(vk.VkImage, imageCount);
    _ = vk.vkGetSwapchainImagesKHR(vk_state_global.logicalDevice, vk_state_global.swapchain, &imageCount, vk_state_global.swapchain_info.images.ptr);
}

fn querySwapChainSupport() !SwapChainSupportDetails {
    var details = SwapChainSupportDetails{
        .capabilities = undefined,
        .formats = &.{},
        .presentModes = &.{},
    };

    var formatCount: u32 = 0;
    var presentModeCount: u32 = 0;
    _ = vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk_state_global.physical_device, vk_state_global.surface, &details.capabilities);
    _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(vk_state_global.physical_device, vk_state_global.surface, &formatCount, null);
    if (formatCount > 0) {
        details.formats = try std.heap.page_allocator.alloc(vk.VkSurfaceFormatKHR, formatCount);
        _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(vk_state_global.physical_device, vk_state_global.surface, &formatCount, details.formats.ptr);
    }
    _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(vk_state_global.physical_device, vk_state_global.surface, &presentModeCount, null);
    if (presentModeCount > 0) {
        details.presentModes = try std.heap.page_allocator.alloc(vk.VkPresentModeKHR, presentModeCount);
        _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(vk_state_global.physical_device, vk_state_global.surface, &presentModeCount, details.presentModes.ptr);
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

fn chooseSwapExtent(capabilities: vk.VkSurfaceCapabilitiesKHR) vk.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        var rect: vk.RECT = undefined;
        _ = vk.GetClientRect(vk_state_global.window, &rect);
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

fn createLogicalDevice(physical_device: vk.VkPhysicalDevice) !void {
    var queue_create_info = vk.VkDeviceQueueCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = vk_state_global.graphics_queue_family_idx,
        .queueCount = 1,
        .pQueuePriorities = &[_]f32{1.0},
    };
    var device_features = vk.VkPhysicalDeviceFeatures{};
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
    try vkcheck(vk.vkCreateDevice(physical_device, &device_create_info, null, &vk_state_global.logicalDevice), "Failed to create logical device");
    std.debug.print("Logical Device Created : {any}\n", .{vk_state_global.logicalDevice});
    vk.vkGetDeviceQueue(vk_state_global.logicalDevice, vk_state_global.graphics_queue_family_idx, 0, &vk_state_global.queue);
    std.debug.print("Queue Obtained : {any}\n", .{vk_state_global.queue});
}

fn wndProc(hwnd: zigWin32.foundation.HWND, msg: u32, wParam: std.os.windows.WPARAM, lParam: std.os.windows.LPARAM) callconv(std.builtin.CallingConvention.winapi) std.os.windows.LRESULT {
    //std.debug.print("wndProc msg:{}\n", .{msg});
    return ui.DefWindowProcW(hwnd, msg, wParam, lParam);
}

fn pickPhysicalDevice(instance: vk.VkInstance) !vk.VkPhysicalDevice {
    var device_count: u32 = 0;
    try vkcheck(vk.vkEnumeratePhysicalDevices(instance, &device_count, null), "Failed to enumerate physical devices");
    if (device_count == 0) {
        return error.NoGPUsWithVulkanSupport;
    }

    const devices = try std.heap.page_allocator.alloc(vk.VkPhysicalDevice, device_count);
    defer std.heap.page_allocator.free(devices);
    try vkcheck(vk.vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr), "Failed to enumerate physical devices");

    for (devices) |device| {
        if (try isDeviceSuitable(device)) {
            return device;
        }
    }
    return error.NoSuitableGPU;
}
fn isDeviceSuitable(device: vk.VkPhysicalDevice) !bool {
    const indices: QueueFamilyIndices = try findQueueFamilies(device);
    vk_state_global.graphics_queue_family_idx = indices.graphicsFamily.?;
    return indices.isComplete();
}

fn findQueueFamilies(device: vk.VkPhysicalDevice) !QueueFamilyIndices {
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
        _ = vk.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), vk_state_global.surface, &presentSupport);
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
