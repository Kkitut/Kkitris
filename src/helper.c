#include <stdarg.h>
#include <stdio.h>

void printlnf(const char *format, ...) {
    va_list args;

    va_start(args, format);
    vprintf(format, args);
    va_end(args);

    putchar('\n');
}