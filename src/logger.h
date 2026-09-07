#ifndef LOGGER_H
#define LOGGER_H

/**
 * Initialize the logger and start the logging thread.
 *
 * @return true on success, false on failure.
 */
bool logger_init(void);

/**
 * Stop the logger and release its resources.
 */
void logger_drop(void);

/**
 * Log an informational message.
 *
 * @param format Message format.
 */
void log_i(const char *format, ...);

/**
 * Log a warning message.
 *
 * @param format Message format.
 */
void log_w(const char *format, ...);

/**
 * Log a failure message.
 *
 * @param format Message format.
 */
void log_f(const char *format, ...);

#endif /* LOGGER_H */