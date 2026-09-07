#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <vulkan/vulkan.h>
#include <GLFW/glfw3.h>

#include "logger.h"
#include "engine.h"
#include "helper.h"

static bool read_spv(
    const char *path,
    uint32_t **code,
    size_t *code_size
) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return false;
    }

    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return false;
    }

    long size = ftell(file);
    if (size < 0 || size % sizeof(uint32_t) != 0) {
        fclose(file);
        return false;
    }

    rewind(file);

    uint32_t *data = malloc((size_t)size);
    if (data == NULL) {
        fclose(file);
        return false;
    }

    if (fread(data, 1, (size_t)size, file) != (size_t)size) {
        free(data);
        fclose(file);
        return false;
    }

    fclose(file);

    *code = data;
    *code_size = (size_t)size;

    return true;
}

static bool create_shader_modules(
    Engine *engine,
    VkShaderModule *vert_module,
    VkShaderModule *frag_module
) {
    char executable_directory[PATH_MAX];
    char vert_path[PATH_MAX];
    char frag_path[PATH_MAX];

    if (!Ktr_get_executable_directory(
        executable_directory,
        sizeof(executable_directory)
    )) {
        return false;
    }

    if (!Ktr_make_path(
        vert_path,
        sizeof(vert_path),
        executable_directory,
        "shader/object.vert.spv"
    )) {
        log_f("Vertex shader path is too long");
        return false;
    }

    if (!Ktr_make_path(
        frag_path,
        sizeof(frag_path),
        executable_directory,
        "shader/object.frag.spv"
    )) {
        log_f("Fragment shader path is too long");
        return false;
    }

    uint32_t *vert_code = NULL;
    uint32_t *frag_code = NULL;

    size_t vert_size;
    size_t frag_size;

    if (!read_spv(vert_path, &vert_code, &vert_size)) {
        log_f("Failed to load object.vert.spv");
        return false;
    }

    if (!read_spv(frag_path, &frag_code, &frag_size)) {
        free(vert_code);
        log_f("Failed to load object.frag.spv");
        return false;
    }

    VkShaderModuleCreateInfo vert_info = {
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = vert_size,
        .pCode = vert_code,
    };

    VkShaderModuleCreateInfo frag_info = {
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = frag_size,
        .pCode = frag_code,
    };

    VkResult result = vkCreateShaderModule(
        engine->device,
        &vert_info,
        NULL,
        vert_module
    );

    if (result != VK_SUCCESS) {
        free(vert_code);
        free(frag_code);

        log_f("Failed to create vertex shader module: %d", result);
        return false;
    }

    result = vkCreateShaderModule(
        engine->device,
        &frag_info,
        NULL,
        frag_module
    );

    if (result != VK_SUCCESS) {
        vkDestroyShaderModule(
            engine->device,
            *vert_module,
            NULL
        );

        free(vert_code);
        free(frag_code);

        log_f("Failed to create fragment shader module: %d", result);
        return false;
    }

    free(vert_code);
    free(frag_code);

    return true;
}

static bool create_instance(Engine *engine) {
    uint32_t glfw_extension_count = 0;

    const char **glfw_extensions =
        glfwGetRequiredInstanceExtensions(&glfw_extension_count);

    if (glfw_extensions == NULL) {
        log_f("Failed to get required Vulkan extensions from GLFW");
        return false;
    }

    VkApplicationInfo app_info = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Kkitris",
        .applicationVersion = VK_MAKE_API_VERSION(0, 1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = VK_MAKE_API_VERSION(0, 1, 0, 0),
        .apiVersion = VK_API_VERSION_1_3,
    };

    VkInstanceCreateInfo create_info = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = glfw_extension_count,
        .ppEnabledExtensionNames = glfw_extensions,
    };

    VkResult result = vkCreateInstance(
        &create_info,
        NULL,
        &engine->instance
    );

    if (result != VK_SUCCESS) {
        log_f("Failed to create Vulkan instance: %d", result);
        return false;
    }

    return true;
}

