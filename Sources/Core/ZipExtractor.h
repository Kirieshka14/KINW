#ifndef KINW_ZIP_EXTRACTOR_H
#define KINW_ZIP_EXTRACTOR_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*kinw_zip_progress_cb)(const char* filename, float progress, void* user_data);

int kinw_zip_extract(const char* zip_path, const char* dest_dir, kinw_zip_progress_cb progress_cb, void* user_data);
int kinw_zip_read_file(const char* zip_path, const char* inner_filename, uint8_t** out_data, size_t* out_size);

#ifdef __cplusplus
}
#endif

#endif // KINW_ZIP_EXTRACTOR_H
