#include <stdio.h>
#include <GLFW/glfw3.h>

#include "logger.h"

int main(void) {
    if (!logger_init()) {
        return 0;
    }

    if (!glfwInit()) {
        const char *description;
        glfwGetError(&description);

        log_f("Failed to initialize GLFW: %s", description);
        return false;
    }

    log_i("OK");


    
    log_i("Bye");
    logger_drop();

    return 0;
}