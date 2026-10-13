#include <CoreServices/CoreServices.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char canary[PATH_MAX];
static unsigned removals;

static void receive(ConstFSEventStreamRef stream, void *context, size_t count, void *paths,
    const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[]) {
  (void)stream;
  (void)context;
  (void)ids;
  char **names = paths;
  for (size_t i = 0; i < count; ++i) {
    if (strcmp(names[i], canary) == 0 && (flags[i] & kFSEventStreamEventFlagItemRemoved) &&
        (flags[i] & kFSEventStreamEventFlagItemIsFile)) {
      ++removals;
    }
  }
}

int main(void) {
  const char *temporary = getenv("TMPDIR");
  if (!temporary) {
    temporary = "/tmp";
  }
  char directory[PATH_MAX];
  if (snprintf(directory, sizeof(directory), "%s/deploy-fsevents-XXXXXX", temporary) >=
          (int)sizeof(directory) ||
      !mkdtemp(directory)) {
    return 2;
  }
  char resolved[PATH_MAX];
  if (!realpath(directory, resolved) ||
      snprintf(canary, sizeof(canary), "%s/canary", resolved) >= (int)sizeof(canary)) {
    return 2;
  }
  CFStringRef path = CFStringCreateWithCString(NULL, resolved, kCFStringEncodingUTF8);
  const void *value = path;
  CFArrayRef paths = CFArrayCreate(NULL, &value, 1, &kCFTypeArrayCallBacks);
  FSEventStreamContext context = {0, NULL, NULL, NULL, NULL};
  FSEventStreamRef stream =
      FSEventStreamCreate(NULL, receive, &context, paths, kFSEventStreamEventIdSinceNow, 0.0,
          kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);
  bool started = false;
  if (stream) {
    FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    started = FSEventStreamStart(stream);
  }
  int fd = open(canary, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (fd < 0 || close(fd) != 0 || unlink(canary) != 0) {
    return 2;
  }
  double deadline = CFAbsoluteTimeGetCurrent() + 10.0;
  while (CFAbsoluteTimeGetCurrent() < deadline && !removals) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
  }
  static const char json_format[] =
      "{\"validDirectory\":true,\"createdStream\":%s,\"startedStream\":%s,"
      "\"removedCanary\":true,\"removeCallbacks\":%u,\"windowSeconds\":10}\n";
  printf(json_format, stream ? "true" : "false", started ? "true" : "false", removals);
  if (stream) {
    if (started) {
      FSEventStreamStop(stream);
    }
    FSEventStreamInvalidate(stream);
    FSEventStreamRelease(stream);
  }
  CFRelease(paths);
  CFRelease(path);
  if (rmdir(directory) != 0) {
    return 2;
  }
  return 0;
}
