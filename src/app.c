#include <GLFW/glfw3.h>

#include "app.h"
#include "engine.h"
#include "logger.h"

const char *KKITRIS = "Kkitris";

static void key_callback(
    GLFWwindow *window,
    int key,
    int scancode,
    int action,
    int mods
) {
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
        glfwSetWindowShouldClose(window, true);
    }
}

int app_run(void) {
    log_i("Starting...");

    if (!glfwInit()) {
        const char *desc;
        glfwGetError(&desc);

        log_f("Failed to initialize GLFW: %s", desc);

        return 1;
    }

    if (!glfwVulkanSupported()) {
        log_f("GLFW reports Vulkan is not supported");

        glfwTerminate();
        return 1;
    }

    log_i(
        "GLFW platform: %d",
        glfwGetPlatform()
    );

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);

    GLFWwindow *window = glfwCreateWindow(
        1600,
        900,
        KKITRIS,
        NULL,
        NULL
    );

    if (window == NULL) {
        const char *desc;
        glfwGetError(&desc);

        log_f("Failed to create GLFW window: %s", desc);

        glfwTerminate();

        return 1;
    }

    glfwSetKeyCallback(
        window,
        key_callback
    );

    Engine engine;

    if (!engine_init(&engine, window)) {
        engine_drop(&engine);

        glfwDestroyWindow(window);
        glfwTerminate();

        return 1;
    }

    log_i("Ready");

    double last_frame_time = glfwGetTime();

    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();

        double frame_time = glfwGetTime();
        float dt = (float)(frame_time - last_frame_time);

        last_frame_time = frame_time;

        engine_update(&engine, dt);
        engine_render(&engine);
    }

    engine_drop(&engine);

    glfwDestroyWindow(window);
    glfwTerminate();

    log_i("Bye");

    return 0;
}