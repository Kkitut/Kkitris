#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <unistd.h>
#include <limits.h>
#include <threads.h>
#include <sys/stat.h>

#include "helper.h"

const char *LOGS_FOLDER_NAME  = "logs";
const char *LOG_FILE_NAME     = "latest.log";
const char *LOG_FILE_NAME_OLD = "latest.log.old";

typedef enum {
    LOG_INFO,
    LOG_WARN,
    LOG_FAIL
} LogLevel;

typedef struct LogEntry {
    LogLevel level;
    char *message;
    struct LogEntry *next;
} LogEntry;

static mtx_t log_mutex;
static cnd_t log_condition;

static LogEntry *log_queue_head;
static LogEntry *log_queue_tail;

static FILE *log_file;
static thrd_t log_thread;
static bool log_running;

static int log_thread_func(void *arg) {
    (void)arg;

    while (true) {
        mtx_lock(&log_mutex);

        while (log_queue_head == NULL && log_running) {
            cnd_wait(&log_condition, &log_mutex);
        }

        if (!log_running && log_queue_head == NULL) {
            mtx_unlock(&log_mutex);
            break;
        }

        LogEntry *entry = log_queue_head;
        log_queue_head = entry->next;

        if (log_queue_head == NULL) {
            log_queue_tail = NULL;
        }

        mtx_unlock(&log_mutex);

        const char *prefix;
        const char *plain_prefix;

        switch (entry->level) {
            case LOG_INFO:
                prefix = "\033[34m[I]\033[0m";
                plain_prefix = "[I]";
                break;

            case LOG_WARN:
                prefix = "\033[33m[W]\033[0m";
                plain_prefix = "[W]";
                break;

            case LOG_FAIL:
                prefix = "\033[31m[F]\033[0m";
                plain_prefix = "[F]";
                break;

            default:
                prefix = "[?]";
                plain_prefix = "[?]";
                break;
        }

        printf("%s %s\n", prefix, entry->message);

        fprintf(log_file, "%s %s\n", plain_prefix, entry->message);
        fflush(log_file);

        free(entry->message);
        free(entry);
    }

    return 0;
}

static void log_enqueue(LogLevel level, const char *format, va_list args) {
    char *message = NULL;

    if (vasprintf(&message, format, args) == -1) {
        return;
    }

    LogEntry *entry = malloc(sizeof(LogEntry));

    if (entry == NULL) {
        free(message);
        return;
    }

    entry->level = level;
    entry->message = message;
    entry->next = NULL;

    mtx_lock(&log_mutex);

    if (log_queue_tail != NULL) {
        log_queue_tail->next = entry;
    } else {
        log_queue_head = entry;
    }

    log_queue_tail = entry;

    cnd_signal(&log_condition);
    mtx_unlock(&log_mutex);
}

bool logger_init(void) {
    if (mtx_init(&log_mutex, mtx_plain) != thrd_success) {
        printlnf("[F] Failed to initialize log mutex");
        return false;
    }

    if (cnd_init(&log_condition) != thrd_success) {
        printlnf("[F] Failed to initialize log condition");
        mtx_destroy(&log_mutex);
        return false;
    }

    char path[PATH_MAX];

    if (!Ktr_get_executable_directory(path, sizeof(path))) {
        cnd_destroy(&log_condition);
        mtx_destroy(&log_mutex);
        return false;
    }

    struct stat st;
    char log_folder_path[PATH_MAX];
    char log_file_path[PATH_MAX];
    char log_file_old_path[PATH_MAX];

    if (!Ktr_make_path(log_folder_path, sizeof(log_folder_path), path, LOGS_FOLDER_NAME)) {
        printlnf("[F] Log folder path is too long");
        cnd_destroy(&log_condition);
        mtx_destroy(&log_mutex);
        return false;
    }

    if (!Ktr_make_path(log_file_path, sizeof(log_file_path), log_folder_path, LOG_FILE_NAME)) {
        printlnf("[F] Log file path is too long");
        cnd_destroy(&log_condition);
        mtx_destroy(&log_mutex);
        return false;
    }

    if (!Ktr_make_path(log_file_old_path, sizeof(log_file_old_path), log_folder_path, LOG_FILE_NAME_OLD)) {
        printlnf("[F] Old log file path is too long");
        cnd_destroy(&log_condition);
        mtx_destroy(&log_mutex);
        return false;
    }

    if (stat(log_folder_path, &st) != 0) {
        printlnf("[I] \"logs\" folder does not exist, creating...");

        if (mkdir(log_folder_path, S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) != 0) {
            printlnf("[F] Failed to create logs folder: %s", strerror(errno));
            cnd_destroy(&log_condition);
            mtx_destroy(&log_mutex);
            return false;
        }
    } else if (!S_ISDIR(st.st_mode)) {
        printlnf("[F] \"logs\" exists but is not a directory");
        cnd_destroy(&log_condition);
        mtx_destroy(&log_mutex);
        return false;
    }

    if (access(log_file_path, F_OK) == 0) {
        if (rename(log_file_path, log_file_old_path) != 0) {
            printlnf("[W] Failed to rename log file: %s", strerror(errno));
        }
    }

    log_file = fopen(log_file_path, "w");

    if (log_file == NULL) {
        printlnf("[F] Failed to create log file: %s", strerror(errno));
        cnd_destroy(&log_condition);
        mtx_destroy(&log_mutex);
        return false;
    }

    log_running = true;

    if (thrd_create(&log_thread, log_thread_func, NULL) != thrd_success) {
        printlnf("[F] Failed to create log thread");

        fclose(log_file);
        log_file = NULL;

        cnd_destroy(&log_condition);
        mtx_destroy(&log_mutex);

        return false;
    }

    return true;
}

void logger_drop(void) {
    mtx_lock(&log_mutex);

    log_running = false;
    cnd_signal(&log_condition);

    mtx_unlock(&log_mutex);

    thrd_join(log_thread, NULL);

    fclose(log_file);
    log_file = NULL;

    cnd_destroy(&log_condition);
    mtx_destroy(&log_mutex);
}

void log_i(const char *format, ...) {
    va_list args;
    va_start(args, format);

    log_enqueue(LOG_INFO, format, args);

    va_end(args);
}

void log_w(const char *format, ...) {
    va_list args;
    va_start(args, format);

    log_enqueue(LOG_WARN, format, args);

    va_end(args);
}

void log_f(const char *format, ...) {
    va_list args;
    va_start(args, format);

    log_enqueue(LOG_FAIL, format, args);

    va_end(args);
}