static bool create_surface(Engine *engine) {
    VkResult result = glfwCreateWindowSurface(
        engine->instance,
        engine->window,
        NULL,
        &engine->surface
    );

    if (result != VK_SUCCESS) {
        log_f("Failed to create Vulkan surface: %d", result);
        return false;
    }

    return true;
}

static uint32_t find_queue_family(
    Engine *engine,
    VkPhysicalDevice device
) {
    uint32_t count = 0;

    vkGetPhysicalDeviceQueueFamilyProperties(
        device,
        &count,
        NULL
    );

    VkQueueFamilyProperties *families =
        malloc(sizeof(*families) * count);

    if (families == NULL) {
        return UINT32_MAX;
    }

    vkGetPhysicalDeviceQueueFamilyProperties(
        device,
        &count,
        families
    );

    for (uint32_t i = 0; i < count; i++) {
        bool graphics =
            (families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0;

        VkBool32 present = VK_FALSE;

        VkResult result =
            vkGetPhysicalDeviceSurfaceSupportKHR(
                device,
                i,
                engine->surface,
                &present
            );

        if (result != VK_SUCCESS) {
            continue;
        }

        if (graphics && present) {
            free(families);
            return i;
        }
    }

    free(families);

    return UINT32_MAX;
}

static bool pick_physical_device(Engine *engine) {
    uint32_t device_count = 0;

    VkResult result = vkEnumeratePhysicalDevices(
        engine->instance,
        &device_count,
        NULL
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to enumerate physical devices: %d",
            result
        );
        return false;
    }

    if (device_count == 0) {
        log_f("No Vulkan physical devices found");
        return false;
    }

    VkPhysicalDevice *devices =
        malloc(sizeof(*devices) * device_count);

    if (devices == NULL) {
        log_f("Failed to allocate physical device list");
        return false;
    }

    result = vkEnumeratePhysicalDevices(
        engine->instance,
        &device_count,
        devices
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to enumerate physical devices: %d",
            result
        );

        free(devices);
        return false;
    }

    for (uint32_t i = 0; i < device_count; i++) {
        VkPhysicalDeviceProperties properties;

        vkGetPhysicalDeviceProperties(
            devices[i],
            &properties
        );

        log_i(
            "Vulkan GPU %u: %s",
            i,
            properties.deviceName
        );

        uint32_t queue_family_index =
            find_queue_family(engine, devices[i]);

        if (queue_family_index == UINT32_MAX) {
            continue;
        }

        engine->physical_device = devices[i];
        engine->queue_family_index = queue_family_index;

        log_i(
            "Selected Vulkan GPU %u: %s",
            i,
            properties.deviceName
        );

        free(devices);
        return true;
    }

    free(devices);

    log_f(
        "No suitable GPU found with Graphics and Surface support"
    );

    return false;
}

static bool create_logical_device(Engine *engine) {
    float queue_priority = 1.0f;

    VkDeviceQueueCreateInfo queue_create_info = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = engine->queue_family_index,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };

    const char *device_extensions[] = {
        VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    };

    VkPhysicalDeviceVulkan12Features vulkan12_features = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .runtimeDescriptorArray = VK_TRUE,
        .shaderSampledImageArrayNonUniformIndexing = VK_TRUE,
        .descriptorBindingSampledImageUpdateAfterBind = VK_TRUE,
        .descriptorBindingPartiallyBound = VK_TRUE,
    };

    VkDeviceCreateInfo create_info = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &vulkan12_features,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queue_create_info,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = device_extensions,
    };

    VkResult result = vkCreateDevice(
        engine->physical_device,
        &create_info,
        NULL,
        &engine->device
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to create logical device: %d",
            result
        );

        return false;
    }

    vkGetDeviceQueue(
        engine->device,
        engine->queue_family_index,
        0,
        &engine->graphics_queue
    );

    engine->present_queue = engine->graphics_queue;

    return true;
}

