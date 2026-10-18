#define _GNU_SOURCE
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <jansson.h>
#include <limits.h>
#include <openssl/evp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define LIMIT (8U * 1024U * 1024U)
static void hash(const unsigned char *data, size_t length, char output[65])
{
    unsigned char bytes[32]; unsigned int count = 0;
    if (!EVP_Digest(data, length, bytes, &count, EVP_sha256(), NULL) || count != 32) exit(1);
    for (unsigned i = 0; i < count; ++i) snprintf(output + i * 2, 3, "%02x", bytes[i]);
}
static int read_file(int fd, unsigned char **data, size_t *length)
{
    struct stat info;
    if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_size < 0 || info.st_size > LIMIT) return -1;
    *length = (size_t)info.st_size;
    *data = malloc(*length + 1);
    if (!*data) return -1;
    size_t offset = 0;
    while (offset < *length) {
        ssize_t count = read(fd, *data + offset, *length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { free(*data); *data = NULL; return -1; }
        offset += (size_t)count;
    }
    (*data)[*length] = 0;
    return 0;
}
static int write_file(int fd, const unsigned char *data, size_t length)
{
    size_t offset = 0;
    while (offset < length) {
        ssize_t count = write(fd, data + offset, length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return -1;
        offset += (size_t)count;
    }
    return fsync(fd);
}
static int result(int code, int exists, const char *digest, const char *backup, int changed)
{
    json_t *value = json_pack("{s:s,s:b,s:s,s:b}", "status", code ? "conflict" : "success",
        "exists", exists, "digest", digest ?: "absent", "changed", changed);
    if (backup) json_object_set_new(value, "backup", json_string(backup));
    if (code) json_object_set_new(value, "error", json_string("Managed file precondition failed; retain the task and conflicting data"));
    json_dumpf(value, stdout, JSON_COMPACT | JSON_SORT_KEYS); putchar('\n'); json_decref(value);
    return code;
}
static int relative_valid(const char *relative)
{
    const char *prefix = ".var/app/app.zen_browser.zen/.zen/";
    if (strncmp(relative, prefix, strlen(prefix))) return 0;
    const char *profile = relative + strlen(prefix), *slash = strchr(profile, '/');
    if (!slash || slash == profile || slash - profile > 128 || !isalnum((unsigned char)*profile)) return 0;
    for (const char *p = profile; p < slash; ++p)
        if (!isalnum((unsigned char)*p) && !strchr("._ -", *p)) return 0;
    const char *suffix = slash + 1;
    return !strcmp(suffix, "user.js") || !strcmp(suffix, "chrome/folio/ui.css") ||
        !strcmp(suffix, "chrome/folio/content.css") || !strcmp(suffix, "chrome/userChrome.css") ||
        !strcmp(suffix, "chrome/userContent.css");
}
int main(int argc, char **argv)
{
    int publish = argc == 10 && !strcmp(argv[1], "publish");
    if ((!publish && (argc != 4 || strcmp(argv[1], "inspect"))) || !geteuid() ||
        argv[2][0] != '/' || !relative_valid(argv[3])) return 2;
    int directory = open(argv[2], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directory < 0) return result(4, 0, NULL, NULL, 0);
    char *path = strdup(argv[3]), *save = NULL, *component = strtok_r(path, "/", &save);
    unsigned depth = 0;
    while (component) {
        char *next = strtok_r(NULL, "/", &save);
        if (!next) break;
        int child = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (child < 0 && errno == ENOENT && publish && depth >= 5) {
            if (mkdirat(directory, component, 0700) || fsync(directory)) { close(directory); free(path); return result(4, 0, NULL, NULL, 0); }
            child = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        }
        if (child < 0) {
            int missing = errno == ENOENT;
            close(directory); free(path);
            return result(missing && !publish ? 0 : 4, 0, NULL, NULL, 0);
        }
        struct stat info;
        if (fstat(child, &info) || info.st_uid != geteuid() || (info.st_mode & 0022)) {
            close(child); close(directory); free(path); return result(4, 0, NULL, NULL, 0);
        }
        close(directory); directory = child; component = next; ++depth;
    }
    unsigned char *old = NULL, *source = NULL, *combined = NULL;
    size_t old_length = 0, source_length = 0, combined_length = 0;
    char old_hash[65] = "absent", source_hash[65], new_hash[65];
    int exists = 0, code = 4, changed = 0;
    struct stat before_info = {0};
    char backup[NAME_MAX + 1] = "";
    int fd = openat(directory, component, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (fd >= 0) {
        struct stat info;
        if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_uid != geteuid() || info.st_nlink != 1 ||
                read_file(fd, &old, &old_length)) { close(fd); goto done; }
        close(fd); exists = 1; hash(old, old_length, old_hash);
        before_info = info;
    } else if (errno != ENOENT) goto done;
    if (!publish) { code = 0; goto done; }
    if (strncmp(argv[4], "/nix/store/", 11)) goto done;
    fd = open(argv[4], O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) goto done;
    int error = read_file(fd, &source, &source_length); close(fd);
    if (error) goto done;
    hash(source, source_length, source_hash);
    if (strcmp(source_hash, argv[9])) goto done;
    if (!strcmp(argv[5], "replace")) {
        combined = source; combined_length = source_length;
    } else if (!strcmp(argv[5], "include")) {
        if (exists && old_length >= source_length && !memcmp(old, source, source_length)) {
            combined = old; combined_length = old_length;
        } else {
            combined_length = source_length + old_length;
            if (combined_length > LIMIT || !(combined = malloc(combined_length + 1))) goto done;
            memcpy(combined, source, source_length);
            if (old_length) memcpy(combined + source_length, old, old_length);
        }
    } else { code = 2; goto done; }
    hash(combined, combined_length, new_hash);
    if (strcmp(old_hash, argv[6])) {
        int recovered = exists && !strcmp(old_hash, new_hash) && !strcmp(argv[5], "replace");
        if (exists && !strcmp(argv[5], "include") && old_length >= source_length && !memcmp(old, source, source_length)) {
            char remainder[65]; hash(old + source_length, old_length - source_length, remainder);
            recovered = !strcmp(remainder, argv[6]) || (!strcmp(argv[6], "absent") && old_length == source_length);
        }
        if (recovered) { code = 0; goto done; }
        goto done;
    }
    if (exists && strcmp(argv[8], "owned") && strcmp(argv[8], "adopt")) goto done;
    if (exists && !strcmp(argv[8], "adopt")) {
        for (const char *p = argv[7]; *p; ++p) if (!isalnum((unsigned char)*p) && *p != '-') goto done;
        if (!argv[7][0] || strlen(argv[7]) > 64 ||
            snprintf(backup, sizeof(backup), "%s.folio-backup-%s", component, argv[7]) >= (int)sizeof(backup)) goto done;
        fd = openat(directory, backup, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (fd < 0) {
            if (errno != EEXIST) goto done;
            unsigned char *saved = NULL; size_t saved_length = 0; char saved_hash[65];
            fd = openat(directory, backup, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
            if (fd < 0) goto done;
            error = read_file(fd, &saved, &saved_length); close(fd);
            if (error) goto done;
            hash(saved, saved_length, saved_hash); free(saved);
            if (strcmp(saved_hash, old_hash)) goto done;
        } else {
            error = write_file(fd, old, old_length);
            if (close(fd) || error || fsync(directory)) goto done;
        }
    }
    if (exists && !strcmp(old_hash, new_hash)) { code = 0; goto done; }
    char temporary[96];
    snprintf(temporary, sizeof(temporary), ".folio-file-%ld", (long)getpid());
    fd = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) goto done;
    error = write_file(fd, combined, combined_length);
    if (close(fd) || error) { unlinkat(directory, temporary, 0); goto done; }
    struct stat current_info;
    int present = fstatat(directory, component, &current_info, AT_SYMLINK_NOFOLLOW) == 0;
    if ((exists && (!present || current_info.st_ino != before_info.st_ino || current_info.st_dev != before_info.st_dev ||
            current_info.st_size != before_info.st_size || current_info.st_mode != before_info.st_mode ||
            current_info.st_mtim.tv_sec != before_info.st_mtim.tv_sec || current_info.st_mtim.tv_nsec != before_info.st_mtim.tv_nsec)) ||
            (!exists && (present || errno != ENOENT))) {
        unlinkat(directory, temporary, 0); goto done;
    }
    if (renameat(directory, temporary, directory, component)) { unlinkat(directory, temporary, 0); goto done; }
    if (fsync(directory)) goto done;
    strcpy(old_hash, new_hash); exists = 1; changed = 1; code = 0;
done:
    close(directory); free(path);
    if (combined != old && combined != source) free(combined);
    free(old); free(source);
    return result(code, exists, old_hash, backup[0] ? backup : NULL, changed);
}
