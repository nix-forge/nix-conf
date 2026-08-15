#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

#ifndef O_DIRECTORY
#error "O_DIRECTORY is required for descriptor-bound directory operations"
#endif

#ifndef O_NOFOLLOW
#error "O_NOFOLLOW is required for descriptor-bound path operations"
#endif

static void usage(void);

static void fail_message(const char *message) { fprintf(stderr, "%s\n", message); }

static int fail_errno(const char *operation) {
  fprintf(stderr, "%s: %s\n", operation, strerror(errno));
  return 1;
}

static int is_private_mode(mode_t mode) { return (mode & 0077) == 0; }

static int is_owned_by_user(const struct stat *status) { return status->st_uid == geteuid(); }

static int parse_mode(const char *text, mode_t *mode) {
  char *end = NULL;
  unsigned long parsed;

  if (text == NULL || *text == '\0') {
    return 0;
  }
  errno = 0;
  parsed = strtoul(text, &end, 8);
  if (errno != 0 || end == text || *end != '\0' || parsed > 07777) {
    return 0;
  }
  *mode = (mode_t)parsed;
  return 1;
}

static int verify_status(const struct stat *status, int directory, const char *mode_text) {
  mode_t expected_mode = 0;

  if (directory) {
    if (!S_ISDIR(status->st_mode)) {
      fail_message("Expected a real directory.");
      return 0;
    }
  } else if (!S_ISREG(status->st_mode)) {
    fail_message("Expected a regular file.");
    return 0;
  }
  if (!is_owned_by_user(status)) {
    fail_message("Path is not owned by the current user.");
    return 0;
  }
  if (mode_text != NULL && strcmp(mode_text, "private") == 0) {
    if (!is_private_mode(status->st_mode)) {
      fail_message("Path is accessible to group or others.");
      return 0;
    }
  } else {
    if (!parse_mode(mode_text, &expected_mode) || (status->st_mode & 07777) != expected_mode) {
      fail_message("Path has an unexpected mode.");
      return 0;
    }
  }
  return 1;
}

static int component_is_dot(const char *component, size_t length) {
  return (length == 1 && component[0] == '.') ||
        (length == 2 && component[0] == '.' && component[1] == '.');
}

static int valid_generation_target(const char *target) {
  static const char prefix[] = "generation-";
  const char *cursor;

  if (target == NULL || strncmp(target, prefix, sizeof(prefix) - 1) != 0) {
    return 0;
  }
  cursor = target + sizeof(prefix) - 1;
  if (*cursor < '1' || *cursor > '9') {
    return 0;
  }
  for (cursor++; *cursor != '\0'; cursor++) {
    if (*cursor < '0' || *cursor > '9') {
      return 0;
    }
  }
  return 1;
}