static bool create_graphics_pipeline(
    Engine *engine
) {
    VkShaderModule vert_module;
    VkShaderModule frag_module;

    if (!create_shader_modules(
        engine,
        &vert_module,
        &frag_module
    )) {
        return false;
    }

    const char *main_function_name = "main";

    VkPipelineShaderStageCreateInfo vert_stage_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_module,
        .pName = main_function_name,
    };

    VkPipelineShaderStageCreateInfo frag_stage_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_module,
        .pName = main_function_name,
    };

    VkPipelineShaderStageCreateInfo shader_stages[] = {
        vert_stage_info,
        frag_stage_info,
    };

    VkPipelineLayoutCreateInfo pipeline_layout_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    };

    VkResult result = vkCreatePipelineLayout(
        engine->device,
        &pipeline_layout_info,
        NULL,
        &engine->pipeline_layout
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to create pipeline layout: %d",
            result
        );

        vkDestroyShaderModule(
            engine->device,
            vert_module,
            NULL
        );

        vkDestroyShaderModule(
            engine->device,
            frag_module,
            NULL
        );

        return false;
    }

    VkPipelineVertexInputStateCreateInfo vertex_input_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };

    VkPipelineInputAssemblyStateCreateInfo input_assembly_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = VK_FALSE,
    };

    VkViewport viewport = {
        .x = 0.0f,
        .y = 0.0f,
        .width = (float)engine->swapchain_extent.width,
        .height = (float)engine->swapchain_extent.height,
        .minDepth = 0.0f,
        .maxDepth = 1.0f,
    };

    VkRect2D scissor = {
        .offset = {0, 0},
        .extent = engine->swapchain_extent,
    };

    VkPipelineViewportStateCreateInfo viewport_state_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    VkPipelineRasterizationStateCreateInfo rasterization_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = VK_FALSE,
        .rasterizerDiscardEnable = VK_FALSE,
        .polygonMode = VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0f,
        .cullMode = VK_CULL_MODE_NONE,
        .frontFace = VK_FRONT_FACE_CLOCKWISE,
    };

    VkPipelineMultisampleStateCreateInfo multisample_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
    };

    VkPipelineColorBlendAttachmentState color_blend_attachment = {
        .colorWriteMask =
            VK_COLOR_COMPONENT_R_BIT |
            VK_COLOR_COMPONENT_G_BIT |
            VK_COLOR_COMPONENT_B_BIT |
            VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = VK_TRUE,
        .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = VK_BLEND_OP_ADD,
    };

    VkPipelineColorBlendStateCreateInfo color_blend_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = VK_FALSE,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
    };

    VkGraphicsPipelineCreateInfo pipeline_info = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly_info,
        .pViewportState = &viewport_state_info,
        .pRasterizationState = &rasterization_info,
        .pMultisampleState = &multisample_info,
        .pColorBlendState = &color_blend_info,
        .layout = engine->pipeline_layout,
        .renderPass = engine->render_pass,
        .subpass = 0,
    };

    result = vkCreateGraphicsPipelines(
        engine->device,
        VK_NULL_HANDLE,
        1,
        &pipeline_info,
        NULL,
        &engine->graphics_pipeline
    );

    vkDestroyShaderModule(
        engine->device,
        vert_module,
        NULL
    );

    vkDestroyShaderModule(
        engine->device,
        frag_module,
        NULL
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to create graphics pipeline: %d",
            result
        );

        vkDestroyPipelineLayout(
            engine->device,
            engine->pipeline_layout,
            NULL
        );

        engine->pipeline_layout = VK_NULL_HANDLE;

        return false;
    }

    return true;
}

