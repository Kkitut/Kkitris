#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

void printlnf(const char *format, ...) {
    va_list args;

    va_start(args, format);
    vprintf(format, args);
    va_end(args);

    putchar('\n');
}

bool Ktr_make_path(
    char *buffer,
    size_t buffer_size,
    const char *base_path,
    const char *name
) {
    int len = snprintf(buffer, buffer_size, "%s/%s", base_path, name);
    return len >= 0 && (size_t)len < buffer_size;
}

bool Ktr_get_executable_directory(char *buffer, size_t size) {
    ssize_t len = readlink("/proc/self/exe", buffer, size - 1);

    if (len == -1) {
        printlnf("[F] Failed to get current program path: %s", strerror(errno));
        return false;
    }

    buffer[len] = '\0';

    char *last_slash = strrchr(buffer, '/');

    if (last_slash != NULL) {
        *last_slash = '\0';
    }

    return true;
}