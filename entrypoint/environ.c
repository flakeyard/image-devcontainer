/*
 * environ: moves the environment of a process into its arguments, and back
 * (ADR-0001). The image starts the entrypoint through it, so that the
 * processes of root start without the variables of the container: the
 * dynamic loader of glibc reads LD_PRELOAD, LD_LIBRARY_PATH, LD_AUDIT,
 * GCONV_PATH and others before the first line of any program. This program is
 * static, so no loader runs before it.
 *
 *   environ to-args PROGRAM [ARG...]
 *     runs PROGRAM, an absolute path, with an empty environment and the
 *     arguments COUNT, the COUNT variables of the environment, then ARG...
 *   environ from-args COUNT [VARIABLE...] COMMAND [ARG...]
 *     runs COMMAND, found in the PATH of the variables, with the COUNT
 *     variables as its environment.
 *
 * Until the command runs, the variables are in the arguments, which every
 * process of the container may read in /proc; by then only root and dev run.
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

/* The exit status when a program cannot run, as of a shell, and on misuse. */
enum { cannot_run = 127, misuse = 2 };

static const char usage[] =
    "usage: environ to-args PROGRAM [ARG...]\n"
    "       environ from-args COUNT [VARIABLE...] COMMAND [ARG...]\n";

/* count: the number of entries before the NULL that ends LIST. */
static size_t count(char *const *list)
{
    size_t length = 0;
    while (list[length] != NULL)
        length++;
    return length;
}

/* failed: reports why PROGRAM did not run. */
static int failed(const char *program)
{
    fprintf(stderr, "environ: %s: %s\n", program, strerror(errno));
    return cannot_run;
}

/* to_args: runs ARGS[0] with the environment in front of ARGS[1...]. */
static int to_args(char **args)
{
    size_t variables = count(environ), rest = count(args) - 1;
    /* The digits of any size_t, fewer than 3 per byte, and the NUL. */
    char number[3 * sizeof(size_t) + 1];
    char *empty[] = {NULL};
    /* The program, the number, the variables, the rest and NULL. */
    char **next = calloc(variables + rest + 3, sizeof *next);

    if (next == NULL)
        return failed(args[0]);
    snprintf(number, sizeof number, "%zu", variables);
    next[0] = args[0];
    next[1] = number;
    memcpy(next + 2, environ, variables * sizeof *next);
    memcpy(next + 2 + variables, args + 1, rest * sizeof *next);
    execve(args[0], next, empty);
    return failed(args[0]);
}

/* decimal: TEXT as a number, or -1 unless it is only decimal digits. */
static long long decimal(const char *text)
{
    char *end;
    long long number;

    if (text[0] < '0' || text[0] > '9')
        return -1;
    errno = 0;
    number = strtoll(text, &end, 10);
    return (*end != '\0' || errno != 0) ? -1 : number;
}

/* from_args: runs the command after the ARGS[0] variables of ARGS[1...]
 * with these variables as its environment. */
static int from_args(char **args)
{
    long long variables = decimal(args[0]);
    char **command;

    /* At least the variables and the command follow the number. */
    if (variables < 0 || (size_t)variables >= count(args) - 1) {
        fputs(usage, stderr);
        return misuse;
    }
    command = args + 1 + variables;
    environ = calloc((size_t)variables + 1, sizeof *environ);
    if (environ == NULL)
        return failed(command[0]);
    memcpy(environ, args + 1, (size_t)variables * sizeof *environ);
    execvp(command[0], command);
    return failed(command[0]);
}

int main(int argc, char **argv)
{
    /* The mode and at least a program or a number with a command. */
    if (argc >= 3 && strcmp(argv[1], "to-args") == 0)
        return to_args(argv + 2);
    if (argc >= 4 && strcmp(argv[1], "from-args") == 0)
        return from_args(argv + 2);
    fputs(usage, stderr);
    return misuse;
}