static bool create_swapchain_resources(
    Engine *engine,
    uint32_t width,
    uint32_t height
) {
    VkSurfaceCapabilitiesKHR capabilities;

    VkResult result =
        vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            engine->physical_device,
            engine->surface,
            &capabilities
        );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to get surface capabilities: %d",
            result
        );
        return false;
    }

    VkExtent2D extent;

    if (capabilities.currentExtent.width != UINT32_MAX) {
        extent = capabilities.currentExtent;
    } else {
        extent.width = width;

        if (extent.width < capabilities.minImageExtent.width) {
            extent.width = capabilities.minImageExtent.width;
        }

        if (extent.width > capabilities.maxImageExtent.width) {
            extent.width = capabilities.maxImageExtent.width;
        }

        extent.height = height;

        if (extent.height < capabilities.minImageExtent.height) {
            extent.height = capabilities.minImageExtent.height;
        }

        if (extent.height > capabilities.maxImageExtent.height) {
            extent.height = capabilities.maxImageExtent.height;
        }
    }

    engine->swapchain_extent = extent;

    uint32_t image_count =
        capabilities.minImageCount + 1;

    if (
        capabilities.maxImageCount > 0 &&
        image_count > capabilities.maxImageCount
    ) {
        image_count = capabilities.maxImageCount;
    }

    VkSwapchainCreateInfoKHR create_info = {
        .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = engine->surface,
        .minImageCount = image_count,
        .imageFormat = engine->swapchain_image_format,
        .imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = VK_PRESENT_MODE_FIFO_KHR,
        .clipped = VK_TRUE,
        .oldSwapchain = engine->swapchain,
    };

    result = vkCreateSwapchainKHR(
        engine->device,
        &create_info,
        NULL,
        &engine->swapchain
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to create swapchain: %d",
            result
        );
        return false;
    }

    result = vkGetSwapchainImagesKHR(
        engine->device,
        engine->swapchain,
        &engine->swapchain_image_count,
        NULL
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to get swapchain image count: %d",
            result
        );
        return false;
    }

    engine->swapchain_images =
        malloc(
            sizeof(*engine->swapchain_images) *
            engine->swapchain_image_count
        );

    if (engine->swapchain_images == NULL) {
        log_f("Failed to allocate swapchain images");
        return false;
    }

    result = vkGetSwapchainImagesKHR(
        engine->device,
        engine->swapchain,
        &engine->swapchain_image_count,
        engine->swapchain_images
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to get swapchain images: %d",
            result
        );

        free(engine->swapchain_images);
        engine->swapchain_images = NULL;

        return false;
    }

    engine->swapchain_image_views =
        calloc(
            engine->swapchain_image_count,
            sizeof(*engine->swapchain_image_views)
        );

    if (engine->swapchain_image_views == NULL) {
        log_f("Failed to allocate swapchain image views");
        return false;
    }

    for (uint32_t i = 0; i < engine->swapchain_image_count; i++) {
        VkImageViewCreateInfo view_info = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = engine->swapchain_images[i],
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = engine->swapchain_image_format,
            .components = {
                .r = VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = {
                .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        result = vkCreateImageView(
            engine->device,
            &view_info,
            NULL,
            &engine->swapchain_image_views[i]
        );

        if (result != VK_SUCCESS) {
            log_f(
                "Failed to create swapchain image view %u: %d",
                i,
                result
            );
            return false;
        }
    }

    engine->swapchain_framebuffers =
        calloc(
            engine->swapchain_image_count,
            sizeof(*engine->swapchain_framebuffers)
        );

    if (engine->swapchain_framebuffers == NULL) {
        log_f("Failed to allocate swapchain framebuffers");
        return false;
    }

    for (uint32_t i = 0; i < engine->swapchain_image_count; i++) {
        VkImageView attachments[] = {
            engine->swapchain_image_views[i],
        };

        VkFramebufferCreateInfo framebuffer_info = {
            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = engine->render_pass,
            .attachmentCount = 1,
            .pAttachments = attachments,
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        };

        result = vkCreateFramebuffer(
            engine->device,
            &framebuffer_info,
            NULL,
            &engine->swapchain_framebuffers[i]
        );

        if (result != VK_SUCCESS) {
            log_f(
                "Failed to create framebuffer %u: %d",
                i,
                result
            );
            return false;
        }
    }

    if (!create_graphics_pipeline(engine)) {
        return false;
    }

    return true;
}

static bool recreate_swapchain(
    Engine *engine,
    uint32_t width,
    uint32_t height
) {
    if (width == 0 || height == 0) {
        return true;
    }

    VkResult result =
        vkDeviceWaitIdle(engine->device);

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to wait for device idle: %d",
            result
        );
        return false;
    }

    for (uint32_t i = 0; i < engine->swapchain_image_count; i++) {
        if (engine->swapchain_framebuffers != NULL) {
            vkDestroyFramebuffer(
                engine->device,
                engine->swapchain_framebuffers[i],
                NULL
            );
        }

        if (engine->swapchain_image_views != NULL) {
            vkDestroyImageView(
                engine->device,
                engine->swapchain_image_views[i],
                NULL
            );
        }
    }

    free(engine->swapchain_framebuffers);
    engine->swapchain_framebuffers = NULL;

    free(engine->swapchain_image_views);
    engine->swapchain_image_views = NULL;

    free(engine->swapchain_images);
    engine->swapchain_images = NULL;

    engine->swapchain_image_count = 0;

    if (engine->swapchain != VK_NULL_HANDLE) {
        vkDestroySwapchainKHR(
            engine->device,
            engine->swapchain,
            NULL
        );

        engine->swapchain = VK_NULL_HANDLE;
    }

    return create_swapchain_resources(
        engine,
        width,
        height
    );
}

