// Prototypes for the parts of the system libarchive (/usr/lib/libarchive.2.dylib) we use.
// The macOS SDK ships the library but not its headers.
#include <sys/types.h>
#include <stddef.h>

struct archive;
struct archive_entry;

#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_WARN (-20)
#define AE_IFREG 0100000
#define AE_IFDIR 0040000

struct archive *archive_read_new(void);
int archive_read_support_format_all(struct archive *);
int archive_read_support_filter_all(struct archive *);
int archive_read_set_options(struct archive *, const char *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_data_skip(struct archive *);
int archive_read_free(struct archive *);
const char *archive_error_string(struct archive *);

const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
unsigned int archive_entry_filetype(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
