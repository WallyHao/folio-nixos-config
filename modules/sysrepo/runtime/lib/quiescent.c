#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <limits.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

/* The pinned sysrepo holds a whole-file POSIX write lock for each connection.
 * Query kernel locks rather than trusting persisted PIDs or opening a damaged
 * repository. Compatible clients also hold the outer repository shared lock. */
int main(int argc, char **argv)
{
    if (argc < 2) return 2;
    for (int argument = 1; argument < argc; ++argument) {
        char pattern[PATH_MAX];
        if (snprintf(pattern, sizeof(pattern), "%s/conn/conn_*.lock", argv[argument]) >= (int)sizeof(pattern)) return 2;
        glob_t paths = {0};
        int code = glob(pattern, 0, NULL, &paths);
        if (code != 0 && code != GLOB_NOMATCH) { globfree(&paths); return 1; }
        for (size_t index = 0; index < paths.gl_pathc; ++index) {
            int fd = open(paths.gl_pathv[index], O_WRONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
            if (fd < 0 && errno == ENOENT) continue;
            struct stat info;
            struct flock lock = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
            if (fd < 0 || fstat(fd, &info) || !S_ISREG(info.st_mode) || fcntl(fd, F_GETLK, &lock)) {
                if (fd >= 0) close(fd);
                globfree(&paths); return 1;
            }
            close(fd);
            if (lock.l_type != F_UNLCK) {
                fprintf(stderr, "Repository connection is still held by process %ld\n", (long)lock.l_pid);
                globfree(&paths); return 4;
            }
        }
        globfree(&paths);
    }
    return 0;
}
