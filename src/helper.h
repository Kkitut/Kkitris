#ifndef HELPER_H
#define HELPER_H

/**
 * Write formatted output to stdout.
 *
 * @param format Format string.
 * @param ... Arguments for the format string.
 */
void printlnf(const char *format, ...);

/**
 * Create a path by combining a base path and a name.
 *
 * @param buffer Buffer to store the resulting path.
 * @param buffer_size Size of the buffer.
 * @param base_path Base path.
 * @param name Name to append to the base path.
 *
 * @return true if the path was created successfully, false otherwise.
 */
bool Ktr_make_path(
    char *buffer,
    size_t buffer_size,
    const char *base_path,
    const char *name
);

/**
 * Get the directory containing the current executable.
 *
 * @param buffer Buffer to store the directory path.
 * @param size Size of the buffer.
 *
 * @return true if the directory was retrieved successfully, false otherwise.
 */
bool Ktr_get_executable_directory(char *buffer, size_t size);

#endif /* HELPER_H */