#include "ArchiveBridge.h"
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

/* Load the system's libarchive ABI without depending on private SDK headers.
   All parser calls remain in the conversion worker in the desktop build. */
static void *library;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static void load(void) { library = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW | RTLD_LOCAL); }
static void *sym(const char *name) { pthread_once(&once, load); return library ? dlsym(library, name) : NULL; }
#define FN(name, result, args) result (*name) args = (result (*) args)sym(#name)
struct FCArchive { void *reader; void *entry; };
int fc_archive_available(void) { return sym("archive_read_new") != NULL; }
const char *fc_archive_version(void) { FN(archive_version_string, const char *, (void)); return archive_version_string ? archive_version_string() : "unavailable"; }
FCArchive *fc_archive_open(const char *path) {
    FN(archive_read_new, void *, (void)); FN(archive_read_support_filter_all, int, (void *));
    FN(archive_read_support_format_all, int, (void *)); FN(archive_read_open_filename, int, (void *, const char *, size_t));
    if (!archive_read_new || !archive_read_support_filter_all || !archive_read_support_format_all || !archive_read_open_filename) return NULL;
    FCArchive *r = calloc(1, sizeof(*r)); if (!r) return NULL;
    r->reader = archive_read_new();
    if (!r->reader) { free(r); return NULL; }
    archive_read_support_filter_all(r->reader); archive_read_support_format_all(r->reader);
    if (archive_read_open_filename(r->reader, path, 65536) != 0) { fc_archive_close(r); return NULL; }
    return r;
}
int fc_archive_next(FCArchive *r) { FN(archive_read_next_header, int, (void *, void **)); return archive_read_next_header ? archive_read_next_header(r->reader, &r->entry) : -30; }
const char *fc_archive_name(FCArchive *r) { FN(archive_entry_pathname_utf8, const char *, (void *)); return archive_entry_pathname_utf8 ? archive_entry_pathname_utf8(r->entry) : NULL; }
int64_t fc_archive_size(FCArchive *r) { FN(archive_entry_size, int64_t, (void *)); return archive_entry_size ? archive_entry_size(r->entry) : -1; }
int fc_archive_kind(FCArchive *r) {
    FN(archive_entry_filetype, unsigned int, (void *)); FN(archive_entry_symlink, const char *, (void *)); FN(archive_entry_hardlink, const char *, (void *));
    if (!archive_entry_filetype || !archive_entry_symlink || !archive_entry_hardlink || archive_entry_symlink(r->entry) || archive_entry_hardlink(r->entry)) return 0;
    unsigned int type = archive_entry_filetype(r->entry);
    return type == S_IFREG ? 1 : type == S_IFDIR ? 2 : 0;
}
long fc_archive_read(FCArchive *r, void *buffer, size_t length) { FN(archive_read_data, long, (void *, void *, size_t)); return archive_read_data ? archive_read_data(r->reader, buffer, length) : -1; }
const char *fc_archive_error(FCArchive *r) { FN(archive_error_string, const char *, (void *)); return archive_error_string ? archive_error_string(r->reader) : "Archive failed"; }
void fc_archive_close(FCArchive *r) { if (!r) return; FN(archive_read_free, int, (void *)); if (r->reader && archive_read_free) archive_read_free(r->reader); free(r); }
int fc_archive_create(const char *destination, const char *format, const char * const *paths, const char * const *names, size_t count, char *error, size_t error_length) {
    FN(archive_write_new, void *, (void)); FN(archive_write_free, int, (void *));
    FN(archive_write_set_format_zip, int, (void *)); FN(archive_write_set_format_pax_restricted, int, (void *)); FN(archive_write_set_format_7zip, int, (void *));
    FN(archive_write_add_filter_gzip, int, (void *)); FN(archive_write_open_filename, int, (void *, const char *));
    FN(archive_write_header, int, (void *, void *)); FN(archive_write_data, long, (void *, const void *, size_t)); FN(archive_write_close, int, (void *));
    FN(archive_entry_new, void *, (void)); FN(archive_entry_free, void, (void *));
    FN(archive_entry_set_pathname_utf8, void, (void *, const char *)); FN(archive_entry_set_size, void, (void *, int64_t));
    FN(archive_entry_set_filetype, void, (void *, unsigned int)); FN(archive_entry_set_perm, void, (void *, unsigned int));
    FN(archive_error_string, const char *, (void *));
    if (!archive_write_new || !archive_write_free || !archive_write_set_format_zip || !archive_write_set_format_pax_restricted || !archive_write_open_filename || !archive_write_header || !archive_write_data || !archive_write_close || !archive_entry_new || !archive_entry_free || !archive_entry_set_pathname_utf8 || !archive_entry_set_size || !archive_entry_set_filetype || !archive_entry_set_perm || !archive_error_string) return -1;
    void *w = archive_write_new(); if (!w) return -1;
    int status = -1;
    if (!strcmp(format, "zip")) status = archive_write_set_format_zip(w);
    else if (!strcmp(format, "7z") && archive_write_set_format_7zip) status = archive_write_set_format_7zip(w);
    else if (!strcmp(format, "tar") || !strcmp(format, "tar.gz")) {
        status = archive_write_set_format_pax_restricted(w);
        if (status == 0 && !strcmp(format, "tar.gz")) status = archive_write_add_filter_gzip ? archive_write_add_filter_gzip(w) : -1;
    }
    if (status == 0) status = archive_write_open_filename(w, destination);
    for (size_t i = 0; status == 0 && i < count; i++) {
        struct stat st; if (lstat(paths[i], &st) || (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode))) { status = -1; break; }
        void *entry = archive_entry_new(); if (!entry) { status = -1; break; }
        archive_entry_set_pathname_utf8(entry, names[i]); archive_entry_set_size(entry, S_ISREG(st.st_mode) ? st.st_size : 0);
        archive_entry_set_filetype(entry, S_ISDIR(st.st_mode) ? S_IFDIR : S_IFREG); archive_entry_set_perm(entry, S_ISDIR(st.st_mode) ? 0755 : 0644);
        status = archive_write_header(w, entry); archive_entry_free(entry);
        if (status || !S_ISREG(st.st_mode)) continue;
        FILE *input = fopen(paths[i], "rb"); if (!input) { status = -1; break; }
        char buffer[65536]; size_t n;
        while ((n = fread(buffer, 1, sizeof(buffer), input))) { if (archive_write_data(w, buffer, n) != (long)n) { status = -1; break; } }
        if (ferror(input)) status = -1; fclose(input);
    }
    if (status == 0) status = archive_write_close(w);
    if (status && error && error_length) { const char *s = archive_error_string(w); snprintf(error, error_length, "%s", s ? s : "Archive creation failed"); }
    archive_write_free(w); return status;
}
