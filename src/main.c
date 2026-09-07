#include "app.h"
#include "logger.h"

int main(void) {
    if (!logger_init()) {
        return 1;
    }

    int result = app_run();

    logger_drop();

    return result;
}