static bool choose_surface_format(Engine *engine) {
    uint32_t count = 0;

    VkResult result =
        vkGetPhysicalDeviceSurfaceFormatsKHR(
            engine->physical_device,
            engine->surface,
            &count,
            NULL
        );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to get surface format count: %d",
            result
        );
        return false;
    }

    if (count == 0) {
        log_f("No Vulkan surface formats available");
        return false;
    }

    VkSurfaceFormatKHR *formats =
        malloc(sizeof(*formats) * count);

    if (formats == NULL) {
        log_f("Failed to allocate surface format list");
        return false;
    }

    result = vkGetPhysicalDeviceSurfaceFormatsKHR(
        engine->physical_device,
        engine->surface,
        &count,
        formats
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to get surface formats: %d",
            result
        );

        free(formats);
        return false;
    }

    VkSurfaceFormatKHR chosen = formats[0];

    for (uint32_t i = 0; i < count; i++) {
        if (formats[i].format == VK_FORMAT_R8G8B8A8_UNORM) {
            chosen = formats[i];
            break;
        }
    }

    engine->swapchain_image_format = chosen.format;
    engine->swapchain_image_color_space = chosen.colorSpace;

    free(formats);

    return true;
}

static bool create_render_pass(Engine *engine) {
    VkAttachmentDescription color_attachment = {
        .format = engine->swapchain_image_format,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    VkAttachmentReference color_attachment_ref = {
        .attachment = 0,
        .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    VkSubpassDescription subpass = {
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
    };

    VkSubpassDependency dependency = {
        .srcSubpass = VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    VkRenderPassCreateInfo create_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };

    VkResult result = vkCreateRenderPass(
        engine->device,
        &create_info,
        NULL,
        &engine->render_pass
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to create render pass: %d",
            result
        );
        return false;
    }

    return true;
}

static bool create_command_buffers(
    Engine *engine
) {
    engine->command_buffers = malloc(
        sizeof(*engine->command_buffers) *
        engine->swapchain_image_count
    );

    if (engine->command_buffers == NULL) {
        log_f("Failed to allocate command buffer list");
        return false;
    }

    VkCommandBufferAllocateInfo alloc_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = engine->command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = engine->swapchain_image_count,
    };

    VkResult result = vkAllocateCommandBuffers(
        engine->device,
        &alloc_info,
        engine->command_buffers
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to allocate command buffers: %d",
            result
        );

        free(engine->command_buffers);
        engine->command_buffers = NULL;

        return false;
    }

    return true;
}

