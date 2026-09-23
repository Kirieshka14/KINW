#include "ZipExtractor.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <zlib.h>

#pragma pack(push, 1)
struct ZipEOCD {
    uint32_t signature; // 0x06054b50
    uint16_t disk_number;
    uint16_t cd_start_disk;
    uint16_t total_entries_disk;
    uint16_t total_entries;
    uint32_t cd_size;
    uint32_t cd_offset;
    uint16_t comment_length;
};

struct ZipCDHeader {
    uint32_t signature; // 0x02014b50
    uint16_t version_made_by;
    uint16_t version_needed;
    uint16_t flags;
    uint16_t method;
    uint16_t mod_time;
    uint16_t mod_date;
    uint32_t crc32;
    uint32_t comp_size;
    uint32_t uncomp_size;
    uint16_t filename_len;
    uint16_t extra_len;
    uint16_t comment_len;
    uint16_t disk_start;
    uint16_t internal_attr;
    uint32_t external_attr;
    uint32_t local_header_offset;
};

struct ZipLocalHeader {
    uint32_t signature; // 0x04034b50
    uint16_t version_needed;
    uint16_t flags;
    uint16_t method;
    uint16_t mod_time;
    uint16_t mod_date;
    uint32_t crc32;
    uint32_t comp_size;
    uint32_t uncomp_size;
    uint16_t filename_len;
    uint16_t extra_len;
};
#pragma pack(pop)

static void make_dirs_for_path(const char* path) {
    char temp[1024];
    size_t len = strlen(path);
    if (len >= sizeof(temp)) return;
    memcpy(temp, path, len + 1);

    for (char* p = temp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(temp, 0755);
            *p = '/';
        }
    }
}

static int decompress_buffer(const uint8_t* in_buf, size_t in_size, uint8_t* out_buf, size_t out_size, uint16_t method) {
    if (method == 0) { // Stored
        size_t copy_sz = in_size < out_size ? in_size : out_size;
        memcpy(out_buf, in_buf, copy_sz);
        return 0;
    } else if (method == 8) { // Deflated
        z_stream strm;
        memset(&strm, 0, sizeof(strm));
        strm.next_in = (Bytef*)in_buf;
        strm.avail_in = (uInt)in_size;
        strm.next_out = (Bytef*)out_buf;
        strm.avail_out = (uInt)out_size;

        if (inflateInit2(&strm, -MAX_WBITS) != Z_OK) {
            return -1;
        }

        int ret = inflate(&strm, Z_FINISH);
        inflateEnd(&strm);
        return (ret == Z_STREAM_END || ret == Z_OK) ? 0 : -1;
    }
    return -2; // Unsupported method
}

int kinw_zip_extract(const char* zip_path, const char* dest_dir, kinw_zip_progress_cb progress_cb, void* user_data) {
    FILE* fp = fopen(zip_path, "rb");
    if (!fp) return -1;

    fseek(fp, 0, SEEK_END);
    long file_size = ftell(fp);
    if (file_size < (long)sizeof(struct ZipEOCD)) {
        fclose(fp);
        return -2;
    }

    // Find EOCD by scanning back from end
    long search_start = file_size - 1024;
    if (search_start < 0) search_start = 0;
    fseek(fp, search_start, SEEK_SET);

    size_t scan_size = file_size - search_start;
    uint8_t* scan_buf = (uint8_t*)malloc(scan_size);
    if (!scan_buf) {
        fclose(fp);
        return -3;
    }
    if (fread(scan_buf, 1, scan_size, fp) != scan_size) {
        free(scan_buf);
        fclose(fp);
        return -4;
    }

    struct ZipEOCD eocd;
    int found_eocd = 0;
    for (long i = (long)scan_size - 4; i >= 0; i--) {
        if (*(uint32_t*)(scan_buf + i) == 0x06054b50) {
            if (scan_size - i >= sizeof(struct ZipEOCD)) {
                memcpy(&eocd, scan_buf + i, sizeof(struct ZipEOCD));
                found_eocd = 1;
                break;
            }
        }
    }
    free(scan_buf);

    if (!found_eocd) {
        fclose(fp);
        return -5;
    }

    mkdir(dest_dir, 0755);

    fseek(fp, eocd.cd_offset, SEEK_SET);
    for (uint16_t entry = 0; entry < eocd.total_entries; entry++) {
        struct ZipCDHeader cd;
        if (fread(&cd, 1, sizeof(cd), fp) != sizeof(cd) || cd.signature != 0x02014b50) {
            break;
        }

        char filename[512];
        size_t fn_len = cd.filename_len < sizeof(filename) - 1 ? cd.filename_len : sizeof(filename) - 1;
        if (fread(filename, 1, fn_len, fp) != fn_len) break;
        filename[fn_len] = '\0';

        // Skip extra and comment
        fseek(fp, (long)cd.filename_len - fn_len + cd.extra_len + cd.comment_len, SEEK_CUR);

        if (progress_cb) {
            progress_cb(filename, (float)(entry + 1) / (float)eocd.total_entries, user_data);
        }

        long next_cd = ftell(fp);

        // Check if directory
        char dest_path[1024];
        snprintf(dest_path, sizeof(dest_path), "%s/%s", dest_dir, filename);

        if (filename[strlen(filename) - 1] == '/') {
            make_dirs_for_path(dest_path);
            mkdir(dest_path, 0755);
            fseek(fp, next_cd, SEEK_SET);
            continue;
        }

        make_dirs_for_path(dest_path);

        // Read local header
        fseek(fp, cd.local_header_offset, SEEK_SET);
        struct ZipLocalHeader lh;
        if (fread(&lh, 1, sizeof(lh), fp) == sizeof(lh) && lh.signature == 0x04034b50) {
            fseek(fp, lh.filename_len + lh.extra_len, SEEK_CUR);

            uint8_t* comp_data = (uint8_t*)malloc(cd.comp_size > 0 ? cd.comp_size : 1);
            uint8_t* uncomp_data = (uint8_t*)malloc(cd.uncomp_size > 0 ? cd.uncomp_size : 1);

            if (comp_data && uncomp_data) {
                if (cd.comp_size == 0 || fread(comp_data, 1, cd.comp_size, fp) == cd.comp_size) {
                    if (decompress_buffer(comp_data, cd.comp_size, uncomp_data, cd.uncomp_size, cd.method) == 0) {
                        FILE* out_fp = fopen(dest_path, "wb");
                        if (out_fp) {
                            if (cd.uncomp_size > 0) {
                                fwrite(uncomp_data, 1, cd.uncomp_size, out_fp);
                            }
                            fclose(out_fp);
                        }
                    }
                }
            }
            free(comp_data);
            free(uncomp_data);
        }

        fseek(fp, next_cd, SEEK_SET);
    }

    fclose(fp);
    return 0;
}

