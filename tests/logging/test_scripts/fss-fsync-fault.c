/*
 * SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 *
 * LD_PRELOAD fsync/fdatasync fault injector for the FSS durability-barrier
 * tests. Fails by path, not by call ordinal: strace's inject=...:when=N hit
 * whichever matching call arrived first, so a barrier subtest could pass
 * while injecting nothing, and it could not target
 * $KEY_DIR/.verification-key.new.$$ at all because the PID is unknown before
 * launch.
 *
 * FSS_FSYNC_FAIL_GLOB carries one fnmatch(3) pattern, matched against the
 * path behind the fd; unset or empty is inert. Preload is inherited across
 * exec, so `sync FILE` (coreutils, a child process) is intercepted too.
 * Every injected failure prints one line to stderr, so a subtest can assert
 * that the barrier it meant to break is the one that broke.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fnmatch.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int should_fail(int fd) {
  const char *pattern = getenv("FSS_FSYNC_FAIL_GLOB");
  char link[64], path[PATH_MAX], msg[PATH_MAX + 64];
  ssize_t len;

  if (pattern == NULL || *pattern == '\0')
    return 0;
  snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
  len = readlink(link, path, sizeof path - 1);
  if (len < 0)
    return 0;
  path[len] = '\0';
  if (fnmatch(pattern, path, 0) != 0)
    return 0;

  len = snprintf(msg, sizeof msg, "fss-fsync-fault: EIO %s\n", path);
  if (len > 0)
    (void)!write(STDERR_FILENO, msg, (size_t)len);
  return 1;
}

int fsync(int fd) {
  static int (*real)(int);
  if (real == NULL)
    real = dlsym(RTLD_NEXT, "fsync");
  if (should_fail(fd)) {
    errno = EIO;
    return -1;
  }
  return real(fd);
}

int fdatasync(int fd) {
  static int (*real)(int);
  if (real == NULL)
    real = dlsym(RTLD_NEXT, "fdatasync");
  if (should_fail(fd)) {
    errno = EIO;
    return -1;
  }
  return real(fd);
}