static bool create_command_pool_and_fences(
    Engine *engine
) {
    VkCommandPoolCreateInfo pool_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = engine->queue_family_index,
    };

    VkResult result = vkCreateCommandPool(
        engine->device,
        &pool_info,
        NULL,
        &engine->command_pool
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to create command pool: %d",
            result
        );
        return false;
    }

    VkFenceCreateInfo fence_info = {
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = VK_FENCE_CREATE_SIGNALED_BIT,
    };

    for (uint32_t i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
        result = vkCreateFence(
            engine->device,
            &fence_info,
            NULL,
            &engine->in_flight_fences[i]
        );

        if (result != VK_SUCCESS) {
            log_f(
                "Failed to create fence %u: %d",
                i,
                result
            );
            return false;
        }
    }

    return true;
}

static bool create_frame_semaphores(
    Engine *engine
) {
    VkSemaphoreCreateInfo semaphore_info = {
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    for (uint32_t i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
        VkResult result = vkCreateSemaphore(
            engine->device,
            &semaphore_info,
            NULL,
            &engine->image_available_semaphores[i]
        );

        if (result != VK_SUCCESS) {
            log_f(
                "Failed to create image available semaphore %u: %d",
                i,
                result
            );
            return false;
        }

        result = vkCreateSemaphore(
            engine->device,
            &semaphore_info,
            NULL,
            &engine->render_finished_semaphores[i]
        );

        if (result != VK_SUCCESS) {
            log_f(
                "Failed to create render finished semaphore %u: %d",
                i,
                result
            );
            return false;
        }
    }

    return true;
}

static bool create_descriptor_layout(Engine *engine) {
    VkDescriptorBindingFlags binding_flags =
        VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT |
        VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT;

    VkDescriptorSetLayoutBindingFlagsCreateInfo binding_flags_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        .bindingCount = 1,
        .pBindingFlags = &binding_flags,
    };

    VkDescriptorSetLayoutBinding binding = {
        .binding = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 4096,
        .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    VkDescriptorSetLayoutCreateInfo layout_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = &binding_flags_info,
        .flags = VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT,
        .bindingCount = 1,
        .pBindings = &binding,
    };

    VkResult result = vkCreateDescriptorSetLayout(
        engine->device,
        &layout_info,
        NULL,
        &engine->descriptor_set_layout
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to create descriptor set layout: %d",
            result
        );
        return false;
    }

    return true;
}

bool engine_init(
    Engine *engine,
    GLFWwindow *window
) {
    memset(engine, 0, sizeof(*engine));

    engine->window = window;

    if (!create_instance(engine)) {
        return false;
    }

    if (!create_surface(engine)) {
        return false;
    }

    if (!pick_physical_device(engine)) {
        return false;
    }

    if (!create_logical_device(engine)) {
        return false;
    }

    if (!choose_surface_format(engine)) {
        return false;
    }

    if (!create_render_pass(engine)) {
        return false;
    }

    if (!create_descriptor_layout(engine)) {
        return false;
    }

    int width;
    int height;

    glfwGetFramebufferSize(
        window,
        &width,
        &height
    );

    if (!create_swapchain_resources(
        engine,
        (uint32_t)width,
        (uint32_t)height
    )) {
        return false;
    }

    if (!create_command_pool_and_fences(engine)) {
        return false;
    }

    if (!create_frame_semaphores(engine)) {
        return false;
    }

    if (!create_command_buffers(engine)) {
        return false;
    }

    return true;
}

void engine_update(Engine *engine, float dt) {

}