int kinw_zip_read_file(const char* zip_path, const char* inner_filename, uint8_t** out_data, size_t* out_size) {
    if (!out_data || !out_size) return -1;
    *out_data = NULL;
    *out_size = 0;

    FILE* fp = fopen(zip_path, "rb");
    if (!fp) return -1;

    fseek(fp, 0, SEEK_END);
    long file_size = ftell(fp);
    if (file_size < (long)sizeof(struct ZipEOCD)) {
        fclose(fp);
        return -2;
    }

    long search_start = file_size - 1024;
    if (search_start < 0) search_start = 0;
    fseek(fp, search_start, SEEK_SET);

    size_t scan_size = file_size - search_start;
    uint8_t* scan_buf = (uint8_t*)malloc(scan_size);
    if (!scan_buf) {
        fclose(fp);
        return -3;
    }
    if (fread(scan_buf, 1, scan_size, fp) != scan_size) {
        free(scan_buf);
        fclose(fp);
        return -4;
    }

    struct ZipEOCD eocd;
    int found_eocd = 0;
    for (long i = (long)scan_size - 4; i >= 0; i--) {
        if (*(uint32_t*)(scan_buf + i) == 0x06054b50) {
            if (scan_size - i >= sizeof(struct ZipEOCD)) {
                memcpy(&eocd, scan_buf + i, sizeof(struct ZipEOCD));
                found_eocd = 1;
                break;
            }
        }
    }
    free(scan_buf);

    if (!found_eocd) {
        fclose(fp);
        return -5;
    }

    fseek(fp, eocd.cd_offset, SEEK_SET);
    for (uint16_t entry = 0; entry < eocd.total_entries; entry++) {
        struct ZipCDHeader cd;
        if (fread(&cd, 1, sizeof(cd), fp) != sizeof(cd) || cd.signature != 0x02014b50) {
            break;
        }

        char filename[512];
        size_t fn_len = cd.filename_len < sizeof(filename) - 1 ? cd.filename_len : sizeof(filename) - 1;
        if (fread(filename, 1, fn_len, fp) != fn_len) break;
        filename[fn_len] = '\0';
        fseek(fp, (long)cd.filename_len - fn_len + cd.extra_len + cd.comment_len, SEEK_CUR);

        if (strcmp(filename, inner_filename) == 0) {
            fseek(fp, cd.local_header_offset, SEEK_SET);
            struct ZipLocalHeader lh;
            if (fread(&lh, 1, sizeof(lh), fp) == sizeof(lh) && lh.signature == 0x04034b50) {
                fseek(fp, lh.filename_len + lh.extra_len, SEEK_CUR);

                uint8_t* comp_data = (uint8_t*)malloc(cd.comp_size > 0 ? cd.comp_size : 1);
                uint8_t* uncomp_data = (uint8_t*)malloc(cd.uncomp_size > 0 ? cd.uncomp_size : 1);

                if (comp_data && uncomp_data) {
                    if (cd.comp_size == 0 || fread(comp_data, 1, cd.comp_size, fp) == cd.comp_size) {
                        if (decompress_buffer(comp_data, cd.comp_size, uncomp_data, cd.uncomp_size, cd.method) == 0) {
                            *out_data = uncomp_data;
                            *out_size = cd.uncomp_size;
                            free(comp_data);
                            fclose(fp);
                            return 0;
                        }
                    }
                }
                free(comp_data);
                free(uncomp_data);
            }
            break;
        }
    }

    fclose(fp);
    return -6; // Not found
}
