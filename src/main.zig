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
//    - continue https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/00_Setup/04_Logical_device_and_queues.html
//       - winAPI and vulcan.h only https://github.com/DarknessFX/zig_workbench/blob/fd6bae8f9236782f92759e64eecbbcc46fad83d6/BaseVulkan/main_vulkanw32.zig#L142
//       - zig version which follows tutorial, but old and uses glfw which is no longer maintained for zig? https://github.com/Vulfox/vulkan-tutorial-zig/tree/main
// draw anything in window
//
pub fn main() !void {
    std.debug.print("start\n", .{});

    try initWindow();
    // keep running for 2sec
    var counter: u32 = 0;
    while (counter < 20) {
        counter += 1;
        std.time.sleep(100_000_000);
    }
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
    var surface: vk.VkSurfaceKHR = undefined;
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
    if (vk.vkCreateWin32SurfaceKHR(vk_instance, &createInfo, null, &surface) != vk.VK_SUCCESS) return error.vkCreateWin32;
    defer vk.vkDestroySurfaceKHR(vk_instance, surface, null);
    const device = try pickPhysicalDevice(vk_instance, surface);
    _ = device;
}

fn wndProc(hwnd: zigWin32.foundation.HWND, msg: u32, wParam: std.os.windows.WPARAM, lParam: std.os.windows.LPARAM) callconv(std.builtin.CallingConvention.winapi) std.os.windows.LRESULT {
    std.debug.print("wndProc msg:{}\n", .{msg});
    return ui.DefWindowProcW(hwnd, msg, wParam, lParam);
}

fn pickPhysicalDevice(instance: vk.VkInstance, surface: vk.VkSurfaceKHR) !vk.VkPhysicalDevice {
    var device_count: u32 = 0;
    try vkcheck(vk.vkEnumeratePhysicalDevices(instance, &device_count, null), "Failed to enumerate physical devices");
    if (device_count == 0) {
        return error.NoGPUsWithVulkanSupport;
    }

    const devices = try std.heap.page_allocator.alloc(vk.VkPhysicalDevice, device_count);
    defer std.heap.page_allocator.free(devices);
    try vkcheck(vk.vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr), "Failed to enumerate physical devices");

    for (devices) |device| {
        if (try isDeviceSuitable(device, surface)) {
            return device;
        }
    }
    return error.NoSuitableGPU;
}
var graphics_queue_family_idx: u32 = undefined;
fn isDeviceSuitable(device: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR) !bool {
    const indices: QueueFamilyIndices = try findQueueFamilies(device, surface);
    graphics_queue_family_idx = indices.graphicsFamily.?;
    return indices.isComplete();
}

fn findQueueFamilies(device: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR) !QueueFamilyIndices {
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
        _ = vk.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &presentSupport);
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