void engine_render(Engine *engine) {
    uint32_t frame = engine->current_frame;

    VkResult result = vkWaitForFences(
        engine->device,
        1,
        &engine->in_flight_fences[frame],
        VK_TRUE,
        UINT64_MAX
    );

    if (result != VK_SUCCESS) {
        log_f("Failed to wait for fence: %d", result);
        return;
    }

    uint32_t image_index;

    result = vkAcquireNextImageKHR(
        engine->device,
        engine->swapchain,
        UINT64_MAX,
        engine->image_available_semaphores[frame],
        VK_NULL_HANDLE,
        &image_index
    );

    if (
        result == VK_ERROR_OUT_OF_DATE_KHR ||
        result == VK_ERROR_SURFACE_LOST_KHR
    ) {
        return;
    }

    if (
        result != VK_SUCCESS &&
        result != VK_SUBOPTIMAL_KHR
    ) {
        log_f(
            "Failed to acquire next image: %d",
            result
        );
        return;
    }

    if (image_index >= engine->swapchain_image_count) {
        log_f(
            "Invalid swapchain image index: %u",
            image_index
        );
        return;
    }

    result = vkResetFences(
        engine->device,
        1,
        &engine->in_flight_fences[frame]
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to reset fence: %d",
            result
        );
        return;
    }

    VkCommandBuffer command_buffer =
        engine->command_buffers[image_index];

    result = vkResetCommandBuffer(
        command_buffer,
        0
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to reset command buffer: %d",
            result
        );
        return;
    }

    VkCommandBufferBeginInfo begin_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };

    result = vkBeginCommandBuffer(
        command_buffer,
        &begin_info
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to begin command buffer: %d",
            result
        );
        return;
    }

    int width;
    int height;

    glfwGetFramebufferSize(
        engine->window,
        &width,
        &height
    );

    VkClearValue clear_value = {
        .color = {
            .float32 = {
                0.0f,
                0.0f,
                0.0f,
                1.0f,
            },
        },
    };

    VkRenderPassBeginInfo render_pass_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,

        .renderPass = engine->render_pass,

        .framebuffer =
            engine->swapchain_framebuffers[image_index],

        .renderArea = {
            .offset = {
                .x = 0,
                .y = 0,
            },

            .extent = engine->swapchain_extent,
        },

        .clearValueCount = 1,
        .pClearValues = &clear_value,
    };

    vkCmdBeginRenderPass(
        command_buffer,
        &render_pass_info,
        VK_SUBPASS_CONTENTS_INLINE
    );

    vkCmdBindPipeline(
        command_buffer,
        VK_PIPELINE_BIND_POINT_GRAPHICS,
        engine->graphics_pipeline
    );

    // render

    // end

    vkCmdEndRenderPass(
        command_buffer
    );

    result = vkEndCommandBuffer(
        command_buffer
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to end command buffer: %d",
            result
        );
    
        return;
    }

    VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSemaphore wait_semaphore = engine->image_available_semaphores[frame];
    VkSemaphore signal_semaphore = engine->render_finished_semaphores[frame];
    VkSubmitInfo submit_info = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &wait_semaphore,
        .pWaitDstStageMask = &wait_stage,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &signal_semaphore,
    };

    result = vkQueueSubmit(
        engine->graphics_queue,
        1,
        &submit_info,
        engine->in_flight_fences[frame]
    );

    if (result != VK_SUCCESS) {
        log_f(
            "Failed to submit queue: %d",
            result
        );
        return;
    }

    VkSwapchainKHR swapchain = engine->swapchain;
    VkPresentInfoKHR present_info = {
        .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &signal_semaphore,
        .swapchainCount = 1,
        .pSwapchains = &swapchain,
        .pImageIndices = &image_index,
    };

    result = vkQueuePresentKHR(
        engine->present_queue,
        &present_info
    );

    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) {
        engine->framebuffer_resized = true;
    } else if (result == VK_ERROR_SURFACE_LOST_KHR) {
        return;
    } else if (result != VK_SUCCESS) {
        log_f(
            "Failed to present swapchain: %d",
            result
        );

        return;
    }

    engine->current_frame = (engine->current_frame + 1) % MAX_FRAMES_IN_FLIGHT;
}

