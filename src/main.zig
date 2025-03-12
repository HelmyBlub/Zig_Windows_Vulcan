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
//    - continue https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/01_Presentation/02_Image_views.html
//       - winAPI and vulcan.h only https://github.com/DarknessFX/zig_workbench/blob/fd6bae8f9236782f92759e64eecbbcc46fad83d6/BaseVulkan/main_vulkanw32.zig#L142
//       - zig version which follows tutorial, but old and uses glfw which is no longer maintained for zig? https://github.com/Vulfox/vulkan-tutorial-zig/tree/main
// draw anything in window
//

pub var vk_state = struct {
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
}{};

const SwapChainSupportDetails = struct {
    capabilities: vk.VkSurfaceCapabilitiesKHR,
    formats: []vk.VkSurfaceFormatKHR,
    presentModes: []vk.VkPresentModeKHR,
};

pub fn main() !void {
    std.debug.print("start\n", .{});

    try initWindow();
    std.debug.print("done\n", .{});
}

fn initWindow() !void {
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
        800,
        600,
        null,
        null,
        hInstance,
        null,
    ) orelse {
        std.debug.print("[!] CreateWindowExW Failed With Error : {}\n", .{zigWin32Everything.GetLastError()});
        return error.Unexpected;
    };

    _ = ui.ShowWindow(hwnd, ui.SW_SHOW);

    const vk_hInstance = vk.GetModuleHandleA(null);
    const vk_window = vk.FindWindowA("className", "title");
    var vk_instance: vk.VkInstance = undefined;
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
    if (vk.vkCreateInstance(&instance_create_info, null, &vk_instance) != vk.VK_SUCCESS) return error.vkCreateInstance;
    defer vk.vkDestroyInstance(vk_instance, null);
    const createInfo = vk.VkWin32SurfaceCreateInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .hinstance = vk_hInstance,
        .hwnd = vk_window,
    };
    if (vk.vkCreateWin32SurfaceKHR(vk_instance, &createInfo, null, &vk_state.surface) != vk.VK_SUCCESS) return error.vkCreateWin32;
    defer vk.vkDestroySurfaceKHR(vk_instance, vk_state.surface, null);
    vk_state.physical_device = try pickPhysicalDevice(vk_instance);
    try createLogicalDevice(vk_state.physical_device);
    defer vk.vkDestroyDevice(vk_state.logicalDevice, null);
    try createSwapChain();
    defer vk.vkDestroySwapchainKHR(vk_state.logicalDevice, vk_state.swapchain, null);
    //vkDestroySwapchainKHR don't forget
    // keep running for 2sec
    var counter: u32 = 0;
    while (counter < 20) {
        counter += 1;
        std.time.sleep(100_000_000);
    }
}

