/*
 * environ: hands the environment of a process to another through a file
 * descriptor (ADR-0001). The image starts the entrypoint through it, so that
 * the processes of root start without the variables of the container: the
 * dynamic loader of glibc reads LD_PRELOAD, LD_LIBRARY_PATH, LD_AUDIT,
 * GCONV_PATH and others before the first line of any program. This program is
 * static, so no loader runs before it.
 *
 *   environ to-fd PROGRAM [ARG...]
 *     runs PROGRAM, an absolute path, with an empty environment and the
 *     arguments FD ARG...: FD reads a memory file with the variables of the
 *     environment, each ended by a NUL.
 *   environ from-fd FD COMMAND [ARG...]
 *     runs COMMAND, a path or a name found in PATH, with the variables that
 *     FD reads from its start, and those of its own environment in place of
 *     the ones of the same name; closes FD.
 *
 * The variables never are in the arguments of a process, which every process
 * of the container may read in /proc; a file descriptor only its owner can
 * open there.
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

extern char **environ;

/* Exit statuses on misuse, and as of a shell, when a command is found but
 * cannot run, and when it is not found. */
enum { misuse = 2, cannot_run = 126, cannot_find = 127 };

/* The PATH without one, as execvp of glibc has it. */
static const char default_path[] = "/bin:/usr/bin";
/* The shell that runs an executable file without "#!", as execvp does. */
static const char shell[] = "/bin/sh";
/* The bytes read from the descriptor at a time. */
static const size_t chunk = 64 * 1024;

static const char usage[] =
    "usage: environ to-fd PROGRAM [ARG...]\n"
    "       environ from-fd FD COMMAND [ARG...]\n";

/* count: the number of entries before the NULL that ends LIST. */
static size_t count(char *const *list)
{
    size_t length = 0;
    while (list[length] != NULL)
        length++;
    return length;
}

/* complain: reports why WHAT failed. */
static void complain(const char *what)
{
    fprintf(stderr, "environ: %s: %s\n", what, strerror(errno));
}

/* failed: reports why WHAT failed; returns the status a shell would. */
static int failed(const char *what)
{
    int status = (errno == ENOENT || errno == ENOTDIR) ? cannot_find : cannot_run;
    complain(what);
    return status;
}

/* misused: reports why the argument WHAT is wrong; returns the status of
 * misuse. */
static int misused(const char *what)
{
    complain(what);
    return misuse;
}

/* write_all: writes SIZE bytes of DATA to FD; 0, or -1 on failure. */
static int write_all(int fd, const char *data, size_t size)
{
    while (size > 0) {
        ssize_t written = write(fd, data, size);
        if (written < 0 && errno != EINTR)
            return -1;
        if (written > 0) {
            data += written;
            size -= (size_t)written;
        }
    }
    return 0;
}

/* above_streams: FD, or a copy of it above the standard streams in its
 * place, since the engine may start the container with one of them closed and
 * the entrypoint refuses one; -1 when FD is -1 or on failure. */
static int above_streams(int fd)
{
    int moved, error;

    if (fd < 0 || fd > STDERR_FILENO)
        return fd;
    /* Without FD_CLOEXEC, as FD, so that it stays open in PROGRAM. */
    moved = fcntl(fd, F_DUPFD, STDERR_FILENO + 1);
    error = errno;
    close(fd);
    errno = error;
    return moved;
}

/* environment_file: a memory file with the variables of the environment,
 * each ended by a NUL, at its start, above the standard streams; -1 on
 * failure. */
static int environment_file(void)
{
    int fd = above_streams(memfd_create("environ", 0));
    if (fd < 0)
        return -1;
    for (char **entry = environ; *entry != NULL; entry++)
        if (write_all(fd, *entry, strlen(*entry) + 1) != 0)
            return -1;
    return lseek(fd, 0, SEEK_SET) == 0 ? fd : -1;
}

/* to_fd: runs ARGS[0] with an empty environment, and the descriptor of a
 * file with the environment in front of ARGS[1...]. */
static int to_fd(char **args)
{
    size_t rest = count(args) - 1;
    /* The digits of any int, fewer than 3 per byte, and the NUL. */
    char number[3 * sizeof(int) + 1];
    char *empty[] = {NULL};
    /* The program, the descriptor, the rest and NULL. */
    char **next = calloc(rest + 3, sizeof *next);
    int fd = environment_file();

    if (next == NULL || fd < 0)
        return failed(args[0]);
    snprintf(number, sizeof number, "%d", fd);
    next[0] = args[0];
    next[1] = number;
    memcpy(next + 2, args + 1, rest * sizeof *next);
    execve(args[0], next, empty);
    return failed(args[0]);
}

/* descriptor: TEXT as a file descriptor other than a standard stream, or -1
 * unless it is only decimal digits. */
static int descriptor(const char *text)
{
    char *end;
    long number;

    if (text[0] < '0' || text[0] > '9')
        return -1;
    errno = 0;
    number = strtol(text, &end, 10);
    if (*end != '\0' || errno != 0 || number <= STDERR_FILENO || number > INT_MAX)
        return -1;
    return (int)number;
}