void engine_drop(
    Engine *engine
) {
    if (engine == NULL) {
        return;
    }

    if (engine->device != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(engine->device);

        free(engine->command_buffers);
        engine->command_buffers = NULL;

        for (uint32_t i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
            if (engine->image_available_semaphores[i] != VK_NULL_HANDLE) {
                vkDestroySemaphore(
                    engine->device,
                    engine->image_available_semaphores[i],
                    NULL
                );
            }

            if (engine->render_finished_semaphores[i] != VK_NULL_HANDLE) {
                vkDestroySemaphore(
                    engine->device,
                    engine->render_finished_semaphores[i],
                    NULL
                );
            }

            if (engine->in_flight_fences[i] != VK_NULL_HANDLE) {
                vkDestroyFence(
                    engine->device,
                    engine->in_flight_fences[i],
                    NULL
                );
            }
        }

        if (engine->swapchain_framebuffers != NULL) {
            for (uint32_t i = 0; i < engine->swapchain_image_count; i++) {
                if (engine->swapchain_framebuffers[i] != VK_NULL_HANDLE) {
                    vkDestroyFramebuffer(
                        engine->device,
                        engine->swapchain_framebuffers[i],
                        NULL
                    );
                }
            }

            free(engine->swapchain_framebuffers);
            engine->swapchain_framebuffers = NULL;
        }

        if (engine->swapchain_image_views != NULL) {
            for (uint32_t i = 0; i < engine->swapchain_image_count; i++) {
                if (engine->swapchain_image_views[i] != VK_NULL_HANDLE) {
                    vkDestroyImageView(
                        engine->device,
                        engine->swapchain_image_views[i],
                        NULL
                    );
                }
            }

            free(engine->swapchain_image_views);
            engine->swapchain_image_views = NULL;
        }

        free(engine->swapchain_images);
        engine->swapchain_images = NULL;

        if (engine->swapchain != VK_NULL_HANDLE) {
            vkDestroySwapchainKHR(
                engine->device,
                engine->swapchain,
                NULL
            );

            engine->swapchain = VK_NULL_HANDLE;
        }

        if (engine->graphics_pipeline != VK_NULL_HANDLE) {
            vkDestroyPipeline(
                engine->device,
                engine->graphics_pipeline,
                NULL
            );

            engine->graphics_pipeline = VK_NULL_HANDLE;
        }

        if (engine->pipeline_layout != VK_NULL_HANDLE) {
            vkDestroyPipelineLayout(
                engine->device,
                engine->pipeline_layout,
                NULL
            );

            engine->pipeline_layout = VK_NULL_HANDLE;
        }

        if (engine->render_pass != VK_NULL_HANDLE) {
            vkDestroyRenderPass(
                engine->device,
                engine->render_pass,
                NULL
            );

            engine->render_pass = VK_NULL_HANDLE;
        }

        if (engine->descriptor_set_layout != VK_NULL_HANDLE) {
            vkDestroyDescriptorSetLayout(
                engine->device,
                engine->descriptor_set_layout,
                NULL
            );

            engine->descriptor_set_layout = VK_NULL_HANDLE;
        }

        if (engine->command_pool != VK_NULL_HANDLE) {
            vkDestroyCommandPool(
                engine->device,
                engine->command_pool,
                NULL
            );

            engine->command_pool = VK_NULL_HANDLE;
        }

        vkDestroyDevice(
            engine->device,
            NULL
        );

        engine->device = VK_NULL_HANDLE;
    }

    if (engine->surface != VK_NULL_HANDLE && engine->instance != VK_NULL_HANDLE) {

        vkDestroySurfaceKHR(
            engine->instance,
            engine->surface,
            NULL
        );

        engine->surface = VK_NULL_HANDLE;
    }

    if (engine->instance != VK_NULL_HANDLE) {
        vkDestroyInstance(
            engine->instance,
            NULL
        );

        engine->instance = VK_NULL_HANDLE;
    }

    engine->window = NULL;
}