fn createSwapChain() !void {
    vk_state.swapchain_info.support = try querySwapChainSupport();
    vk_state.swapchain_info.format = chooseSwapSurfaceFormat(vk_state.swapchain_info.support.formats);
    vk_state.swapchain_info.present = chooseSwapPresentMode(vk_state.swapchain_info.support.presentModes);
    vk_state.swapchain_info.extent = chooseSwapExtent(vk_state.swapchain_info.support.capabilities);

    var imageCount = vk_state.swapchain_info.support.capabilities.minImageCount + 1;
    if (vk_state.swapchain_info.support.capabilities.maxImageCount > 0 and imageCount > vk_state.swapchain_info.support.capabilities.maxImageCount) {
        imageCount = vk_state.swapchain_info.support.capabilities.maxImageCount;
    }

    var createInfo = vk.VkSwapchainCreateInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = vk_state.surface,
        .minImageCount = imageCount,
        .imageFormat = vk_state.swapchain_info.format.format,
        .imageColorSpace = vk_state.swapchain_info.format.colorSpace,
        .imageExtent = vk_state.swapchain_info.extent,
        .imageArrayLayers = 1,
        .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = vk_state.swapchain_info.support.capabilities.currentTransform,
        .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = vk_state.swapchain_info.present,
        .clipped = vk.VK_TRUE,
        .oldSwapchain = null,
    };

    const indices = try findQueueFamilies(vk_state.physical_device);
    const queueFamilyIndices = [_]u32{ indices.graphicsFamily.?, indices.presentFamily.? };
    if (indices.graphicsFamily != indices.presentFamily) {
        createInfo.imageSharingMode = vk.VK_SHARING_MODE_CONCURRENT;
        createInfo.queueFamilyIndexCount = 2;
        createInfo.pQueueFamilyIndices = &queueFamilyIndices;
    } else {
        createInfo.imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE;
    }

    try vkcheck(vk.vkCreateSwapchainKHR(vk_state.logicalDevice, &createInfo, null, &vk_state.swapchain), "Failed to create swapchain KHR");
    std.debug.print("Swapchain KHR Created : {any}\n", .{vk_state.logicalDevice});

    _ = vk.vkGetSwapchainImagesKHR(vk_state.logicalDevice, vk_state.swapchain, &imageCount, null);
    vk_state.swapchain_info.images = try std.heap.page_allocator.alloc(vk.VkImage, imageCount);
    _ = vk.vkGetSwapchainImagesKHR(vk_state.logicalDevice, vk_state.swapchain, &imageCount, vk_state.swapchain_info.images.ptr);
}

fn querySwapChainSupport() !SwapChainSupportDetails {
    var details = SwapChainSupportDetails{
        .capabilities = undefined,
        .formats = &.{},
        .presentModes = &.{},
    };

    var formatCount: u32 = 0;
    var presentModeCount: u32 = 0;
    _ = vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk_state.physical_device, vk_state.surface, &details.capabilities);
    _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(vk_state.physical_device, vk_state.surface, &formatCount, null);
    if (formatCount > 0) {
        details.formats = try std.heap.page_allocator.alloc(vk.VkSurfaceFormatKHR, formatCount);
        _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(vk_state.physical_device, vk_state.surface, &formatCount, details.formats.ptr);
    }
    _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(vk_state.physical_device, vk_state.surface, &presentModeCount, null);
    if (presentModeCount > 0) {
        details.presentModes = try std.heap.page_allocator.alloc(vk.VkPresentModeKHR, presentModeCount);
        _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(vk_state.physical_device, vk_state.surface, &presentModeCount, details.presentModes.ptr);
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
        _ = vk.GetClientRect(vk_state.window, &rect);
        var actual_extent = vk.VkExtent2D{
            .width = @intCast(rect.right - rect.left),
            .height = @intCast(rect.bottom - rect.top),
        };
        actual_extent.width = std.math.clamp(actual_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
        actual_extent.height = std.math.clamp(actual_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);
        return actual_extent;
    }
}

fn createLogicalDevice(physical_device: vk.VkPhysicalDevice) !void {
    var queue_create_info = vk.VkDeviceQueueCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = graphics_queue_family_idx,
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
    device_create_info.enabledLayerCount = 0;
    device_create_info.ppEnabledLayerNames = null;
    try vkcheck(vk.vkCreateDevice(physical_device, &device_create_info, null, &vk_state.logicalDevice), "Failed to create logical device");
    std.debug.print("Logical Device Created : {any}\n", .{vk_state.logicalDevice});
    vk.vkGetDeviceQueue(vk_state.logicalDevice, graphics_queue_family_idx, 0, &vk_state.queue);
    std.debug.print("Queue Obtained : {any}\n", .{vk_state.queue});
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
var graphics_queue_family_idx: u32 = undefined;
fn isDeviceSuitable(device: vk.VkPhysicalDevice) !bool {
    const indices: QueueFamilyIndices = try findQueueFamilies(device);
    graphics_queue_family_idx = indices.graphicsFamily.?;
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
        _ = vk.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), vk_state.surface, &presentSupport);
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