/* read_all: what FD reads from its start, SIZE bytes followed by a NUL;
 * NULL on failure. */
static char *read_all(int fd, size_t *size)
{
    size_t length = 0;
    char *data = NULL, *grown;
    ssize_t got = 1;

    if (lseek(fd, 0, SEEK_SET) < 0 && errno != ESPIPE)
        return NULL;
    while (got != 0) {
        grown = realloc(data, length + chunk + 1);
        if (grown == NULL)
            break;
        data = grown;
        got = read(fd, data + length, chunk);
        if (got < 0 && errno != EINTR)
            break;
        if (got > 0)
            length += (size_t)got;
    }
    if (got != 0) {
        free(data);
        return NULL;
    }
    data[length] = '\0';
    *size = length;
    return data;
}

/* name_length: the length of the name of ENTRY, before its first '='. */
static size_t name_length(const char *entry)
{
    return strcspn(entry, "=");
}

/* overridden: the environment of this process has the variable of ENTRY. */
static int overridden(const char *entry)
{
    size_t length = name_length(entry);
    for (char **own = environ; *own != NULL; own++)
        if (name_length(*own) == length && strncmp(*own, entry, length) == 0)
            return 1;
    return 0;
}

/* merged: the entries of DATA, SIZE bytes each ended by a NUL, that the
 * environment of this process does not override, then that environment;
 * NULL on failure. */
static char **merged(char *data, size_t size)
{
    char *end = data + size, *entry, **next;
    size_t own = count(environ), entries = 0, used = 0;

    for (entry = data; entry < end; entry += strlen(entry) + 1)
        entries++;
    next = calloc(entries + own + 1, sizeof *next);
    if (next == NULL)
        return NULL;
    for (entry = data; entry < end; entry += strlen(entry) + 1)
        if (!overridden(entry))
            next[used++] = entry;
    memcpy(next + used, environ, own * sizeof *next);
    return next;
}

/* exec_file: runs FILE with ARGS, and an executable file without "#!"
 * through the shell, as execvp does; returns on failure with errno set. */
static void exec_file(const char *file, char **args)
{
    size_t rest = count(args) - 1;
    char **with_shell;

    execve(file, args, environ);
    if (errno != ENOEXEC)
        return;
    /* The shell, the file, the rest and NULL. */
    with_shell = calloc(rest + 3, sizeof *with_shell);
    if (with_shell == NULL)
        return;
    with_shell[0] = (char *)shell;
    with_shell[1] = (char *)file;
    memcpy(with_shell + 2, args + 1, rest * sizeof *with_shell);
    execve(shell, with_shell, environ);
    free(with_shell);
}

/* exec_in: runs COMMAND from the directory DIR of LENGTH bytes; an empty
 * one is the working directory. Returns on failure with errno set. */
static void exec_in(const char *dir, size_t length, char **command)
{
    char file[PATH_MAX];
    int written = length == 0
                      ? snprintf(file, sizeof file, "%s", command[0])
                      : snprintf(file, sizeof file, "%.*s/%s", (int)length, dir, command[0]);

    if (written < 0 || (size_t)written >= sizeof file) {
        errno = ENAMETOOLONG;
        return;
    }
    exec_file(file, command);
}

/* missing: errno says that a file of the search is not there. */
static int missing(void)
{
    return errno == ENOENT || errno == ENOTDIR || errno == ENAMETOOLONG;
}

/* run: runs COMMAND, a path or a name found in PATH. Returns on failure
 * with the status of a shell: not found, or found but not run. */
static int run(char **command)
{
    const char *dir = getenv("PATH");
    int found = 0;

    if (command[0][0] != '\0' && strchr(command[0], '/') != NULL) {
        exec_file(command[0], command);
        return failed(command[0]);
    }
    for (dir = dir != NULL ? dir : default_path; command[0][0] != '\0'; dir++) {
        size_t length = strcspn(dir, ":");
        exec_in(dir, length, command);
        if (!missing())
            found = errno;
        dir += length;
        if (*dir == '\0')
            break;
    }
    errno = found != 0 ? found : ENOENT;
    return failed(command[0]);
}

/* from_fd: runs the command of ARGS[1...] with the variables of the
 * descriptor ARGS[0] and those of this process. */
static int from_fd(char **args)
{
    int fd = descriptor(args[0]);
    size_t size;
    char *data, **next;

    if (fd < 0) {
        fputs(usage, stderr);
        return misuse;
    }
    data = read_all(fd, &size);
    /* A descriptor that is not open for reading is a wrong argument too. */
    if (data == NULL && errno == EBADF)
        return misused(args[0]);
    if (data == NULL)
        return failed(args[0]);
    close(fd);
    next = merged(data, size);
    if (next == NULL)
        return failed(args[1]);
    environ = next;
    return run(args + 1);
}

int main(int argc, char **argv)
{
    /* The mode and at least a program, or a descriptor and a command. */
    if (argc >= 3 && strcmp(argv[1], "to-fd") == 0)
        return to_fd(argv + 2);
    if (argc >= 4 && strcmp(argv[1], "from-fd") == 0)
        return from_fd(argv + 2);
    fputs(usage, stderr);
    return misuse;
}
