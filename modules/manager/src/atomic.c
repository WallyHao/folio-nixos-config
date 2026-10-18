#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* Same-directory replacement, then flush both file contents and directory entry.
 * The caller owns the destination directory and serializes protocol mutations. */
int main(int argc, char **argv)
{
    char temporary[PATH_MAX], parent[PATH_MAX], buffer[16384];
    int fd = -1, directory = -1, result = 1;
    size_t total = 0;
    ssize_t count;
    if (argc != 2 || argv[1][0] != '/' || strlen(argv[1]) >= sizeof(parent)) {
        fprintf(stderr, "Usage: folio-atomic-write ABSOLUTE_DESTINATION\n");
        return 2;
    }
    strcpy(parent, argv[1]);
    char *slash = strrchr(parent, '/');
    if (slash == parent || !slash[1]) {
        fprintf(stderr, "Destination needs an owned parent directory\n");
        return 2;
    }
    *slash = '\0';
    directory = open(parent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat info;
    if (directory < 0 || fstat(directory, &info) || info.st_uid != geteuid() || (info.st_mode & 0022)) {
        fprintf(stderr, "Unsafe destination directory: %s\n", parent);
        goto cleanup;
    }
    if (snprintf(temporary, sizeof(temporary), "%s/.atomic-XXXXXX", parent) >= (int)sizeof(temporary)) {
        goto cleanup;
    }
    fd = mkstemp(temporary);
    if (fd < 0) {
        goto cleanup;
    }
    while ((count = read(STDIN_FILENO, buffer, sizeof(buffer))) != 0) {
        if (count < 0) {
            if (errno == EINTR) continue;
            goto cleanup;
        }
        total += (size_t)count;
        if (total > 16 * 1024 * 1024) {
            fprintf(stderr, "Record exceeds 16 MiB\n");
            goto cleanup;
        }
        ssize_t offset = 0;
        while (offset < count) {
            ssize_t written = write(fd, buffer + offset, (size_t)(count - offset));
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) goto cleanup;
            offset += written;
        }
    }
    if (fsync(fd) || rename(temporary, argv[1]) || fsync(directory)) {
        goto cleanup;
    }
    result = 0;
cleanup:
    if (result) perror("Durable record write failed");
    if (fd >= 0) {
        close(fd);
        if (result) unlink(temporary);
    }
    if (directory >= 0) close(directory);
    return result;
}
