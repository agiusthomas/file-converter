#ifndef ARCHIVE_BRIDGE_H
#define ARCHIVE_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
typedef struct FCArchive FCArchive;
int fc_archive_available(void);
const char *fc_archive_version(void);
FCArchive *fc_archive_open(const char *path);
int fc_archive_next(FCArchive *reader);
const char *fc_archive_name(FCArchive *reader);
int64_t fc_archive_size(FCArchive *reader);
int fc_archive_kind(FCArchive *reader); /* 1 regular, 2 directory, 0 unsupported/link */
long fc_archive_read(FCArchive *reader, void *buffer, size_t length);
const char *fc_archive_error(FCArchive *reader);
void fc_archive_close(FCArchive *reader);
int fc_archive_create(const char *destination, const char *format, const char * const *paths, const char * const *names, size_t count, char *error, size_t error_length);
#endif