static int open_trusted_path_internal(const char *path, int final_flags,
                                      int allow_generation_link) {
  const char *cursor;
  int directory_fd;
  int followed_generation_link = 0;

  if (path == NULL || *path == '\0') {
    errno = EINVAL;
    return -1;
  }

  if (strcmp(path, ".") == 0) {
    return open(".", O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | final_flags);
  }

  directory_fd = open(path[0] == '/' ? "/" : ".",
                      O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (directory_fd < 0) {
    return -1;
  }

  cursor = path;
  while (*cursor == '/') {
    cursor++;
  }
  if (*cursor == '\0') {
    return directory_fd;
  }

  for (;;) {
    const char *separator = cursor;
    size_t component_length;
    int is_final;
    int next_fd;
    char *component;
    int flags = O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW;

    while (*separator != '\0' && *separator != '/') {
      separator++;
    }
    component_length = (size_t)(separator - cursor);
    if (component_length == 0 || component_is_dot(cursor, component_length)) {
      close(directory_fd);
      errno = EINVAL;
      return -1;
    }
    component = malloc(component_length + 1);
    if (component == NULL) {
      close(directory_fd);
      errno = ENOMEM;
      return -1;
    }
    memcpy(component, cursor, component_length);
    component[component_length] = '\0';

    cursor = separator;
    while (*cursor == '/') {
      cursor++;
    }
    is_final = *cursor == '\0';
    if (!is_final) {
      flags |= O_DIRECTORY;
    } else {
      flags |= final_flags;
    }

    next_fd = openat(directory_fd, component, flags);
    if (next_fd < 0 && allow_generation_link && !followed_generation_link && !is_final &&
        strcmp(component, "current") == 0) {
      struct stat link_status;
      struct stat target_status;
      char target[64];
      ssize_t target_length;

      if (fstatat(directory_fd, component, &link_status, AT_SYMLINK_NOFOLLOW) < 0 ||
          !S_ISLNK(link_status.st_mode) || !is_owned_by_user(&link_status)) {
        free(component);
        close(directory_fd);
        errno = ELOOP;
        return -1;
      }
      target_length = readlinkat(directory_fd, component, target, sizeof(target) - 1);
      if (target_length <= 0 || (size_t)target_length >= sizeof(target) - 1) {
        free(component);
        close(directory_fd);
        errno = EINVAL;
        return -1;
      }
      target[target_length] = '\0';
      if (!valid_generation_target(target)) {
        free(component);
        close(directory_fd);
        errno = EINVAL;
        return -1;
      }
      next_fd = openat(directory_fd, target,
                      O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW | O_DIRECTORY);
      if (next_fd < 0 || fstat(next_fd, &target_status) < 0 ||
          !verify_status(&target_status, 1, "private")) {
        int saved_errno = errno == 0 ? EPERM : errno;
        if (next_fd >= 0) {
          close(next_fd);
        }
        free(component);
        close(directory_fd);
        errno = saved_errno;
        return -1;
      }
      followed_generation_link = 1;
    }
    free(component);
    close(directory_fd);
    if (next_fd < 0) {
      return -1;
    }
    if (is_final) {
      return next_fd;
    }
    directory_fd = next_fd;
  }
}

static int open_trusted_path(const char *path, int final_flags) {
  return open_trusted_path_internal(path, final_flags, 0);
}

static int open_trusted_generation_path(const char *path, int final_flags) {
  return open_trusted_path_internal(path, final_flags, 1);
}

static int valid_leaf_name(const char *name) {
  return name != NULL && *name != '\0' && strchr(name, '/') == NULL &&
    !component_is_dot(name, strlen(name));
}

static int open_trusted_parent(const char *path, char **name_out) {
  const char *separator;
  char *parent_path;
  char *name;
  size_t parent_length;
  int parent_fd;

  if (path == NULL || *path == '\0') {
    errno = EINVAL;
    return -1;
  }
  separator = strrchr(path, '/');
  if (separator == NULL) {
    parent_path = strdup(".");
    name = strdup(path);
  } else {
    parent_length = (size_t)(separator - path);
    if (parent_length == 0) {
      parent_path = strdup("/");
    } else {
      parent_path = malloc(parent_length + 1);
      if (parent_path != NULL) {
        memcpy(parent_path, path, parent_length);
        parent_path[parent_length] = '\0';
      }
    }
    name = strdup(separator + 1);
  }
  if (parent_path == NULL || name == NULL || !valid_leaf_name(name)) {
    free(parent_path);
    free(name);
    errno = EINVAL;
    return -1;
  }
  parent_fd = open_trusted_path(parent_path, O_DIRECTORY);
  free(parent_path);
  if (parent_fd < 0) {
    free(name);
    return -1;
  }
  *name_out = name;
  return parent_fd;
}

static int open_child(int directory_fd, const char *name, int directory) {
  int flags = O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW;
  if (directory) {
    flags |= O_DIRECTORY;
  }
  return openat(directory_fd, name, flags);
}

static int stat_matches(const struct stat *before, const struct stat *after) {
  if (before->st_dev != after->st_dev || before->st_ino != after->st_ino ||
      before->st_mode != after->st_mode || before->st_uid != after->st_uid ||
      before->st_gid != after->st_gid || before->st_nlink != after->st_nlink ||
      before->st_size != after->st_size) {
    return 0;
  }
#if defined(__APPLE__)
  return before->st_mtimespec.tv_sec == after->st_mtimespec.tv_sec &&
        before->st_mtimespec.tv_nsec == after->st_mtimespec.tv_nsec &&
        before->st_ctimespec.tv_sec == after->st_ctimespec.tv_sec &&
        before->st_ctimespec.tv_nsec == after->st_ctimespec.tv_nsec;
#else
  return before->st_mtim.tv_sec == after->st_mtim.tv_sec &&
        before->st_mtim.tv_nsec == after->st_mtim.tv_nsec &&
        before->st_ctim.tv_sec == after->st_ctim.tv_sec &&
        before->st_ctim.tv_nsec == after->st_ctim.tv_nsec;
#endif
}

static int verify_fd(int fd, int directory, const char *mode_text, struct stat *status) {
  if (fstat(fd, status) < 0) {
    return fail_errno("fstat");
  }
  return verify_status(status, directory, mode_text) ? 0 : 1;
}

static int command_validate_file_internal(const char *path, const char *mode_text,
                                          int report_state, int allow_generation_link) {
  struct stat status;
  int fd = allow_generation_link ? open_trusted_generation_path(path, 0)
                                : open_trusted_path(path, 0);
  if (fd < 0) {
    if (errno == ENOENT && report_state) {
      puts("missing");
      return 0;
    }
    return fail_errno("openat");
  }
  if (verify_fd(fd, 0, mode_text, &status) != 0) {
    close(fd);
    return 1;
  }
  close(fd);
  if (report_state) {
    puts("present");
  }
  return 0;
}

static int command_validate_file(const char *path, const char *mode_text, int report_state) {
  return command_validate_file_internal(path, mode_text, report_state, 0);
}

static int command_repair_file_mode(const char *path, const char *mode_text) {
  mode_t mode;
  struct stat before;
  struct stat after;
  int fd;

  if (!parse_mode(mode_text, &mode)) {
    fail_message("The requested file mode is invalid.");
    return 64;
  }
  fd = open_trusted_path(path, O_RDWR);
  if (fd < 0) {
    if (errno == ENOENT) {
      puts("missing");
      return 0;
    }
    return fail_errno("openat");
  }
  if (fstat(fd, &before) < 0) {
    int result = fail_errno("fstat");
    close(fd);
    return result;
  }
  if (!S_ISREG(before.st_mode)) {
    close(fd);
    fail_message("Expected a real regular file.");
    return 1;
  }
  if (!is_owned_by_user(&before)) {
    close(fd);
    fail_message("Path is not owned by the current user.");
    return 1;
  }
  if (fchmod(fd, mode) < 0) {
    int result = fail_errno("fchmod");
    close(fd);
    return result;
  }
  if (fstat(fd, &after) < 0) {
    int result = fail_errno("fstat");
    close(fd);
    return result;
  }
  if (before.st_dev != after.st_dev || before.st_ino != after.st_ino ||
      before.st_uid != after.st_uid || before.st_gid != after.st_gid ||
      before.st_nlink != after.st_nlink ||
      (after.st_mode & 07777) != mode) {
    close(fd);
    fail_message("The file changed while its mode was being repaired.");
    return 1;
  }
  close(fd);
  puts("present");
  return 0;
}

static int command_validate_directory(const char *path) {
  struct stat status;
  int fd = open_trusted_path(path, O_DIRECTORY);
  if (fd < 0) {
    return fail_errno("openat");
  }
  if (verify_fd(fd, 1, "private", &status) != 0) {
    close(fd);
    return 1;
  }
  close(fd);
  return 0;
}

static int command_validate_source_directory(const char *path) {
  struct stat status;
  int fd = open_trusted_path(path, O_DIRECTORY);
  if (fd < 0) {
    return fail_errno("openat");
  }
  if (fstat(fd, &status) < 0) {
    int result = fail_errno("fstat");
    close(fd);
    return result;
  }
  if (!S_ISDIR(status.st_mode) || !is_owned_by_user(&status)) {
    close(fd);
    fail_message("Source directory is not an owned real directory.");
    return 1;
  }
  close(fd);
  return 0;
}

static int command_ensure_directory(const char *path) {
  const char *cursor;
  int directory_fd;

  if (path == NULL || *path == '\0') {
    errno = EINVAL;
    return fail_errno("invalid directory path");
  }
  directory_fd = open(path[0] == '/' ? "/" : ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (directory_fd < 0) {
    return fail_errno("openat");
  }
  cursor = path;
  while (*cursor == '/') {
    cursor++;
  }
  while (*cursor != '\0') {
    const char *separator = cursor;
    size_t component_length;
    int next_fd;
    char *component;

    while (*separator != '\0' && *separator != '/') {
      separator++;
    }
    component_length = (size_t)(separator - cursor);
    if (component_length == 0 || component_is_dot(cursor, component_length)) {
      close(directory_fd);
      errno = EINVAL;
      return fail_errno("invalid directory path");
    }
    component = malloc(component_length + 1);
    if (component == NULL) {
      close(directory_fd);
      errno = ENOMEM;
      return fail_errno("malloc");
    }
    memcpy(component, cursor, component_length);
    component[component_length] = '\0';
    cursor = separator;
    while (*cursor == '/') {
      cursor++;
    }

    next_fd = openat(directory_fd, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (next_fd < 0 && errno == ENOENT) {
      if (mkdirat(directory_fd, component, 0700) < 0 && errno != EEXIST) {
        int saved_errno = errno;
        free(component);
        close(directory_fd);
        errno = saved_errno;
        return fail_errno("mkdirat");
      }
      next_fd = openat(directory_fd, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    }
    free(component);
    close(directory_fd);
    if (next_fd < 0) {
      return fail_errno("openat");
    }
    directory_fd = next_fd;
  }

  {
    struct stat status;
    if (verify_fd(directory_fd, 1, "private", &status) != 0) {
      close(directory_fd);
      return 1;
    }
    if (fchmod(directory_fd, 0700) < 0) {
      int result = fail_errno("fchmod");
      close(directory_fd);
      return result;
    }
  }
  close(directory_fd);
  return 0;
}

static int command_directory_empty(const char *path) {
  int fd = open_trusted_path(path, O_DIRECTORY);
  int scan_fd;
  DIR *directory;
  struct dirent *entry;
  int result = 0;

  if (fd < 0) {
    return fail_errno("openat");
  }
  if (verify_fd(fd, 1, "private", &(struct stat){0}) != 0) {
    close(fd);
    return 1;
  }
  scan_fd = dup(fd);
  if (scan_fd < 0) {
    close(fd);
    return fail_errno("dup");
  }
  directory = fdopendir(scan_fd);
  if (directory == NULL) {
    close(scan_fd);
    close(fd);
    return fail_errno("fdopendir");
  }
  errno = 0;
  while ((entry = readdir(directory)) != NULL) {
    if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) {
      result = 1;
      break;
    }
  }
  if (errno != 0) {
    result = 1;
  }
  closedir(directory);
  close(fd);
  return result;
}

static int directory_fd_is_empty(int fd) {
  int scan_fd = dup(fd);
  DIR *directory;
  struct dirent *entry;
  int result = 1;

  if (scan_fd < 0) {
    return -1;
  }
  directory = fdopendir(scan_fd);
  if (directory == NULL) {
    close(scan_fd);
    return -1;
  }
  errno = 0;
  while ((entry = readdir(directory)) != NULL) {
    if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) {
      result = 0;
      break;
    }
  }
  if (errno != 0) {
    result = -1;
  }
  closedir(directory);
  return result;
}

static int read_fd_to_stdout(int fd, const struct stat *before) {
  char buffer[65536];
  ssize_t count;
  off_t total = 0;
  struct stat after;

  for (;;) {
    count = read(fd, buffer, sizeof(buffer));
    if (count < 0) {
      return fail_errno("read");
    }
    if (count == 0) {
      break;
    }
    if (fwrite(buffer, 1, (size_t)count, stdout) != (size_t)count) {
      return fail_errno("write");
    }
    total += count;
  }
  if (fstat(fd, &after) < 0) {
    return fail_errno("fstat");
  }
  if (total != before->st_size || !stat_matches(before, &after)) {
    fail_message("File changed while it was being read.");
    return 1;
  }
  return 0;
}

static int command_read_file_internal(const char *path, const char *mode_text,
                                      int allow_generation_link) {
  struct stat status;
  int fd = allow_generation_link ? open_trusted_generation_path(path, 0)
                                : open_trusted_path(path, 0);
  int result;

  if (fd < 0) {
    return fail_errno("openat");
  }
  if (verify_fd(fd, 0, mode_text, &status) != 0) {
    close(fd);
    return 1;
  }
  result = read_fd_to_stdout(fd, &status);
  close(fd);
  return result;
}

static int command_read_file(const char *path, const char *mode_text) {
  return command_read_file_internal(path, mode_text, 0);
}

static int write_stdin_to_fd(int fd) {
  unsigned char buffer[65536];
  ssize_t count;

  for (;;) {
    count = read(STDIN_FILENO, buffer, sizeof(buffer));
    if (count < 0) {
      return fail_errno("read");
    }
    if (count == 0) {
      return 0;
    }
    {
      ssize_t written = 0;
      while (written < count) {
        ssize_t result = write(fd, buffer + written, (size_t)(count - written));
        if (result < 0) {
          return fail_errno("write");
        }
        written += result;
      }
    }
  }
}

static int command_create_file(const char *path, const char *mode_text) {
  char *name = NULL;
  mode_t mode;
  int parent_fd;
  int fd;
  struct stat status;
  int result = 1;

  if (!parse_mode(mode_text, &mode)) {
    fail_message("The requested file mode is invalid.");
    return 64;
  }
  parent_fd = open_trusted_parent(path, &name);
  if (parent_fd < 0) {
    return fail_errno("openat");
  }
  fd = openat(parent_fd, name, O_WRONLY | O_CLOEXEC | O_NOFOLLOW | O_CREAT | O_EXCL, mode);
  if (fd < 0) {
    result = fail_errno("openat");
    close(parent_fd);
    free(name);
    return result;
  }
  if (fchmod(fd, mode) < 0 || fstat(fd, &status) < 0 || !verify_status(&status, 0, mode_text)) {
    if (errno != 0) {
      result = fail_errno("create file");
    }
    close(fd);
    unlinkat(parent_fd, name, 0);
    close(parent_fd);
    free(name);
    return result;
  }
  if (write_stdin_to_fd(fd) != 0 || fsync(fd) < 0) {
    result = errno == 0 ? 1 : fail_errno("create file");
    close(fd);
    unlinkat(parent_fd, name, 0);
    close(parent_fd);
    free(name);
    return result;
  }
  if (close(fd) < 0) {
    result = fail_errno("close");
    unlinkat(parent_fd, name, 0);
    close(parent_fd);
    free(name);
    return result;
  }
  close(parent_fd);
  free(name);
  return 0;
}

static int command_atomic_write(const char *path, const char *mode_text) {
  char *name = NULL;
  mode_t mode;
  int parent_fd;
  int target_fd;
  int temporary_fd = -1;
  char temporary_name[NAME_MAX];
  struct stat status;
  unsigned long attempt;
  int result;

  if (!parse_mode(mode_text, &mode)) {
    fail_message("The requested file mode is invalid.");
    return 64;
  }
  parent_fd = open_trusted_parent(path, &name);
  if (parent_fd < 0) {
    return fail_errno("openat");
  }
  target_fd = openat(parent_fd, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (target_fd >= 0) {
    if (verify_fd(target_fd, 0, mode_text, &status) != 0) {
      close(target_fd);
      close(parent_fd);
      free(name);
      return 1;
    }
    close(target_fd);
  } else if (errno != ENOENT) {
    result = fail_errno("openat");
    close(parent_fd);
    free(name);
    return result;
  }

  for (attempt = 0; attempt < 1000; attempt++) {
    int written =
      snprintf(temporary_name, sizeof(temporary_name), ".local-control.%ld.%lu", (long)getpid(), attempt);
    if (written < 0 || (size_t)written >= sizeof(temporary_name)) {
      close(parent_fd);
      free(name);
      errno = ENAMETOOLONG;
      return fail_errno("temporary file");
    }
    temporary_fd = openat(parent_fd, temporary_name,
                          O_WRONLY | O_CLOEXEC | O_NOFOLLOW | O_CREAT | O_EXCL, mode);
    if (temporary_fd >= 0) {
      break;
    }
    if (errno != EEXIST) {
      result = fail_errno("openat");
      close(parent_fd);
      free(name);
      return result;
    }
  }
  if (temporary_fd < 0) {
    close(parent_fd);
    free(name);
    errno = EEXIST;
    return fail_errno("temporary file");
  }
  if (fchmod(temporary_fd, mode) < 0 || write_stdin_to_fd(temporary_fd) != 0 || fsync(temporary_fd) < 0) {
    result = errno == 0 ? 1 : fail_errno("atomic write");
    close(temporary_fd);
    unlinkat(parent_fd, temporary_name, 0);
    close(parent_fd);
    free(name);
    return result;
  }
  if (close(temporary_fd) < 0 || renameat(parent_fd, temporary_name, parent_fd, name) < 0 ||
      fsync(parent_fd) < 0) {
    result = fail_errno("atomic write");
    unlinkat(parent_fd, temporary_name, 0);
    close(parent_fd);
    free(name);
    return result;
  }
  close(parent_fd);
  free(name);
  return 0;
}

static int validate_cluster_child(int directory_fd, const char *name, int directory) {
  struct stat status;
  int fd = open_child(directory_fd, name, directory);
  if (fd < 0) {
    return fail_errno("openat");
  }
  if (verify_fd(fd, directory, "private", &status) != 0) {
    close(fd);
    return 1;
  }
  close(fd);
  return 0;
}

static int open_exec_directory(const char *path, int private_directory) {
  int fd = open_trusted_path(path, O_DIRECTORY);
  struct stat status;

  if (fd < 0) {
    return -1;
  }
  if (private_directory) {
    if (verify_fd(fd, 1, "private", &status) != 0) {
      close(fd);
      return -1;
    }
  } else if (fstat(fd, &status) < 0 || !S_ISDIR(status.st_mode) || !is_owned_by_user(&status)) {
    close(fd);
    fail_message("Source directory is not an owned real directory.");
    return -1;
  }
  return fd;
}

static int exec_with_directory(const char *path, int private_directory, const char *executable,
    int argument_count, char **arguments) {
  int fd = open_exec_directory(path, private_directory);
  char **child_argv;
  int result;

  if (fd < 0) {
    return fail_errno("openat");
  }
  child_argv = calloc((size_t)argument_count + 2, sizeof(*child_argv));
  if (child_argv == NULL) {
    close(fd);
    errno = ENOMEM;
    return fail_errno("calloc");
  }
  child_argv[0] = (char *)executable;
  for (int index = 0; index < argument_count; index++) {
    child_argv[index + 1] = arguments[index];
  }
  if (fchdir(fd) < 0) {
    result = fail_errno("fchdir");
    free(child_argv);
    close(fd);
    return result;
  }
  execv(executable, child_argv);
  result = fail_errno("execv");
  free(child_argv);
  close(fd);
  return result;
}

static int exec_with_empty_directory(const char *path, const char *executable, int argument_count,
    char **arguments) {
  int fd = open_exec_directory(path, 1);
  char **child_argv;
  int empty;
  int result;

  if (fd < 0) {
    return fail_errno("openat");
  }
  empty = directory_fd_is_empty(fd);
  if (empty < 0) {
    result = fail_errno("readdir");
    close(fd);
    return result;
  }
  if (empty == 0) {
    fail_message("The directory is not empty.");
    close(fd);
    return 1;
  }
  child_argv = calloc((size_t)argument_count + 2, sizeof(*child_argv));
  if (child_argv == NULL) {
    close(fd);
    errno = ENOMEM;
    return fail_errno("calloc");
  }
  child_argv[0] = (char *)executable;
  for (int index = 0; index < argument_count; index++) {
    child_argv[index + 1] = arguments[index];
  }
  if (fchdir(fd) < 0) {
    result = fail_errno("fchdir");
    free(child_argv);
    close(fd);
    return result;
  }
  execv(executable, child_argv);
  result = fail_errno("execv");
  free(child_argv);
  close(fd);
  return result;
}

struct file_mapping {
  char *name;
  int fd;
};

static void close_file_mappings(struct file_mapping *mappings, size_t count) {
  for (size_t index = 0; index < count; index++) {
    close(mappings[index].fd);
    free(mappings[index].name);
  }
  free(mappings);
}

static int find_file_mapping(const struct file_mapping *mappings, size_t count, const char *name) {
  for (size_t index = 0; index < count; index++) {
    if (strcmp(mappings[index].name, name) == 0) {
      return (int)index;
    }
  }
  return -1;
}

static int make_inheritable(int fd) {
  int flags = fcntl(fd, F_GETFD);
  if (flags < 0 || fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC) < 0) {
    return fail_errno("fcntl");
  }
  return 0;
}

static int resolve_fd_path(int fd, char **path_out) {
  char path[PATH_MAX];

  if (path_out == NULL) {
    errno = EINVAL;
    return fail_errno("resolve fd path");
  }

#if defined(__APPLE__)
  memset(path, 0, sizeof(path));
  if (fcntl(fd, F_GETPATH, path) < 0) {
    return fail_errno("fcntl");
  }
#else
  char proc_path[64];
  int proc_path_length = snprintf(proc_path, sizeof(proc_path), "/proc/self/fd/%d", fd);
  if (proc_path_length < 0 || (size_t)proc_path_length >= sizeof(proc_path)) {
    errno = EOVERFLOW;
    return fail_errno("format fd path");
  }
  ssize_t path_length = readlink(proc_path, path, sizeof(path) - 1);
  if (path_length < 0) {
    return fail_errno("readlink");
  }
  if ((size_t)path_length >= sizeof(path) - 1) {
    errno = ENAMETOOLONG;
    return fail_errno("readlink");
  }
  path[path_length] = '\0';
#endif

  if (path[0] != '/') {
    errno = EINVAL;
    return fail_errno("resolve fd path");
  }
  *path_out = strdup(path);
  if (*path_out == NULL) {
    errno = ENOMEM;
    return fail_errno("strdup");
  }
  return 0;
}

static int open_mapped_file(int directory_fd, const char *name, const char *mode_text,
                            const char *kind, int *fd_out) {
  int flags;
  mode_t mode;
  int fd;
  struct stat status;

  if (!valid_leaf_name(name) || !parse_mode(mode_text, &mode)) {
    fail_message("The mapped file specification is invalid.");
    return 64;
  }
  if (strcmp(kind, "create") == 0) {
    flags = O_RDWR | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW | O_CREAT | O_EXCL;
    fd = openat(directory_fd, name, flags, mode);
    if (fd >= 0 && fchmod(fd, mode) < 0) {
      int saved_errno = errno;
      close(fd);
      unlinkat(directory_fd, name, 0);
      errno = saved_errno;
      return fail_errno("fchmod");
    }
  } else if (strcmp(kind, "update") == 0) {
    fd = openat(directory_fd, name, O_RDWR | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
  } else if (strcmp(kind, "read") == 0) {
    fd = openat(directory_fd, name, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
  } else {
    fail_message("The mapped file mode is invalid.");
    return 64;
  }
  if (fd < 0) {
    return fail_errno("openat");
  }
  if (verify_fd(fd, 0, mode_text, &status) != 0 || make_inheritable(fd) != 0) {
    close(fd);
    if (strcmp(kind, "create") == 0) {
      unlinkat(directory_fd, name, 0);
    }
    return 1;
  }
  *fd_out = fd;
  return 0;
}

static int command_exec_files(int argc, char **argv) {
  int directory_fd;
  struct file_mapping *mappings = NULL;
  size_t mapping_count = 0;
  size_t mapping_capacity = 0;
  int separator = -1;
  char **child_argv = NULL;
  int result;

  if (argc < 5) {
    usage();
    return 64;
  }
  directory_fd = open_exec_directory(argv[1], 1);
  if (directory_fd < 0) {
    return fail_errno("openat");
  }
  for (int index = 3; index < argc; index++) {
    if (strcmp(argv[index], "--") == 0) {
      separator = index;
      break;
    }
    if (index + 3 >= argc ||
        (strcmp(argv[index], "--create") != 0 && strcmp(argv[index], "--update") != 0 &&
        strcmp(argv[index], "--read") != 0)) {
      fail_message("The mapped file command is malformed.");
      close(directory_fd);
      return 64;
    }
    if (mapping_count == mapping_capacity) {
      size_t new_capacity = mapping_capacity == 0 ? 4 : mapping_capacity * 2;
      struct file_mapping *new_mappings = realloc(mappings, new_capacity * sizeof(*new_mappings));
      if (new_mappings == NULL) {
        close(directory_fd);
        close_file_mappings(mappings, mapping_count);
        errno = ENOMEM;
        return fail_errno("realloc");
      }
      mappings = new_mappings;
      mapping_capacity = new_capacity;
    }
    mappings[mapping_count].name = strdup(argv[index + 1]);
    if (mappings[mapping_count].name == NULL) {
      close(directory_fd);
      close_file_mappings(mappings, mapping_count);
      errno = ENOMEM;
      return fail_errno("strdup");
    }
    if (find_file_mapping(mappings, mapping_count, mappings[mapping_count].name) >= 0 ||
        open_mapped_file(directory_fd, argv[index + 1], argv[index + 2], argv[index] + 2,
        &mappings[mapping_count].fd) != 0) {
      free(mappings[mapping_count].name);
      mappings[mapping_count].name = NULL;
      close(directory_fd);
      close_file_mappings(mappings, mapping_count);
      return 1;
    }
    mapping_count++;
    index += 2;
  }
  if (separator < 0 || separator + 1 >= argc) {
    fail_message("The mapped file command is missing its executable arguments.");
    close(directory_fd);
    close_file_mappings(mappings, mapping_count);
    return 64;
  }
  child_argv = calloc((size_t)(argc - separator + 1), sizeof(*child_argv));
  if (child_argv == NULL) {
    close(directory_fd);
    close_file_mappings(mappings, mapping_count);
    errno = ENOMEM;
    return fail_errno("calloc");
  }
  child_argv[0] = argv[2];
  for (int index = separator + 1; index < argc; index++) {
    const char *argument = argv[index];
    char *replacement = NULL;
    if (argument[0] == '@' && argument[strlen(argument) - 1] == '@') {
      size_t name_length = strlen(argument) - 2;
      char *name = strndup(argument + 1, name_length);
      int mapping_index = name == NULL ? -1 : find_file_mapping(mappings, mapping_count, name);
      free(name);
      if (mapping_index < 0) {
        fail_message("The mapped file placeholder is unknown.");
        free(child_argv);
        close(directory_fd);
        close_file_mappings(mappings, mapping_count);
        return 64;
      }
      if (asprintf(&replacement, "/dev/fd/%d", mappings[mapping_index].fd) < 0) {
        free(child_argv);
        close(directory_fd);
        close_file_mappings(mappings, mapping_count);
        errno = ENOMEM;
        return fail_errno("asprintf");
      }
      child_argv[index - separator] = replacement;
    } else {
      child_argv[index - separator] = argv[index];
    }
  }
  if (fchdir(directory_fd) < 0) {
    result = fail_errno("fchdir");
    free(child_argv);
    close(directory_fd);
    close_file_mappings(mappings, mapping_count);
    return result;
  }
  execv(argv[2], child_argv);
  result = fail_errno("execv");
  for (int index = 1; index < argc - separator; index++) {
    if (child_argv[index] != argv[separator + index]) {
      free(child_argv[index]);
    }
  }
  free(child_argv);
  close(directory_fd);
  close_file_mappings(mappings, mapping_count);
  return result;
}

static void clear_sensitive_bytes(char *value, size_t length) {
  volatile unsigned char *cursor = (volatile unsigned char *)value;
  while (length > 0) {
    *cursor++ = 0;
    length--;
  }
}

static int valid_environment_name(const char *value, size_t length) {
  if (length == 0 || !((value[0] >= 'A' && value[0] <= 'Z') || value[0] == '_')) {
    return 0;
  }
  for (size_t index = 1; index < length; index++) {
    if (!((value[index] >= 'A' && value[index] <= 'Z') ||
          (value[index] >= '0' && value[index] <= '9') || value[index] == '_')) {
      return 0;
    }
  }
  return 1;
}

static int load_proxy_attestation(const char *path, char **value_out) {
  static const char expected_name[] = "SERVICE_PROXY_ATTESTATION";
  const size_t maximum_size = 65536;
  struct stat before;
  struct stat after;
  int fd = -1;
  char *contents = NULL;
  char *attestation = NULL;
  size_t total = 0;
  int found = 0;
  int result = 1;

  if (value_out == NULL) {
    errno = EINVAL;
    return fail_errno("proxy environment");
  }
  *value_out = NULL;
  fd = open_trusted_generation_path(path, 0);
  if (fd < 0) {
    return fail_errno("openat");
  }
  if (verify_fd(fd, 0, "600", &before) != 0 || before.st_size <= 0 ||
      (uint64_t)before.st_size > maximum_size) {
    fail_message("Proxy environment file is empty, oversized, or unsafe.");
    goto cleanup;
  }
  contents = malloc((size_t)before.st_size + 1);
  if (contents == NULL) {
    errno = ENOMEM;
    fail_errno("malloc");
    goto cleanup;
  }
  while (total < (size_t)before.st_size) {
    ssize_t count = read(fd, contents + total, (size_t)before.st_size - total);
    if (count <= 0) {
      if (count < 0) {
        fail_errno("read");
      } else {
        fail_message("Proxy environment file changed while it was read.");
      }
      goto cleanup;
    }
    total += (size_t)count;
  }
  {
    unsigned char extra;
    ssize_t count = read(fd, &extra, 1);
    if (count != 0) {
      if (count < 0) {
        fail_errno("read");
      } else {
        fail_message("Proxy environment file changed while it was read.");
      }
      goto cleanup;
    }
  }
  if (fstat(fd, &after) < 0) {
    fail_errno("fstat");
    goto cleanup;
  }
  if (!stat_matches(&before, &after)) {
    fail_message("Proxy environment file changed while it was read.");
    goto cleanup;
  }
  contents[total] = '\0';

  for (size_t offset = 0; offset < total;) {
    size_t line_end = offset;
    size_t equals = offset;
    while (line_end < total && contents[line_end] != '\n') {
      if (contents[line_end] == '\0' || contents[line_end] == '\r') {
        fail_message("Proxy environment file contains control data.");
        goto cleanup;
      }
      line_end++;
    }
    if (line_end == offset || contents[offset] == '#') {
      offset = line_end < total ? line_end + 1 : total;
      continue;
    }
    while (equals < line_end && contents[equals] != '=') {
      equals++;
    }
    if (equals == line_end || !valid_environment_name(contents + offset, equals - offset)) {
      fail_message("Proxy environment file contains a malformed record.");
      goto cleanup;
    }
    if ((equals - offset) == sizeof(expected_name) - 1 &&
        memcmp(contents + offset, expected_name, sizeof(expected_name) - 1) == 0) {
      size_t value_start = equals + 1;
      size_t value_length = line_end - value_start;
      if (found || value_length < 32 || value_length > 512) {
        fail_message("Proxy attestation is missing, duplicated, or invalid.");
        goto cleanup;
      }
      for (size_t index = value_start; index < line_end; index++) {
        unsigned char character = (unsigned char)contents[index];
        if (character < 0x21 || character > 0x7e) {
          fail_message("Proxy attestation is missing, duplicated, or invalid.");
          goto cleanup;
        }
      }
      attestation = malloc(value_length + 1);
      if (attestation == NULL) {
        errno = ENOMEM;
        fail_errno("malloc");
        goto cleanup;
      }
      memcpy(attestation, contents + value_start, value_length);
      attestation[value_length] = '\0';
      found = 1;
    }
    offset = line_end < total ? line_end + 1 : total;
  }
  if (!found) {
    fail_message("Proxy attestation is missing, duplicated, or invalid.");
    goto cleanup;
  }
  *value_out = attestation;
  attestation = NULL;
  result = 0;

cleanup:
  if (fd >= 0) {
    close(fd);
  }
  if (contents != NULL) {
    clear_sensitive_bytes(contents, total);
    free(contents);
  }
  if (attestation != NULL) {
    clear_sensitive_bytes(attestation, strlen(attestation));
    free(attestation);
  }
  return result;
}

static int command_exec_proxy(int argc, char **argv) {
  char **child_argv = NULL;
  char *proxy_attestation = NULL;
  int directory_fd;
  const char *names[] = {"ca.crt", "server.crt", "server.key"};
  const char *modes[] = {"644", "644", "600"};
  const char *variables[] = {"LOCAL_CONTROL_PROXY_CA", "LOCAL_CONTROL_PROXY_CERT",
    "LOCAL_CONTROL_PROXY_KEY"};
  int file_fds[3];

  if (argc < 5) {
    usage();
    return 64;
  }
  directory_fd = open_exec_directory(argv[1], 1);
  if (directory_fd < 0) {
    return fail_errno("openat");
  }
  for (size_t index = 0; index < 3; index++) {
    if (open_mapped_file(directory_fd, names[index], modes[index], "read", &file_fds[index]) != 0) {
      close(directory_fd);
      for (size_t cleanup = 0; cleanup < index; cleanup++) {
        close(file_fds[cleanup]);
      }
      return 1;
    }
    char *fd_path = NULL;
    if (asprintf(&fd_path, "/dev/fd/%d", file_fds[index]) < 0 ||
        setenv(variables[index], fd_path, 1) < 0) {
      free(fd_path);
      close(directory_fd);
      for (size_t cleanup = 0; cleanup <= index; cleanup++) {
        close(file_fds[cleanup]);
      }
      return fail_errno("setenv");
    }
    free(fd_path);
  }
  if (load_proxy_attestation(argv[2], &proxy_attestation) != 0 ||
      setenv("SERVICE_PROXY_ATTESTATION", proxy_attestation, 1) < 0) {
    if (proxy_attestation != NULL) {
      clear_sensitive_bytes(proxy_attestation, strlen(proxy_attestation));
      free(proxy_attestation);
    }
    close(directory_fd);
    for (size_t cleanup = 0; cleanup < 3; cleanup++) {
      close(file_fds[cleanup]);
    }
    return 1;
  }
  clear_sensitive_bytes(proxy_attestation, strlen(proxy_attestation));
  free(proxy_attestation);

  child_argv = calloc((size_t)argc - 2, sizeof(*child_argv));
  if (child_argv == NULL) {
    close(directory_fd);
    for (size_t cleanup = 0; cleanup < 3; cleanup++) {
      close(file_fds[cleanup]);
    }
    errno = ENOMEM;
    return fail_errno("calloc");
  }
  child_argv[0] = argv[3];
  for (int index = 4; index < argc; index++) {
    child_argv[index - 3] = argv[index];
  }
  child_argv[argc - 3] = NULL;
  if (fchdir(directory_fd) < 0) {
    int result = fail_errno("fchdir");
    free(child_argv);
    close(directory_fd);
    for (size_t cleanup = 0; cleanup < 3; cleanup++) {
      close(file_fds[cleanup]);
    }
    return result;
  }
  execv(argv[3], child_argv);
  free(child_argv);
  close(directory_fd);
  for (size_t cleanup = 0; cleanup < 3; cleanup++) {
    close(file_fds[cleanup]);
  }
  return fail_errno("execv");
}

static int validate_cluster_fd(int fd, const char *version) {
  char contents[128];
  ssize_t count;

  if (verify_fd(fd, 1, "private", &(struct stat){0}) != 0) {
    return 1;
  }
  {
    const char *files[] = {"PG_VERSION", "postgresql.conf", "pg_hba.conf", "pg_ident.conf"};
    const char *directories[] = {"base", "global", "pg_wal"};
    size_t index;
    for (index = 0; index < sizeof(files) / sizeof(files[0]); index++) {
      if (validate_cluster_child(fd, files[index], 0) != 0) {
        return 1;
      }
    }
    for (index = 0; index < sizeof(directories) / sizeof(directories[0]); index++) {
      if (validate_cluster_child(fd, directories[index], 1) != 0) {
        return 1;
      }
    }
  }

  {
    int version_fd = open_child(fd, "PG_VERSION", 0);
    if (version_fd < 0) {
      return fail_errno("openat");
    }
    count = read(version_fd, contents, sizeof(contents) - 1);
    if (count < 0) {
      int result = fail_errno("read");
      close(version_fd);
      return result;
    }
    contents[count] = '\0';
    if (strcmp(contents, version) != 0 && (count < 1 || contents[count - 1] != '\n' ||
                                          strncmp(contents, version, (size_t)count - 1) != 0)) {
      close(version_fd);
      fail_message("The directory has an incompatible version marker.");
      return 1;
    }
    close(version_fd);
  }
  return 0;
}

static int command_validate_cluster(const char *path, const char *version) {
  int fd = open_trusted_path(path, O_DIRECTORY);
  int result;
  if (fd < 0) {
    return fail_errno("openat");
  }
  result = validate_cluster_fd(fd, version);
  close(fd);
  return result;
}

static int command_exec_cluster(int argc, char **argv) {
  int fd;

  if (argc < 5) {
    usage();
    return 64;
  }
  fd = open_trusted_path(argv[1], O_DIRECTORY);
  if (fd < 0) {
    return fail_errno("openat");
  }
  if (validate_cluster_fd(fd, argv[2]) != 0) {
    close(fd);
    return 1;
  }
  if (fchdir(fd) < 0) {
    int result = fail_errno("fchdir");
    close(fd);
    return result;
  }
  if (execv(argv[3], &argv[3]) < 0) {
    return fail_errno("execv");
  }
  return 1;
}

static int command_exec_cluster_socket(int argc, char **argv) {
  int cluster_fd;
  int socket_fd;
  struct stat socket_status;
  char *socket_path = NULL;
  char **child_argv;
  int result;

  if (argc < 6) {
    usage();
    return 64;
  }
  cluster_fd = open_trusted_path(argv[1], O_DIRECTORY);
  if (cluster_fd < 0) {
    return fail_errno("openat");
  }
  if (validate_cluster_fd(cluster_fd, argv[2]) != 0) {
    close(cluster_fd);
    return 1;
  }
  socket_fd = open_trusted_path(argv[3], O_DIRECTORY);
  if (socket_fd < 0) {
    close(cluster_fd);
    return fail_errno("openat");
  }
  if (verify_fd(socket_fd, 1, "private", &socket_status) != 0 ||
      resolve_fd_path(socket_fd, &socket_path) != 0) {
    close(cluster_fd);
    close(socket_fd);
    return 1;
  }
  /* argv[4] and argv[5..argc) require one additional NULL terminator. */
  child_argv = calloc((size_t)(argc - 3), sizeof(*child_argv));
  if (child_argv == NULL) {
    close(cluster_fd);
    close(socket_fd);
    free(socket_path);
    errno = ENOMEM;
    return fail_errno("calloc");
  }
  child_argv[0] = argv[4];
  for (int index = 5; index < argc; index++) {
    if (strcmp(argv[index], "@socket@") == 0) {
      child_argv[index - 4] = strdup(socket_path);
      if (child_argv[index - 4] == NULL) {
        free(child_argv);
        close(cluster_fd);
        close(socket_fd);
        free(socket_path);
        errno = ENOMEM;
        return fail_errno("strdup");
      }
    } else {
      child_argv[index - 4] = argv[index];
    }
  }
  if (fchdir(cluster_fd) < 0) {
    result = fail_errno("fchdir");
    for (int index = 1; index < argc - 4; index++) {
      if (child_argv[index] != argv[index + 4]) {
        free(child_argv[index]);
      }
    }
    free(child_argv);
    close(cluster_fd);
    close(socket_fd);
    free(socket_path);
    return result;
  }
  execv(argv[4], child_argv);
  result = fail_errno("execv");
  for (int index = 1; index < argc - 4; index++) {
    if (child_argv[index] != argv[index + 4]) {
      free(child_argv[index]);
    }
  }
  free(child_argv);
  close(cluster_fd);
  close(socket_fd);
  free(socket_path);
  return result;
}

static int command_cluster_state(const char *path, const char *version) {
  int fd = open_trusted_path(path, O_DIRECTORY);
  int marker_fd;
  int empty;
  char contents[128];
  ssize_t count;

  if (fd < 0) {
    return fail_errno("openat");
  }
  if (verify_fd(fd, 1, "private", &(struct stat){0}) != 0) {
    close(fd);
    return 1;
  }
  marker_fd = open_child(fd, "PG_VERSION", 0);
  if (marker_fd < 0 && errno == ENOENT) {
    empty = directory_fd_is_empty(fd);
    close(fd);
    if (empty < 0) {
      return fail_errno("readdir");
    }
    if (empty == 1) {
      puts("missing");
      return 0;
    }
    fail_message("The database directory is non-empty without a valid cluster marker.");
    return 1;
  }
  if (marker_fd < 0) {
    int result = fail_errno("openat");
    close(fd);
    return result;
  }
  count = read(marker_fd, contents, sizeof(contents) - 1);
  close(marker_fd);
  if (count < 0) {
    int result = fail_errno("read");
    close(fd);
    return result;
  }
  contents[count] = '\0';
  if ((strcmp(contents, version) != 0 &&
      (count < 1 || contents[count - 1] != '\n' ||
        strncmp(contents, version, (size_t)count - 1) != 0))) {
    close(fd);
    fail_message("The database directory has an incompatible version marker.");
    return 1;
  }
  if (validate_cluster_fd(fd, version) != 0) {
    close(fd);
    return 1;
  }
  close(fd);
  puts("present");
  return 0;
}

static int command_initialize_cluster(int argc, char **argv) {
  int fd;
  int empty;
  pid_t child;
  int child_status;

  if (argc < 5) {
    usage();
    return 64;
  }
  fd = open_exec_directory(argv[1], 1);
  if (fd < 0) {
    return fail_errno("openat");
  }
  empty = directory_fd_is_empty(fd);
  if (empty < 0) {
    int result = fail_errno("readdir");
    close(fd);
    return result;
  }
  if (empty == 0) {
    close(fd);
    fail_message("The directory is not empty.");
    return 1;
  }
  child = fork();
  if (child < 0) {
    int result = fail_errno("fork");
    close(fd);
    return result;
  }
  if (child == 0) {
    char **child_argv = calloc((size_t)(argc - 2), sizeof(*child_argv));
    if (child_argv == NULL) {
      dprintf(STDERR_FILENO, "calloc: %s\n", strerror(errno));
      _exit(127);
    }
    if (fchdir(fd) < 0) {
      dprintf(STDERR_FILENO, "fchdir: %s\n", strerror(errno));
      _exit(127);
    }
    child_argv[0] = argv[3];
    for (int index = 4; index < argc; index++) {
      child_argv[index - 3] = argv[index];
    }
    child_argv[argc - 3] = NULL;
    execv(argv[3], child_argv);
    dprintf(STDERR_FILENO, "execv: %s\n", strerror(errno));
    _exit(127);
  }
  if (waitpid(child, &child_status, 0) < 0) {
    int result = fail_errno("waitpid");
    close(fd);
    return result;
  }
  if (!WIFEXITED(child_status) || WEXITSTATUS(child_status) != 0) {
    close(fd);
    fail_message("The database initializer failed.");
    return 1;
  }
  if (validate_cluster_fd(fd, argv[2]) != 0) {
    close(fd);
    return 1;
  }
  close(fd);
  return 0;
}

static int write_u32(uint32_t value) {
  unsigned char bytes[4];
  bytes[0] = (unsigned char)(value & 0xffU);
  bytes[1] = (unsigned char)((value >> 8) & 0xffU);
  bytes[2] = (unsigned char)((value >> 16) & 0xffU);
  bytes[3] = (unsigned char)((value >> 24) & 0xffU);
  return fwrite(bytes, 1, sizeof(bytes), stdout) == sizeof(bytes) ? 0 : 1;
}

static int write_u64(uint64_t value) {
  unsigned char bytes[8];
  size_t index;
  for (index = 0; index < sizeof(bytes); index++) {
    bytes[index] = (unsigned char)((value >> (index * 8)) & 0xffU);
  }
  return fwrite(bytes, 1, sizeof(bytes), stdout) == sizeof(bytes) ? 0 : 1;
}

static int write_bytes(const void *data, size_t length) {
  return fwrite(data, 1, length, stdout) == length ? 0 : 1;
}

static int write_snapshot_header(unsigned char kind, mode_t mode, const char *path,
                                uint64_t data_length) {
  size_t path_length = strlen(path);
  if (write_bytes(&kind, 1) != 0 || write_u32((uint32_t)(mode & 07777)) != 0 ||
      write_u64((uint64_t)path_length) != 0 || write_bytes(path, path_length) != 0 ||
      write_u64(data_length) != 0) {
    return fail_errno("write");
  }
  return 0;
}

static char *join_snapshot_path(const char *prefix, const char *name) {
  size_t prefix_length = strlen(prefix);
  size_t name_length = strlen(name);
  char *joined = malloc(prefix_length + 1 + name_length + 1);
  if (joined == NULL) {
    errno = ENOMEM;
    return NULL;
  }
  if (strcmp(prefix, ".") == 0) {
    snprintf(joined, name_length + 2, "./%s", name);
  } else {
    memcpy(joined, prefix, prefix_length);
    joined[prefix_length] = '/';
    memcpy(joined + prefix_length + 1, name, name_length + 1);
  }
  return joined;
}

static int compare_names(const void *left, const void *right) {
  const char *const *left_name = left;
  const char *const *right_name = right;
  return strcmp(*left_name, *right_name);
}

static int collect_names(int directory_fd, char ***names_out, size_t *count_out,
                        struct stat *before, struct stat *after) {
  int scan_fd;
  DIR *directory;
  struct dirent *entry;
  char **names = NULL;
  size_t count = 0;
  size_t capacity = 0;

  if (fstat(directory_fd, before) < 0) {
    return fail_errno("fstat");
  }
  scan_fd = dup(directory_fd);
  if (scan_fd < 0) {
    return fail_errno("dup");
  }
  directory = fdopendir(scan_fd);
  if (directory == NULL) {
    close(scan_fd);
    return fail_errno("fdopendir");
  }
  errno = 0;
  while ((entry = readdir(directory)) != NULL) {
    char *name;
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    if (count == capacity) {
      size_t new_capacity = capacity == 0 ? 16 : capacity * 2;
      char **new_names = realloc(names, new_capacity * sizeof(*new_names));
      if (new_names == NULL) {
        closedir(directory);
        for (size_t index = 0; index < count; index++) {
          free(names[index]);
        }
        free(names);
        errno = ENOMEM;
        return fail_errno("realloc");
      }
      names = new_names;
      capacity = new_capacity;
    }
    name = strdup(entry->d_name);
    if (name == NULL) {
      closedir(directory);
      for (size_t index = 0; index < count; index++) {
        free(names[index]);
      }
      free(names);
      errno = ENOMEM;
      return fail_errno("strdup");
    }
    names[count++] = name;
  }
  if (errno != 0 || fstat(directory_fd, after) < 0) {
    int saved_errno = errno == 0 ? EIO : errno;
    closedir(directory);
    for (size_t index = 0; index < count; index++) {
      free(names[index]);
    }
    free(names);
    errno = saved_errno;
    return fail_errno("directory snapshot");
  }
  closedir(directory);
  qsort(names, count, sizeof(*names), compare_names);
  *names_out = names;
  *count_out = count;
  return 0;
}

static int snapshot_file(int fd, const struct stat *before, const char *path) {
  unsigned char buffer[65536];
  uint64_t remaining = (uint64_t)before->st_size;
  struct stat after;

  if (write_snapshot_header('F', before->st_mode, path, remaining) != 0) {
    return 1;
  }
  while (remaining > 0) {
    size_t requested = remaining < sizeof(buffer) ? (size_t)remaining : sizeof(buffer);
    ssize_t count = read(fd, buffer, requested);
    if (count <= 0 || write_bytes(buffer, (size_t)count) != 0) {
      return count < 0 ? fail_errno("read") : 1;
    }
    remaining -= (uint64_t)count;
  }
  {
    unsigned char extra;
    ssize_t count = read(fd, &extra, 1);
    if (count != 0) {
      fail_message("File changed while it was being snapshotted.");
      return 1;
    }
  }
  if (fstat(fd, &after) < 0) {
    return fail_errno("fstat");
  }
  if (!stat_matches(before, &after)) {
    fail_message("File changed while it was being snapshotted.");
    return 1;
  }
  return 0;
}

static int snapshot_directory(int fd, const char *path) {
  char **names = NULL;
  size_t count = 0;
  struct stat directory_before;
  struct stat names_before;
  struct stat after;

  if (fstat(fd, &directory_before) < 0) {
    return fail_errno("fstat");
  }
  if (!S_ISDIR(directory_before.st_mode) || !is_owned_by_user(&directory_before)) {
    fail_message("Source directory is not an owned real directory.");
    return 1;
  }
  if (write_snapshot_header('D', directory_before.st_mode, path, 0) != 0) {
    return 1;
  }
  if (collect_names(fd, &names, &count, &names_before, &after) != 0) {
    return 1;
  }
  if (!stat_matches(&directory_before, &names_before)) {
    for (size_t index = 0; index < count; index++) {
      free(names[index]);
    }
    free(names);
    fail_message("Source directory changed while it was being snapshotted.");
    return 1;
  }
  for (size_t index = 0; index < count; index++) {
    const char *name = names[index];
    int child_fd;
    struct stat child_status;
    char *child_path;

    child_path = join_snapshot_path(path, name);
    if (child_path == NULL) {
      for (size_t cleanup = 0; cleanup < count; cleanup++) {
        free(names[cleanup]);
      }
      free(names);
      return fail_errno("malloc");
    }
    child_fd = open_child(fd, name, 0);
    if (child_fd < 0) {
      free(child_path);
      for (size_t cleanup = 0; cleanup < count; cleanup++) {
        free(names[cleanup]);
      }
      free(names);
      return fail_errno("openat");
    }
    if (fstat(child_fd, &child_status) < 0) {
      close(child_fd);
      free(child_path);
      for (size_t cleanup = 0; cleanup < count; cleanup++) {
        free(names[cleanup]);
      }
      free(names);
      return fail_errno("fstat");
    }
    if (strcmp(name, ".git") == 0 && S_ISDIR(child_status.st_mode)) {
      close(child_fd);
      free(child_path);
      continue;
    }
    if (!is_owned_by_user(&child_status) ||
        (!S_ISREG(child_status.st_mode) && !S_ISDIR(child_status.st_mode))) {
      close(child_fd);
      free(child_path);
      for (size_t cleanup = 0; cleanup < count; cleanup++) {
        free(names[cleanup]);
      }
      free(names);
      fail_message("Source tree contains a symlink or special file.");
      return 1;
    }
    if (S_ISDIR(child_status.st_mode)) {
      if (snapshot_directory(child_fd, child_path) != 0) {
        close(child_fd);
        free(child_path);
        for (size_t cleanup = 0; cleanup < count; cleanup++) {
          free(names[cleanup]);
        }
        free(names);
        return 1;
      }
    } else if (snapshot_file(child_fd, &child_status, child_path) != 0) {
      close(child_fd);
      free(child_path);
      for (size_t cleanup = 0; cleanup < count; cleanup++) {
        free(names[cleanup]);
      }
      free(names);
      return 1;
    }
    close(child_fd);
    free(child_path);
  }
  if (fstat(fd, &after) < 0 || !stat_matches(&directory_before, &after)) {
    for (size_t index = 0; index < count; index++) {
      free(names[index]);
    }
    free(names);
    fail_message("Source directory changed while it was being snapshotted.");
    return 1;
  }
  for (size_t index = 0; index < count; index++) {
    free(names[index]);
  }
  free(names);
  return 0;
}

static int command_snapshot_tree(const char *path) {
  int fd = open_trusted_path(path, O_DIRECTORY);
  int result;
  if (fd < 0) {
    return fail_errno("openat");
  }
  result = snapshot_directory(fd, ".");
  close(fd);
  return result;
}

static void usage(void) {
  fprintf(stderr, "Usage: local-control-secure-files COMMAND PATH [MODE]\n"
                  "Commands: ensure-directory, validate-directory, "
                  "validate-source-directory, "
                  "validate-file, inspect-file, inspect-generation-file, repair-file-mode, "
                  "read-file, read-generation-file, create-file, atomic-write, directory-empty, "
                  "validate-cluster, cluster-state, initialize-cluster, exec-cluster, "
                  "exec-cluster-socket, "
                  "exec-private-directory, exec-empty-private-directory, exec-source, "
                  "exec-files, exec-proxy, "
                  "snapshot-tree\n");
}

int main(int argc, char **argv) {
  if (argc < 3) {
    usage();
    return 64;
  }
  if (strcmp(argv[1], "ensure-directory") == 0 && argc == 3) {
    return command_ensure_directory(argv[2]);
  }
  if (strcmp(argv[1], "validate-directory") == 0 && argc == 3) {
    return command_validate_directory(argv[2]);
  }
  if (strcmp(argv[1], "validate-source-directory") == 0 && argc == 3) {
    return command_validate_source_directory(argv[2]);
  }
  if (strcmp(argv[1], "validate-file") == 0 && argc == 4) {
    return command_validate_file(argv[2], argv[3], 0);
  }
  if (strcmp(argv[1], "inspect-file") == 0 && argc == 4) {
    return command_validate_file(argv[2], argv[3], 1);
  }
  if (strcmp(argv[1], "inspect-generation-file") == 0 && argc == 4) {
    return command_validate_file_internal(argv[2], argv[3], 1, 1);
  }
  if (strcmp(argv[1], "repair-file-mode") == 0 && argc == 4) {
    return command_repair_file_mode(argv[2], argv[3]);
  }
  if (strcmp(argv[1], "read-file") == 0 && argc == 4) {
    return command_read_file(argv[2], argv[3]);
  }
  if (strcmp(argv[1], "read-generation-file") == 0 && argc == 4) {
    return command_read_file_internal(argv[2], argv[3], 1);
  }
  if (strcmp(argv[1], "create-file") == 0 && argc == 4) {
    return command_create_file(argv[2], argv[3]);
  }
  if (strcmp(argv[1], "atomic-write") == 0 && argc == 4) {
    return command_atomic_write(argv[2], argv[3]);
  }
  if (strcmp(argv[1], "directory-empty") == 0 && argc == 3) {
    return command_directory_empty(argv[2]);
  }
  if (strcmp(argv[1], "validate-cluster") == 0 && argc == 4) {
    return command_validate_cluster(argv[2], argv[3]);
  }
  if (strcmp(argv[1], "cluster-state") == 0 && argc == 4) {
    return command_cluster_state(argv[2], argv[3]);
  }
  if (strcmp(argv[1], "initialize-cluster") == 0) {
    return command_initialize_cluster(argc - 1, &argv[1]);
  }
  if (strcmp(argv[1], "exec-cluster") == 0) {
    return command_exec_cluster(argc - 1, &argv[1]);
  }
  if (strcmp(argv[1], "exec-cluster-socket") == 0) {
    return command_exec_cluster_socket(argc - 1, &argv[1]);
  }
  if (strcmp(argv[1], "exec-private-directory") == 0 && argc >= 4) {
    return exec_with_directory(argv[2], 1, argv[3], argc - 4, &argv[4]);
  }
  if (strcmp(argv[1], "exec-empty-private-directory") == 0 && argc >= 4) {
    return exec_with_empty_directory(argv[2], argv[3], argc - 4, &argv[4]);
  }
  if (strcmp(argv[1], "exec-source") == 0 && argc >= 4) {
    return exec_with_directory(argv[2], 0, argv[3], argc - 4, &argv[4]);
  }
  if (strcmp(argv[1], "exec-files") == 0) {
    return command_exec_files(argc - 1, &argv[1]);
  }
  if (strcmp(argv[1], "exec-proxy") == 0) {
    return command_exec_proxy(argc - 1, &argv[1]);
  }
  if (strcmp(argv[1], "snapshot-tree") == 0 && argc == 3) {
    return command_snapshot_tree(argv[2]);
  }
  usage();
  return 64;
}
