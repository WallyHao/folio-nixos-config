#include <glob.h>
#include <libyang/libyang.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* libyang is the authority for types, defaults, constraints and RFC 7951 values.
 * Object-key and known system-list ordering is handled by the packaged jq step. */
int main(int argc, char **argv)
{
    struct ly_ctx *ctx = NULL;
    struct lyd_node *tree = NULL;
    glob_t paths = {0};
    char *pattern = NULL;
    int result = 2;

    if (argc != 3) {
        fprintf(stderr, "Usage: folio-normalize-data MODEL_DIRECTORY CONFIGURATION.json\n");
        return 2;
    }
    if (asprintf(&pattern, "%s/*.yang", argv[1]) < 0) {
        return 1;
    }
    if (ly_ctx_new(argv[1], LY_CTX_DISABLE_SEARCHDIR_CWD, &ctx) != LY_SUCCESS ||
            glob(pattern, 0, NULL, &paths) != 0) {
        fprintf(stderr, "Unable to load model directory\n");
        goto cleanup;
    }
    for (size_t i = 0; i < paths.gl_pathc; ++i) {
        char *name = strdup(strrchr(paths.gl_pathv[i], '/') + 1);
        if (!name) {
            result = 1;
            goto cleanup;
        }
        char *end = strchr(name, '@');
        if (!end) {
            end = strstr(name, ".yang");
        }
        *end = '\0';
        const struct lys_module *module = ly_ctx_load_module(ctx, name, NULL, NULL);
        free(name);
        if (!module) {
            goto cleanup;
        }
    }
    if (lyd_parse_data_path(ctx, argv[2], LYD_JSON, LYD_PARSE_STRICT | LYD_PARSE_NO_STATE,
            LYD_VALIDATE_NO_STATE, &tree) != LY_SUCCESS) {
        goto cleanup;
    }
    if (!tree) {
        fprintf(stderr, "Configuration is empty\n");
        goto cleanup;
    }
    if (lyd_print_file(stdout, tree, LYD_JSON,
            LYD_PRINT_WITHSIBLINGS | LYD_PRINT_SHRINK | LYD_PRINT_WD_ALL) != LY_SUCCESS ||
            fputc('\n', stdout) == EOF || fflush(stdout) == EOF) {
        result = 1;
        goto cleanup;
    }
    result = 0;

cleanup:
    lyd_free_all(tree);
    ly_ctx_destroy(ctx);
    globfree(&paths);
    free(pattern);
    return result;
}
