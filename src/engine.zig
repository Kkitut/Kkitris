const std = @import("std");
const bc = @import("c.zig");
const c = bc.c;
const logger = @import("logger.zig");
const helper = @import("helper.zig");

pub const max_frames_in_flight = 2;

const ShaderModules = struct {
    vert: c.VkShaderModule,
    frag: c.VkShaderModule,
};

const Buffer = struct {
    handle: c.VkBuffer,
    memory: c.VkDeviceMemory,
};

/// Per-instance data for the test quad. Layout must match object.vert.
const InstanceData = extern struct {
    color: [4]f32,
    position: [2]f32,
    scale: [2]f32,
    rotation: f32,
    texture_index: u32,
};

pub const Engine = struct {
    window: ?*c.GLFWwindow = null,
    instance: c.VkInstance = null,
    surface: c.VkSurfaceKHR = null,
    physical_device: c.VkPhysicalDevice = null,
    queue_family_index: u32 = 0,
    device: c.VkDevice = null,
    graphics_queue: c.VkQueue = null,
    present_queue: c.VkQueue = null,
    swapchain: c.VkSwapchainKHR = null,
    swapchain_images: []c.VkImage = &.{},
    swapchain_image_format: c.VkFormat = 0,
    swapchain_image_color_space: c.VkColorSpaceKHR = 0,
    swapchain_extent: c.VkExtent2D = .{ .width = 0, .height = 0 },
    swapchain_image_views: []c.VkImageView = &.{},
    swapchain_framebuffers: []c.VkFramebuffer = &.{},
    render_pass: c.VkRenderPass = null,
    descriptor_set_layout: c.VkDescriptorSetLayout = null,
    pipeline_layout: c.VkPipelineLayout = null,
    graphics_pipeline: c.VkPipeline = null,
    command_pool: c.VkCommandPool = null,
    command_buffers: []c.VkCommandBuffer = &.{},
    image_available_semaphores: [max_frames_in_flight]c.VkSemaphore = [_]c.VkSemaphore{null} ** max_frames_in_flight,
    render_finished_semaphores: [max_frames_in_flight]c.VkSemaphore = [_]c.VkSemaphore{null} ** max_frames_in_flight,
    in_flight_fences: [max_frames_in_flight]c.VkFence = [_]c.VkFence{null} ** max_frames_in_flight,
    current_frame: u32 = 0,
    framebuffer_resized: bool = false,
    instance_buffer: c.VkBuffer = null,
    instance_memory: c.VkDeviceMemory = null,
    instance_mapped: []u8 = &.{},
    test_image: c.VkImage = null,
    test_image_memory: c.VkDeviceMemory = null,
    test_image_view: c.VkImageView = null,
    test_sampler: c.VkSampler = null,
    descriptor_pool: c.VkDescriptorPool = null,
    descriptor_set: c.VkDescriptorSet = null,
    test_rotation: f32 = 0,
    io: std.Io,
    allocator: std.mem.Allocator,

    pub fn init(self: *Engine, io: std.Io, allocator: std.mem.Allocator, window: ?*c.GLFWwindow) !void {
        self.* = .{ .io = io, .allocator = allocator, .window = window };
        errdefer self.deinit();

        try self.createInstance();
        try self.createSurface();
        try self.pickAndInitDevice();
    }

    /// Pick GPUs in score order and bring up the first one that works end to
    /// end. A GPU can report surface support yet fail later (e.g. an NVIDIA
    /// dGPU that cannot present to a Wayland compositor running on the iGPU),
    /// so fall through to the next candidate instead of giving up.
    fn pickAndInitDevice(self: *Engine) !void {
        var device_count: u32 = 0;
        var result = c.vkEnumeratePhysicalDevices(self.instance, &device_count, null);
        if (result != c.VK_SUCCESS or device_count == 0) {
            logger.fail("Failed to find GPUs with Vulkan support: {d}", .{result});
            return error.NoSuitableGpu;
        }

        const devices = self.allocator.alloc(c.VkPhysicalDevice, device_count) catch
            return error.OutOfMemory;
        defer self.allocator.free(devices);

        result = c.vkEnumeratePhysicalDevices(self.instance, &device_count, devices.ptr);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to enumerate GPUs: {d}", .{result});
            return error.NoSuitableGpu;
        }

        const scores = self.allocator.alloc(u32, devices.len) catch return error.OutOfMemory;
        defer self.allocator.free(scores);

        const tried = self.allocator.alloc(bool, devices.len) catch return error.OutOfMemory;
        defer self.allocator.free(tried);
        @memset(tried, false);

        for (devices, 0..) |dev, i| {
            var properties: c.VkPhysicalDeviceProperties = undefined;
            c.vkGetPhysicalDeviceProperties(dev, &properties);

            const name_len =
                std.mem.indexOfScalar(u8, &properties.deviceName, 0) orelse
                properties.deviceName.len;

            scores[i] = self.rateDeviceSuitability(dev);
            logger.info("Vulkan GPU {d}: {s} (Type: {d}, Score: {d})", .{
                i,
                properties.deviceName[0..name_len],
                properties.deviceType,
                scores[i],
            });
        }

        var last_err: anyerror = error.NoSuitableGpu;
        while (true) {
            var best: ?usize = null;
            for (scores, 0..) |score, i| {
                if (!tried[i] and score > 0 and (best == null or score > scores[best.?])) {
                    best = i;
                }
            }
            const bi = best orelse break;
            tried[bi] = true;

            self.physical_device = devices[bi];
            self.queue_family_index = self.findQueueFamily(devices[bi]);

            self.initDevice() catch |err| {
                logger.warn("GPU {d} failed to initialize, trying next", .{bi});
                last_err = err;
                self.deinitDevice();
                continue;
            };

            var properties: c.VkPhysicalDeviceProperties = undefined;
            c.vkGetPhysicalDeviceProperties(self.physical_device, &properties);
            const name_len =
                std.mem.indexOfScalar(u8, &properties.deviceName, 0) orelse
                properties.deviceName.len;
            logger.info("Selected Vulkan GPU: {s} (Score: {d})", .{
                properties.deviceName[0..name_len],
                scores[bi],
            });
            return;
        }

        logger.fail("No suitable GPU found with Graphics and Surface support", .{});
        return last_err;
    }

    fn initDevice(self: *Engine) !void {
        try self.createLogicalDevice();
        try self.chooseSurfaceFormat();
        try self.createRenderPass();
        try self.createDescriptorLayout();

        var width: c_int = 0;
        var height: c_int = 0;
        c.glfwGetFramebufferSize(self.window.?, &width, &height);
        try self.createSwapchainResources(@intCast(width), @intCast(height));

        try self.createCommandPoolAndFences();
        try self.createFrameSemaphores();
        try self.createCommandBuffers();
        try self.createTestResources();
    }

    fn deinitTestResources(self: *Engine) void {
        if (self.instance_mapped.len > 0) {
            c.vkUnmapMemory(self.device, self.instance_memory);
            self.instance_mapped = &.{};
        }

        if (self.instance_buffer != null) {
            c.vkDestroyBuffer(self.device, self.instance_buffer, null);
            self.instance_buffer = null;
        }

        if (self.instance_memory != null) {
            c.vkFreeMemory(self.device, self.instance_memory, null);
            self.instance_memory = null;
        }

        if (self.test_sampler != null) {
            c.vkDestroySampler(self.device, self.test_sampler, null);
            self.test_sampler = null;
        }

        if (self.test_image_view != null) {
            c.vkDestroyImageView(self.device, self.test_image_view, null);
            self.test_image_view = null;
        }

        if (self.test_image != null) {
            c.vkDestroyImage(self.device, self.test_image, null);
            self.test_image = null;
        }

        if (self.test_image_memory != null) {
            c.vkFreeMemory(self.device, self.test_image_memory, null);
            self.test_image_memory = null;
        }

        if (self.descriptor_pool != null) {
            c.vkDestroyDescriptorPool(self.device, self.descriptor_pool, null);
            self.descriptor_pool = null;
            self.descriptor_set = null;
        }
    }

    pub fn update(self: *Engine, dt: f32) void {
        self.test_rotation += dt * 0.8;
        self.writeTestInstance();
    }

    fn writeTestInstance(self: *Engine) void {
        if (self.instance_mapped.len < @sizeOf(InstanceData)) return;

        const w: f32 = @floatFromInt(self.swapchain_extent.width);
        const h: f32 = @floatFromInt(self.swapchain_extent.height);
        const inst = InstanceData{
            .color = .{ 1.0, 0.45, 0.1, 1.0 },
            .position = .{ w * 0.5, h * 0.5 },
            .scale = .{ 220, 220 },
            .rotation = self.test_rotation,
            .texture_index = 0,
        };
        std.mem.copyForwards(
            u8,
            self.instance_mapped[0..@sizeOf(InstanceData)],
            std.mem.asBytes(&inst),
        );
    }

    pub fn render(self: *Engine) void {
        const frame = self.current_frame;

        var result = c.vkWaitForFences(
            self.device,
            1,
            &self.in_flight_fences[frame],
            c.VK_TRUE,
            std.math.maxInt(u64),
        );
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to wait for fence: {d}", .{result});
            return;
        }

        var image_index: u32 = 0;
        result = c.vkAcquireNextImageKHR(
            self.device,
            self.swapchain,
            std.math.maxInt(u64),
            self.image_available_semaphores[frame],
            null,
            &image_index,
        );
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_ERROR_SURFACE_LOST_KHR) {
            return;
        }
        if (result != c.VK_SUCCESS and result != c.VK_SUBOPTIMAL_KHR) {
            logger.fail("Failed to acquire next image: {d}", .{result});
            return;
        }

        if (image_index >= self.swapchain_images.len) {
            logger.fail("Invalid swapchain image index: {d}", .{image_index});
            return;
        }

        result = c.vkResetFences(self.device, 1, &self.in_flight_fences[frame]);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to reset fence: {d}", .{result});
            return;
        }

        const command_buffer = self.command_buffers[image_index];

        result = c.vkResetCommandBuffer(command_buffer, 0);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to reset command buffer: {d}", .{result});
            return;
        }

        const begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        };
        result = c.vkBeginCommandBuffer(command_buffer, &begin_info);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to begin command buffer: {d}", .{result});
            return;
        }

        const clear_value = c.VkClearValue{
            .color = .{ .float32 = .{ 0, 0, 0, 1 } },
        };
        const render_pass_info = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .pNext = null,
            .renderPass = self.render_pass,
            .framebuffer = self.swapchain_framebuffers[image_index],
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swapchain_extent,
            },
            .clearValueCount = 1,
            .pClearValues = &clear_value,
        };

        c.vkCmdBeginRenderPass(command_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);
        c.vkCmdBindPipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.graphics_pipeline);

        var vbuf = self.instance_buffer;
        const voffset: c.VkDeviceSize = 0;
        c.vkCmdBindVertexBuffers(command_buffer, 0, 1, &vbuf, &voffset);

        var dset = self.descriptor_set;
        c.vkCmdBindDescriptorSets(
            command_buffer,
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.pipeline_layout,
            0,
            1,
            &dset,
            0,
            null,
        );

        const w: f32 = @floatFromInt(self.swapchain_extent.width);
        const h: f32 = @floatFromInt(self.swapchain_extent.height);
        var proj = [16]f32{
            2 / w, 0,     0, 0,
            0,     2 / h, 0, 0,
            0,     0,     1, 0,
            -1,    -1,    0, 1,
        };
        c.vkCmdPushConstants(
            command_buffer,
            self.pipeline_layout,
            c.VK_SHADER_STAGE_VERTEX_BIT,
            0,
            64,
            @ptrCast(&proj),
        );

        c.vkCmdDraw(command_buffer, 6, 1, 0, 0);

        c.vkCmdEndRenderPass(command_buffer);

        result = c.vkEndCommandBuffer(command_buffer);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to end command buffer: {d}", .{result});
            return;
        }

        const wait_stage: c.VkPipelineStageFlags =
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        var wait_semaphore = self.image_available_semaphores[frame];
        var signal_semaphore = self.render_finished_semaphores[frame];
        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &wait_semaphore,
            .pWaitDstStageMask = &wait_stage,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer,
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signal_semaphore,
        };
        result = c.vkQueueSubmit(
            self.graphics_queue,
            1,
            &submit_info,
            self.in_flight_fences[frame],
        );
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to submit queue: {d}", .{result});
            return;
        }

        var swapchain = self.swapchain;
        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pNext = null,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &signal_semaphore,
            .swapchainCount = 1,
            .pSwapchains = &swapchain,
            .pImageIndices = &image_index,
            .pResults = null,
        };
        result = c.vkQueuePresentKHR(self.present_queue, &present_info);
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR) {
            self.framebuffer_resized = true;
        } else if (result == c.VK_ERROR_SURFACE_LOST_KHR) {
            return;
        } else if (result != c.VK_SUCCESS) {
            logger.fail("Failed to present swapchain: {d}", .{result});
            return;
        }

        self.current_frame = (self.current_frame + 1) % max_frames_in_flight;
    }

    pub fn deinit(self: *Engine) void {
        self.deinitDevice();

        if (self.surface != null and self.instance != null) {
            c.vkDestroySurfaceKHR(self.instance, self.surface, null);
            self.surface = null;
        }

        if (self.instance != null) {
            c.vkDestroyInstance(self.instance, null);
            self.instance = null;
        }

        self.window = null;
    }

    fn deinitDevice(self: *Engine) void {
        if (self.device != null) {
            _ = c.vkDeviceWaitIdle(self.device);

            self.deinitTestResources();

            if (self.command_buffers.len > 0) {
                self.allocator.free(self.command_buffers);
                self.command_buffers = &.{};
            }

            for (0..max_frames_in_flight) |i| {
                if (self.image_available_semaphores[i] != null) {
                    c.vkDestroySemaphore(self.device, self.image_available_semaphores[i], null);
                    self.image_available_semaphores[i] = null;
                }
                if (self.render_finished_semaphores[i] != null) {
                    c.vkDestroySemaphore(self.device, self.render_finished_semaphores[i], null);
                    self.render_finished_semaphores[i] = null;
                }
                if (self.in_flight_fences[i] != null) {
                    c.vkDestroyFence(self.device, self.in_flight_fences[i], null);
                    self.in_flight_fences[i] = null;
                }
            }

            if (self.swapchain_framebuffers.len > 0) {
                for (self.swapchain_framebuffers) |fb| {
                    if (fb != null) c.vkDestroyFramebuffer(self.device, fb, null);
                }
                self.allocator.free(self.swapchain_framebuffers);
                self.swapchain_framebuffers = &.{};
            }

            if (self.swapchain_image_views.len > 0) {
                for (self.swapchain_image_views) |view| {
                    if (view != null) c.vkDestroyImageView(self.device, view, null);
                }
                self.allocator.free(self.swapchain_image_views);
                self.swapchain_image_views = &.{};
            }

            if (self.swapchain_images.len > 0) {
                self.allocator.free(self.swapchain_images);
                self.swapchain_images = &.{};
            }

            if (self.swapchain != null) {
                c.vkDestroySwapchainKHR(self.device, self.swapchain, null);
                self.swapchain = null;
            }

            if (self.graphics_pipeline != null) {
                c.vkDestroyPipeline(self.device, self.graphics_pipeline, null);
                self.graphics_pipeline = null;
            }

            if (self.pipeline_layout != null) {
                c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
                self.pipeline_layout = null;
            }

            if (self.render_pass != null) {
                c.vkDestroyRenderPass(self.device, self.render_pass, null);
                self.render_pass = null;
            }

            if (self.descriptor_set_layout != null) {
                c.vkDestroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
                self.descriptor_set_layout = null;
            }

            if (self.command_pool != null) {
                c.vkDestroyCommandPool(self.device, self.command_pool, null);
                self.command_pool = null;
            }

            c.vkDestroyDevice(self.device, null);
            self.device = null;
        }
    }

    fn readSpv(self: *Engine, path: []const u8) ![]u32 {
        const cwd = std.Io.Dir.cwd();

        var file = cwd.openFile(self.io, path, .{}) catch return error.ShaderNotFound;
        defer file.close(self.io);

        const st = file.stat(self.io) catch return error.ShaderNotFound;
        if (st.size % @sizeOf(u32) != 0) return error.ShaderInvalid;

        const words = self.allocator.alloc(u32, st.size / @sizeOf(u32)) catch
            return error.OutOfMemory;
        errdefer self.allocator.free(words);

        var reader = file.reader(self.io, &.{});
        reader.interface.readSliceAll(std.mem.sliceAsBytes(words)) catch
            return error.ShaderReadFailed;

        return words;
    }

    fn createShaderModules(self: *Engine) !ShaderModules {
        var exe_buf: [4096]u8 = undefined;
        const exe_dir = helper.getExecutableDirectory(self.io, &exe_buf) orelse
            return error.ShaderNotFound;

        var vert_buf: [4096]u8 = undefined;
        const vert_path = helper.makePath(&vert_buf, exe_dir, "shader/object.vert.spv") orelse {
            logger.fail("Vertex shader path is too long", .{});
            return error.ShaderNotFound;
        };

        var frag_buf: [4096]u8 = undefined;
        const frag_path = helper.makePath(&frag_buf, exe_dir, "shader/object.frag.spv") orelse {
            logger.fail("Fragment shader path is too long", .{});
            return error.ShaderNotFound;
        };

        const vert_code = self.readSpv(vert_path) catch {
            logger.fail("Failed to load object.vert.spv", .{});
            return error.ShaderNotFound;
        };
        defer self.allocator.free(vert_code);

        const frag_code = self.readSpv(frag_path) catch {
            logger.fail("Failed to load object.frag.spv", .{});
            return error.ShaderNotFound;
        };
        defer self.allocator.free(frag_code);

        const vert_info = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = vert_code.len * @sizeOf(u32),
            .pCode = @ptrCast(vert_code.ptr),
        };
        const frag_info = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = frag_code.len * @sizeOf(u32),
            .pCode = @ptrCast(frag_code.ptr),
        };

        var vert_module: c.VkShaderModule = null;
        var result = c.vkCreateShaderModule(self.device, &vert_info, null, &vert_module);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create vertex shader module: {d}", .{result});
            return error.ShaderModuleFailed;
        }
        errdefer c.vkDestroyShaderModule(self.device, vert_module, null);

        var frag_module: c.VkShaderModule = null;
        result = c.vkCreateShaderModule(self.device, &frag_info, null, &frag_module);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create fragment shader module: {d}", .{result});
            return error.ShaderModuleFailed;
        }

        return .{ .vert = vert_module, .frag = frag_module };
    }

    fn createInstance(self: *Engine) !void {
        var extension_count: u32 = 0;
        const extensions = c.glfwGetRequiredInstanceExtensions(&extension_count);
        if (extensions == null) {
            logger.fail("Failed to get required Vulkan extensions from GLFW", .{});
            return error.VulkanInstanceFailed;
        }

        const app_info = c.VkApplicationInfo{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pNext = null,
            .pApplicationName = "Kkitris",
            .applicationVersion = bc.makeApiVersion(0, 1, 0, 0),
            .pEngineName = "No Engine",
            .engineVersion = bc.makeApiVersion(0, 1, 0, 0),
            .apiVersion = bc.api_version_1_3,
        };
        const create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .pApplicationInfo = &app_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = extension_count,
            .ppEnabledExtensionNames = extensions,
        };

        const result = c.vkCreateInstance(&create_info, null, &self.instance);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create Vulkan instance: {d}", .{result});
            return error.VulkanInstanceFailed;
        }
    }

    fn createSurface(self: *Engine) !void {
        const result = c.glfwCreateWindowSurface(
            self.instance,
            self.window.?,
            null,
            &self.surface,
        );
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create Vulkan surface: {d}", .{result});
            return error.VulkanSurfaceFailed;
        }
    }

    fn findQueueFamily(self: *Engine, device: c.VkPhysicalDevice) u32 {
        const no_family = std.math.maxInt(u32);

        var count: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &count, null);

        const families = self.allocator.alloc(c.VkQueueFamilyProperties, count) catch
            return no_family;
        defer self.allocator.free(families);

        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &count, families.ptr);

        const graphics_bit: u32 = c.VK_QUEUE_GRAPHICS_BIT;
        for (families, 0..) |fam, i| {
            const graphics = (fam.queueFlags & graphics_bit) != 0;

            var present: c.VkBool32 = c.VK_FALSE;
            const result = c.vkGetPhysicalDeviceSurfaceSupportKHR(
                device,
                @intCast(i),
                self.surface,
                &present,
            );
            if (result != c.VK_SUCCESS) continue;

            if (graphics and present != 0) return @intCast(i);
        }

        return no_family;
    }

    fn rateDeviceSuitability(self: *Engine, device: c.VkPhysicalDevice) u32 {
        if (self.findQueueFamily(device) == std.math.maxInt(u32)) return 0;

        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(device, &properties);

        var score: u32 = 0;
        switch (properties.deviceType) {
            c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => score += 10000,
            c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => score += 1000,
            c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => score += 100,
            c.VK_PHYSICAL_DEVICE_TYPE_CPU => score += 1,
            else => score += 10,
        }
        score += properties.limits.maxImageDimension2D;

        return score;
    }

    fn createLogicalDevice(self: *Engine) !void {
        var queue_priority: f32 = 1.0;
        const queue_info = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = self.queue_family_index,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };

        const device_extensions = [_][*c]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

        var features12 = c.VkPhysicalDeviceVulkan12Features{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
            .pNext = null,
            .samplerMirrorClampToEdge = c.VK_FALSE,
            .drawIndirectCount = c.VK_FALSE,
            .storageBuffer8BitAccess = c.VK_FALSE,
            .uniformAndStorageBuffer8BitAccess = c.VK_FALSE,
            .storagePushConstant8 = c.VK_FALSE,
            .shaderBufferInt64Atomics = c.VK_FALSE,
            .shaderSharedInt64Atomics = c.VK_FALSE,
            .shaderFloat16 = c.VK_FALSE,
            .shaderInt8 = c.VK_FALSE,
            .descriptorIndexing = c.VK_FALSE,
            .shaderInputAttachmentArrayDynamicIndexing = c.VK_FALSE,
            .shaderUniformTexelBufferArrayDynamicIndexing = c.VK_FALSE,
            .shaderStorageTexelBufferArrayDynamicIndexing = c.VK_FALSE,
            .shaderUniformBufferArrayNonUniformIndexing = c.VK_FALSE,
            .shaderSampledImageArrayNonUniformIndexing = c.VK_TRUE,
            .shaderStorageBufferArrayNonUniformIndexing = c.VK_FALSE,
            .shaderStorageImageArrayNonUniformIndexing = c.VK_FALSE,
            .shaderInputAttachmentArrayNonUniformIndexing = c.VK_FALSE,
            .shaderUniformTexelBufferArrayNonUniformIndexing = c.VK_FALSE,
            .shaderStorageTexelBufferArrayNonUniformIndexing = c.VK_FALSE,
            .descriptorBindingUniformBufferUpdateAfterBind = c.VK_FALSE,
            .descriptorBindingSampledImageUpdateAfterBind = c.VK_TRUE,
            .descriptorBindingStorageImageUpdateAfterBind = c.VK_FALSE,
            .descriptorBindingStorageBufferUpdateAfterBind = c.VK_FALSE,
            .descriptorBindingUniformTexelBufferUpdateAfterBind = c.VK_FALSE,
            .descriptorBindingStorageTexelBufferUpdateAfterBind = c.VK_FALSE,
            .descriptorBindingUpdateUnusedWhilePending = c.VK_FALSE,
            .descriptorBindingPartiallyBound = c.VK_TRUE,
            .descriptorBindingVariableDescriptorCount = c.VK_FALSE,
            .runtimeDescriptorArray = c.VK_TRUE,
            .samplerFilterMinmax = c.VK_FALSE,
            .scalarBlockLayout = c.VK_FALSE,
            .imagelessFramebuffer = c.VK_FALSE,
            .uniformBufferStandardLayout = c.VK_FALSE,
            .shaderSubgroupExtendedTypes = c.VK_FALSE,
            .separateDepthStencilLayouts = c.VK_FALSE,
            .hostQueryReset = c.VK_FALSE,
            .timelineSemaphore = c.VK_FALSE,
            .bufferDeviceAddress = c.VK_FALSE,
            .bufferDeviceAddressCaptureReplay = c.VK_FALSE,
            .bufferDeviceAddressMultiDevice = c.VK_FALSE,
            .vulkanMemoryModel = c.VK_FALSE,
            .vulkanMemoryModelDeviceScope = c.VK_FALSE,
            .vulkanMemoryModelAvailabilityVisibilityChains = c.VK_FALSE,
            .shaderOutputViewportIndex = c.VK_FALSE,
            .shaderOutputLayer = c.VK_FALSE,
            .subgroupBroadcastDynamicId = c.VK_FALSE,
        };

        const create_info = c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = &features12,
            .flags = 0,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queue_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = 1,
            .ppEnabledExtensionNames = device_extensions[0..].ptr,
        };

        const result = c.vkCreateDevice(self.physical_device, &create_info, null, &self.device);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create logical device: {d}", .{result});
            return error.LogicalDeviceFailed;
        }

        c.vkGetDeviceQueue(self.device, self.queue_family_index, 0, &self.graphics_queue);
        self.present_queue = self.graphics_queue;
    }

    fn createGraphicsPipeline(self: *Engine) !void {
        const mods = try self.createShaderModules();
        defer c.vkDestroyShaderModule(self.device, mods.vert, null);
        defer c.vkDestroyShaderModule(self.device, mods.frag, null);

        var stages = [_]c.VkPipelineShaderStageCreateInfo{
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                .module = mods.vert,
                .pName = "main",
                .pSpecializationInfo = null,
            },
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .module = mods.frag,
                .pName = "main",
                .pSpecializationInfo = null,
            },
        };

        // Must match `PushConstants` in object.vert (mat4 = 64 bytes).
        const push_range = c.VkPushConstantRange{
            .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
            .offset = 0,
            .size = 64,
        };
        const layout_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = 1,
            .pSetLayouts = &self.descriptor_set_layout,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &push_range,
        };
        var result = c.vkCreatePipelineLayout(self.device, &layout_info, null, &self.pipeline_layout);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create pipeline layout: {d}", .{result});
            return error.PipelineFailed;
        }
        errdefer {
            c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
            self.pipeline_layout = null;
        }

        const binding_desc = c.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(InstanceData),
            .inputRate = c.VK_VERTEX_INPUT_RATE_INSTANCE,
        };
        var attr_descs = [_]c.VkVertexInputAttributeDescription{
            .{ .location = 0, .binding = 0, .format = c.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 0 },
            .{ .location = 1, .binding = 0, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = 16 },
            .{ .location = 2, .binding = 0, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = 24 },
            .{ .location = 3, .binding = 0, .format = c.VK_FORMAT_R32_SFLOAT, .offset = 32 },
            .{ .location = 4, .binding = 0, .format = c.VK_FORMAT_R32_UINT, .offset = 36 },
        };
        const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .vertexBindingDescriptionCount = 1,
            .pVertexBindingDescriptions = &binding_desc,
            .vertexAttributeDescriptionCount = 5,
            .pVertexAttributeDescriptions = attr_descs[0..].ptr,
        };
        const input_assembly_info = c.VkPipelineInputAssemblyStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        var viewport = c.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swapchain_extent.width),
            .height = @floatFromInt(self.swapchain_extent.height),
            .minDepth = 0,
            .maxDepth = 1,
        };
        var scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain_extent,
        };
        const viewport_state_info = c.VkPipelineViewportStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .viewportCount = 1,
            .pViewports = &viewport,
            .scissorCount = 1,
            .pScissors = &scissor,
        };

        const rasterization_info = c.VkPipelineRasterizationStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .depthClampEnable = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .polygonMode = c.VK_POLYGON_MODE_FILL,
            .cullMode = c.VK_CULL_MODE_NONE,
            .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
            .depthBiasEnable = c.VK_FALSE,
            .depthBiasConstantFactor = 0,
            .depthBiasClamp = 0,
            .depthBiasSlopeFactor = 0,
            .lineWidth = 1,
        };
        const multisample_info = c.VkPipelineMultisampleStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
            .sampleShadingEnable = c.VK_FALSE,
            .minSampleShading = 0,
            .pSampleMask = null,
            .alphaToCoverageEnable = c.VK_FALSE,
            .alphaToOneEnable = c.VK_FALSE,
        };

        const color_write_mask: u32 =
            c.VK_COLOR_COMPONENT_R_BIT |
            c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT |
            c.VK_COLOR_COMPONENT_A_BIT;
        const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
            .blendEnable = c.VK_TRUE,
            .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA,
            .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .colorBlendOp = c.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp = c.VK_BLEND_OP_ADD,
            .colorWriteMask = color_write_mask,
        };
        const color_blend_info = c.VkPipelineColorBlendStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_CLEAR,
            .attachmentCount = 1,
            .pAttachments = &color_blend_attachment,
            .blendConstants = .{ 0, 0, 0, 0 },
        };

        const pipeline_info = c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stageCount = 2,
            .pStages = stages[0..].ptr,
            .pVertexInputState = &vertex_input_info,
            .pInputAssemblyState = &input_assembly_info,
            .pTessellationState = null,
            .pViewportState = &viewport_state_info,
            .pRasterizationState = &rasterization_info,
            .pMultisampleState = &multisample_info,
            .pDepthStencilState = null,
            .pColorBlendState = &color_blend_info,
            .pDynamicState = null,
            .layout = self.pipeline_layout,
            .renderPass = self.render_pass,
            .subpass = 0,
            .basePipelineHandle = null,
            .basePipelineIndex = 0,
        };
        result = c.vkCreateGraphicsPipelines(
            self.device,
            null,
            1,
            &pipeline_info,
            null,
            &self.graphics_pipeline,
        );
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create graphics pipeline: {d}", .{result});
            return error.PipelineFailed;
        }
    }

    fn createSwapchainResources(self: *Engine, width: u32, height: u32) !void {
        var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
        var result = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            self.physical_device,
            self.surface,
            &capabilities,
        );
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to get surface capabilities: {d}", .{result});
            return error.SwapchainFailed;
        }

        var extent: c.VkExtent2D = undefined;
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            extent = capabilities.currentExtent;
        } else {
            extent.width = @min(
                @max(width, capabilities.minImageExtent.width),
                capabilities.maxImageExtent.width,
            );
            extent.height = @min(
                @max(height, capabilities.minImageExtent.height),
                capabilities.maxImageExtent.height,
            );
        }
        self.swapchain_extent = extent;

        var image_count = capabilities.minImageCount + 1;
        if (capabilities.maxImageCount > 0 and image_count > capabilities.maxImageCount) {
            image_count = capabilities.maxImageCount;
        }

        const create_info = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .surface = self.surface,
            .minImageCount = image_count,
            .imageFormat = self.swapchain_image_format,
            .imageColorSpace = self.swapchain_image_color_space,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .preTransform = capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = c.VK_PRESENT_MODE_FIFO_KHR,
            .clipped = c.VK_TRUE,
            .oldSwapchain = self.swapchain,
        };
        result = c.vkCreateSwapchainKHR(self.device, &create_info, null, &self.swapchain);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create swapchain: {d}", .{result});
            return error.SwapchainFailed;
        }

        var actual_count: u32 = 0;
        result = c.vkGetSwapchainImagesKHR(self.device, self.swapchain, &actual_count, null);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to get swapchain image count: {d}", .{result});
            return error.SwapchainFailed;
        }

        const images = self.allocator.alloc(c.VkImage, actual_count) catch
            return error.OutOfMemory;
        errdefer self.allocator.free(images);

        result = c.vkGetSwapchainImagesKHR(self.device, self.swapchain, &actual_count, images.ptr);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to get swapchain images: {d}", .{result});
            return error.SwapchainFailed;
        }
        self.swapchain_images = images;

        const views = self.allocator.alloc(c.VkImageView, self.swapchain_images.len) catch
            return error.OutOfMemory;
        errdefer self.allocator.free(views);

        for (self.swapchain_images, 0..) |image, i| {
            const view_info = c.VkImageViewCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .image = image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = self.swapchain_image_format,
                .components = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };
            result = c.vkCreateImageView(self.device, &view_info, null, &views[i]);
            if (result != c.VK_SUCCESS) {
                logger.fail("Failed to create swapchain image view {d}: {d}", .{
                    i,
                    result,
                });
                return error.SwapchainFailed;
            }
        }
        self.swapchain_image_views = views;

        const framebuffers = self.allocator.alloc(c.VkFramebuffer, self.swapchain_images.len) catch
            return error.OutOfMemory;
        errdefer self.allocator.free(framebuffers);

        for (self.swapchain_image_views, 0..) |view, i| {
            const attachments = [_]c.VkImageView{view};
            const framebuffer_info = c.VkFramebufferCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .renderPass = self.render_pass,
                .attachmentCount = 1,
                .pAttachments = attachments[0..].ptr,
                .width = extent.width,
                .height = extent.height,
                .layers = 1,
            };
            result = c.vkCreateFramebuffer(self.device, &framebuffer_info, null, &framebuffers[i]);
            if (result != c.VK_SUCCESS) {
                logger.fail("Failed to create framebuffer {d}: {d}", .{
                    i,
                    result,
                });
                return error.SwapchainFailed;
            }
        }
        self.swapchain_framebuffers = framebuffers;

        try self.createGraphicsPipeline();
    }

    fn chooseSurfaceFormat(self: *Engine) !void {
        var count: u32 = 0;
        var result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(
            self.physical_device,
            self.surface,
            &count,
            null,
        );
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to get surface format count: {d}", .{result});
            return error.SurfaceFormatFailed;
        }
        if (count == 0) {
            logger.fail("No Vulkan surface formats available", .{});
            return error.SurfaceFormatFailed;
        }

        const formats = self.allocator.alloc(c.VkSurfaceFormatKHR, count) catch
            return error.OutOfMemory;
        defer self.allocator.free(formats);

        result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(
            self.physical_device,
            self.surface,
            &count,
            formats.ptr,
        );
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to get surface formats: {d}", .{result});
            return error.SurfaceFormatFailed;
        }

        var chosen = formats[0];
        for (formats) |format| {
            if (format.format == c.VK_FORMAT_R8G8B8A8_UNORM) {
                chosen = format;
                break;
            }
        }

        self.swapchain_image_format = chosen.format;
        self.swapchain_image_color_space = chosen.colorSpace;
    }

    fn createRenderPass(self: *Engine) !void {
        const color_attachment = c.VkAttachmentDescription{
            .flags = 0,
            .format = self.swapchain_image_format,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };
        const color_attachment_ref = c.VkAttachmentReference{
            .attachment = 0,
            .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };
        const subpass = c.VkSubpassDescription{
            .flags = 0,
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .inputAttachmentCount = 0,
            .pInputAttachments = null,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color_attachment_ref,
            .pResolveAttachments = null,
            .pDepthStencilAttachment = null,
            .preserveAttachmentCount = 0,
            .pPreserveAttachments = null,
        };
        const dependency = c.VkSubpassDependency{
            .srcSubpass = c.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = 0,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .dependencyFlags = 0,
        };
        const create_info = c.VkRenderPassCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .attachmentCount = 1,
            .pAttachments = &color_attachment,
            .subpassCount = 1,
            .pSubpasses = &subpass,
            .dependencyCount = 1,
            .pDependencies = &dependency,
        };

        const result = c.vkCreateRenderPass(self.device, &create_info, null, &self.render_pass);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create render pass: {d}", .{result});
            return error.RenderPassFailed;
        }
    }

    fn createCommandBuffers(self: *Engine) !void {
        const buffers = self.allocator.alloc(c.VkCommandBuffer, self.swapchain_images.len) catch {
            logger.fail("Failed to allocate command buffer list", .{});
            return error.OutOfMemory;
        };
        errdefer self.allocator.free(buffers);

        const alloc_info = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = self.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(buffers.len),
        };
        const result = c.vkAllocateCommandBuffers(self.device, &alloc_info, buffers.ptr);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to allocate command buffers: {d}", .{result});
            return error.CommandFailed;
        }

        self.command_buffers = buffers;
    }

    fn createCommandPoolAndFences(self: *Engine) !void {
        const pool_info = c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = self.queue_family_index,
        };
        var result = c.vkCreateCommandPool(self.device, &pool_info, null, &self.command_pool);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create command pool: {d}", .{result});
            return error.CommandFailed;
        }

        const fence_info = c.VkFenceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };
        for (0..max_frames_in_flight) |i| {
            result = c.vkCreateFence(self.device, &fence_info, null, &self.in_flight_fences[i]);
            if (result != c.VK_SUCCESS) {
                logger.fail("Failed to create fence {d}: {d}", .{ i, result });
                return error.CommandFailed;
            }
        }
    }

    fn createFrameSemaphores(self: *Engine) !void {
        const semaphore_info = c.VkSemaphoreCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
        };
        for (0..max_frames_in_flight) |i| {
            var result = c.vkCreateSemaphore(
                self.device,
                &semaphore_info,
                null,
                &self.image_available_semaphores[i],
            );
            if (result != c.VK_SUCCESS) {
                logger.fail("Failed to create image available semaphore {d}: {d}", .{
                    i,
                    result,
                });
                return error.SemaphoreFailed;
            }

            result = c.vkCreateSemaphore(
                self.device,
                &semaphore_info,
                null,
                &self.render_finished_semaphores[i],
            );
            if (result != c.VK_SUCCESS) {
                logger.fail("Failed to create render finished semaphore {d}: {d}", .{
                    i,
                    result,
                });
                return error.SemaphoreFailed;
            }
        }
    }

    fn createDescriptorLayout(self: *Engine) !void {
        var binding_flags: u32 =
            c.VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT |
            c.VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT;
        var binding_flags_info = c.VkDescriptorSetLayoutBindingFlagsCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
            .pNext = null,
            .bindingCount = 1,
            .pBindingFlags = &binding_flags,
        };
        const binding = c.VkDescriptorSetLayoutBinding{
            .binding = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 4096,
            .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .pImmutableSamplers = null,
        };
        const layout_info = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pNext = &binding_flags_info,
            .flags = c.VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT,
            .bindingCount = 1,
            .pBindings = &binding,
        };

        const result = c.vkCreateDescriptorSetLayout(
            self.device,
            &layout_info,
            null,
            &self.descriptor_set_layout,
        );
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create descriptor set layout: {d}", .{result});
            return error.DescriptorFailed;
        }
    }

    fn findMemoryType(self: *Engine, type_filter: u32, properties: u32) !u32 {
        var mem_props: c.VkPhysicalDeviceMemoryProperties = undefined;
        c.vkGetPhysicalDeviceMemoryProperties(self.physical_device, &mem_props);

        for (0..mem_props.memoryTypeCount) |i| {
            const bit: u32 = @as(u32, 1) << @intCast(i);
            const flags = mem_props.memoryTypes[i].propertyFlags;
            if ((type_filter & bit) != 0 and (flags & properties) == properties) {
                return @intCast(i);
            }
        }

        logger.fail("Failed to find suitable memory type", .{});
        return error.NoSuitableMemory;
    }

    fn createBuffer(self: *Engine, size: u64, usage: u32, properties: u32) !Buffer {
        const info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = size,
            .usage = usage,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var buf: c.VkBuffer = null;
        var result = c.vkCreateBuffer(self.device, &info, null, &buf);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create buffer: {d}", .{result});
            return error.BufferFailed;
        }
        errdefer c.vkDestroyBuffer(self.device, buf, null);

        var req: c.VkMemoryRequirements = undefined;
        c.vkGetBufferMemoryRequirements(self.device, buf, &req);

        const mem_index = try self.findMemoryType(req.memoryTypeBits, properties);
        const alloc_info = c.VkMemoryAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = req.size,
            .memoryTypeIndex = mem_index,
        };

        var mem: c.VkDeviceMemory = null;
        result = c.vkAllocateMemory(self.device, &alloc_info, null, &mem);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to allocate buffer memory: {d}", .{result});
            return error.BufferFailed;
        }
        errdefer c.vkFreeMemory(self.device, mem, null);

        result = c.vkBindBufferMemory(self.device, buf, mem, 0);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to bind buffer memory: {d}", .{result});
            return error.BufferFailed;
        }

        return .{ .handle = buf, .memory = mem };
    }

    fn beginSingleUse(self: *Engine) !c.VkCommandBuffer {
        const alloc_info = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = self.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };

        var cmd: c.VkCommandBuffer = null;
        var result = c.vkAllocateCommandBuffers(self.device, &alloc_info, &cmd);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to allocate upload command buffer: {d}", .{result});
            return error.CommandFailed;
        }
        errdefer c.vkFreeCommandBuffers(self.device, self.command_pool, 1, &cmd);

        const begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        };
        result = c.vkBeginCommandBuffer(cmd, &begin_info);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to begin upload command buffer: {d}", .{result});
            return error.CommandFailed;
        }

        return cmd;
    }

    fn endSingleUse(self: *Engine, cmd: c.VkCommandBuffer) !void {
        var cb = cmd;

        var result = c.vkEndCommandBuffer(cb);
        if (result != c.VK_SUCCESS) {
            c.vkFreeCommandBuffers(self.device, self.command_pool, 1, &cb);
            logger.fail("Failed to end upload command buffer: {d}", .{result});
            return error.CommandFailed;
        }

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreCount = 0,
            .pWaitSemaphores = null,
            .pWaitDstStageMask = null,
            .commandBufferCount = 1,
            .pCommandBuffers = &cb,
            .signalSemaphoreCount = 0,
            .pSignalSemaphores = null,
        };
        result = c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, null);
        if (result != c.VK_SUCCESS) {
            c.vkFreeCommandBuffers(self.device, self.command_pool, 1, &cb);
            logger.fail("Failed to submit upload: {d}", .{result});
            return error.CommandFailed;
        }

        result = c.vkQueueWaitIdle(self.graphics_queue);
        c.vkFreeCommandBuffers(self.device, self.command_pool, 1, &cb);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to wait for upload: {d}", .{result});
            return error.CommandFailed;
        }
    }

    fn createTestResources(self: *Engine) !void {
        const host_visible_coherent =
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;

        const ibuf = try self.createBuffer(
            @sizeOf(InstanceData),
            c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            host_visible_coherent,
        );
        self.instance_buffer = ibuf.handle;
        self.instance_memory = ibuf.memory;

        var mapped: ?*anyopaque = null;
        var result = c.vkMapMemory(
            self.device,
            self.instance_memory,
            0,
            @sizeOf(InstanceData),
            0,
            &mapped,
        );
        if (result != c.VK_SUCCESS or mapped == null) {
            logger.fail("Failed to map instance buffer: {d}", .{result});
            return error.BufferFailed;
        }
        self.instance_mapped =
            @as([*]u8, @ptrCast(mapped.?))[0..@sizeOf(InstanceData)];
        self.writeTestInstance();

        const pixels = [_]u8{ 255, 255, 255, 255 };
        const staging = try self.createBuffer(
            pixels.len,
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            host_visible_coherent,
        );
        defer c.vkDestroyBuffer(self.device, staging.handle, null);
        defer c.vkFreeMemory(self.device, staging.memory, null);

        var smapped: ?*anyopaque = null;
        result = c.vkMapMemory(self.device, staging.memory, 0, pixels.len, 0, &smapped);
        if (result != c.VK_SUCCESS or smapped == null) {
            logger.fail("Failed to map staging buffer: {d}", .{result});
            return error.BufferFailed;
        }
        @memcpy(@as([*]u8, @ptrCast(smapped.?))[0..pixels.len], &pixels);
        c.vkUnmapMemory(self.device, staging.memory);

        const img_info = c.VkImageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .imageType = c.VK_IMAGE_TYPE_2D,
            .format = c.VK_FORMAT_R8G8B8A8_UNORM,
            .extent = .{ .width = 1, .height = 1, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .tiling = c.VK_IMAGE_TILING_OPTIMAL,
            .usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        };

        var img: c.VkImage = null;
        result = c.vkCreateImage(self.device, &img_info, null, &img);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create test image: {d}", .{result});
            return error.ImageFailed;
        }
        errdefer c.vkDestroyImage(self.device, img, null);

        var img_req: c.VkMemoryRequirements = undefined;
        c.vkGetImageMemoryRequirements(self.device, img, &img_req);

        const img_mem_index = try self.findMemoryType(
            img_req.memoryTypeBits,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        );
        const img_alloc = c.VkMemoryAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = img_req.size,
            .memoryTypeIndex = img_mem_index,
        };

        var img_mem: c.VkDeviceMemory = null;
        result = c.vkAllocateMemory(self.device, &img_alloc, null, &img_mem);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to allocate image memory: {d}", .{result});
            return error.ImageFailed;
        }
        errdefer c.vkFreeMemory(self.device, img_mem, null);

        result = c.vkBindImageMemory(self.device, img, img_mem, 0);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to bind image memory: {d}", .{result});
            return error.ImageFailed;
        }

        const cmd = try self.beginSingleUse();

        var barrier = c.VkImageMemoryBarrier{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .pNext = null,
            .srcAccessMask = 0,
            .dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
            .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = img,
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        c.vkCmdPipelineBarrier(
            cmd,
            c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            c.VK_PIPELINE_STAGE_TRANSFER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &barrier,
        );

        const region = c.VkBufferImageCopy{
            .bufferOffset = 0,
            .bufferRowLength = 0,
            .bufferImageHeight = 0,
            .imageSubresource = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
            .imageExtent = .{ .width = 1, .height = 1, .depth = 1 },
        };
        c.vkCmdCopyBufferToImage(
            cmd,
            staging.handle,
            img,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &region,
        );

        barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;
        barrier.oldLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        c.vkCmdPipelineBarrier(
            cmd,
            c.VK_PIPELINE_STAGE_TRANSFER_BIT,
            c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &barrier,
        );

        try self.endSingleUse(cmd);

        self.test_image = img;
        self.test_image_memory = img_mem;

        const view_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = img,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = c.VK_FORMAT_R8G8B8A8_UNORM,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        var view: c.VkImageView = null;
        result = c.vkCreateImageView(self.device, &view_info, null, &view);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create test image view: {d}", .{result});
            return error.ImageFailed;
        }
        self.test_image_view = view;

        const sampler_info = c.VkSamplerCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .magFilter = c.VK_FILTER_NEAREST,
            .minFilter = c.VK_FILTER_NEAREST,
            .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_NEAREST,
            .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .mipLodBias = 0,
            .anisotropyEnable = c.VK_FALSE,
            .maxAnisotropy = 1,
            .compareEnable = c.VK_FALSE,
            .compareOp = c.VK_COMPARE_OP_ALWAYS,
            .minLod = 0,
            .maxLod = 0,
            .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
            .unnormalizedCoordinates = c.VK_FALSE,
        };
        var sampler: c.VkSampler = null;
        result = c.vkCreateSampler(self.device, &sampler_info, null, &sampler);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create test sampler: {d}", .{result});
            return error.ImageFailed;
        }
        self.test_sampler = sampler;

        const pool_size = c.VkDescriptorPoolSize{
            .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 4096,
        };
        const pool_info = c.VkDescriptorPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT,
            .maxSets = 1,
            .poolSizeCount = 1,
            .pPoolSizes = &pool_size,
        };
        var pool: c.VkDescriptorPool = null;
        result = c.vkCreateDescriptorPool(self.device, &pool_info, null, &pool);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to create descriptor pool: {d}", .{result});
            return error.DescriptorFailed;
        }
        errdefer c.vkDestroyDescriptorPool(self.device, pool, null);
        self.descriptor_pool = pool;

        const set_alloc = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = null,
            .descriptorPool = pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &self.descriptor_set_layout,
        };
        var set: c.VkDescriptorSet = null;
        result = c.vkAllocateDescriptorSets(self.device, &set_alloc, &set);
        if (result != c.VK_SUCCESS) {
            logger.fail("Failed to allocate descriptor set: {d}", .{result});
            return error.DescriptorFailed;
        }
        self.descriptor_set = set;

        const img_desc = c.VkDescriptorImageInfo{
            .sampler = sampler,
            .imageView = view,
            .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        };
        const write = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstSet = set,
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &img_desc,
            .pBufferInfo = null,
            .pTexelBufferView = null,
        };
        c.vkUpdateDescriptorSets(self.device, 1, &write, 0, null);
    }
};
