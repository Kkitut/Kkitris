#ifndef ENGINE_H
#define ENGINE_H

#include <stdbool.h>
#include <GLFW/glfw3.h>
#include <vulkan/vulkan.h>

#define MAX_FRAMES_IN_FLIGHT 2

typedef struct Engine {
    GLFWwindow *window;
    VkInstance instance;
    VkSurfaceKHR surface;
    VkPhysicalDevice physical_device;
    uint32_t queue_family_index;
    VkDevice device;
    VkQueue graphics_queue;
    VkQueue present_queue;
    VkSwapchainKHR swapchain;
    VkImage *swapchain_images;
    uint32_t swapchain_image_count;
    VkFormat swapchain_image_format;
    VkColorSpaceKHR swapchain_image_color_space;
    VkExtent2D swapchain_extent;
    VkImageView *swapchain_image_views;
    VkFramebuffer *swapchain_framebuffers;
    VkRenderPass render_pass;
    VkDescriptorSetLayout descriptor_set_layout;
    VkPipelineLayout pipeline_layout;
    VkPipeline graphics_pipeline;
    VkCommandPool command_pool;
    VkCommandBuffer *command_buffers;
    VkSemaphore image_available_semaphores[MAX_FRAMES_IN_FLIGHT];
    VkSemaphore render_finished_semaphores[MAX_FRAMES_IN_FLIGHT];
    VkFence in_flight_fences[MAX_FRAMES_IN_FLIGHT];
    uint32_t current_frame;
    bool framebuffer_resized;
} Engine;

/**
 * Initialize the engine.
 *
 * @param engine Engine instance.
 * @param window GLFW window.
 *
 * @return true on success, false on failure.
 */
bool engine_init(
    Engine *engine,
    GLFWwindow *window
);

/**
 * Update the engine state for the current frame.
 *
 * @param engine Engine instance.
 * @param dt Delta time in seconds.
 */
void engine_update(
    Engine *engine,
    float dt
);

/**
 * Render the current frame.
 *
 * @param engine Engine instance.
 */
void engine_render(Engine *engine);

/**
 * Shut down the engine and release its resources.
 *
 * @param engine Engine instance.
 */
void engine_drop(Engine *engine);

#endif /* ENGINE_H */