// Native CLI output protection. Original code, covered by the project MIT license.
// Only create a new directory entry; never truncate, unlink or replace a target.
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
#include "moonbit.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>

static wchar_t *output_path(const unsigned char *path, int length) {
  if (length <= 0 || memchr(path, 0, (size_t)length)) return NULL;
  int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                (const char *)path, length, NULL, 0);
  if (!count) return NULL;
  wchar_t *wide = (wchar_t *)malloc(((size_t)count + 1) * sizeof(wchar_t));
  if (!wide) return NULL;
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                         (const char *)path, length, wide, count)) {
    free(wide);
    return NULL;
  }
  wide[count] = 0;
  for (int i = 0; i < count; i++) {
    if (wide[i] == L'/') wide[i] = L'\\';
    // Refuse alternate streams and device namespaces, rather than writing
    // through an existing file's stream or accepting a non-file destination.
    if (wide[i] == L':' && !(i == 1 &&
        ((wide[0] >= L'A' && wide[0] <= L'Z') ||
         (wide[0] >= L'a' && wide[0] <= L'z')))) {
      free(wide);
      return NULL;
    }
  }
  if (count >= 4 && wide[0] == L'\\' && wide[1] == L'\\' &&
      (wide[2] == L'.' || wide[2] == L'?') && wide[3] == L'\\') {
    free(wide);
    return NULL;
  }
  return wide;
}

MOONBIT_FFI_EXPORT int moonsize_output_probe(moonbit_bytes_t path, int length) {
  wchar_t *wide = output_path(path, length);
  if (!wide) return 2;
  DWORD attrs = GetFileAttributesW(wide);
  DWORD error = GetLastError();
  free(wide);
  if (attrs != INVALID_FILE_ATTRIBUTES) return 1;
  return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ? 0 : 2;
}

MOONBIT_FFI_EXPORT int moonsize_output_create(moonbit_bytes_t path, int length,
                                            moonbit_bytes_t data, int size) {
  wchar_t *wide = output_path(path, length);
  if (!wide) return 2;
  HANDLE file = CreateFileW(wide, GENERIC_WRITE, FILE_SHARE_READ, NULL,
                           CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
  DWORD error = GetLastError();
  free(wide);
  if (file == INVALID_HANDLE_VALUE)
    return error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS ? 1 : 2;
  int status = 0;
  if (GetFileType(file) != FILE_TYPE_DISK) status = 2;
  int offset = 0;
  while (!status && offset < size) {
    DWORD written = 0;
    if (!WriteFile(file, data + offset, (DWORD)(size - offset), &written, NULL) ||
        !written) status = 2;
    else offset += (int)written;
  }
  if (!CloseHandle(file)) status = 2;
  return status;
}
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

static int valid_path(const unsigned char *path, int length) {
  return length > 0 && !memchr(path, 0, (size_t)length);
}

MOONBIT_FFI_EXPORT int moonsize_output_probe(moonbit_bytes_t path, int length) {
  if (!valid_path(path, length)) return 2;
  struct stat info;
  // lstat also refuses dangling final symlinks. Kernel lookup handles aliases.
  if (!lstat((const char *)path, &info)) return 1;
  return errno == ENOENT ? 0 : 2;
}

MOONBIT_FFI_EXPORT int moonsize_output_create(moonbit_bytes_t path, int length,
                                            moonbit_bytes_t data, int size) {
  if (!valid_path(path, length)) return 2;
  int file = open((const char *)path, O_WRONLY | O_CREAT | O_EXCL, 0666);
  if (file < 0) return errno == EEXIST ? 1 : 2;
  int offset = 0, status = 0;
  while (offset < size) {
    ssize_t written = write(file, data + offset, (size_t)(size - offset));
    if (written < 0 && errno == EINTR) continue;
    if (written <= 0) { status = 2; break; }
    offset += (int)written;
  }
  if (close(file)) status = 2;
  return status;
}
#endif
