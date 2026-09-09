// Exercise Crashpad's public database API without crashing or uploading
// anything.
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>

#include "client/crash_report_database.h"
#include "util/file/file_writer.h"
#include "util/misc/metrics.h"

using Database = crashpad::CrashReportDatabase;

static void require(bool condition, const char* message) {
  if (!condition) {
    std::fprintf(stderr, "test failure: %s\n", message);
    std::exit(1);
  }
}

int main(int argc, char** argv) {
  require(argc == 3,
          "expected database path and pending/completed/denied mode");
  const std::string mode(argv[2]);
  const base::FilePath path(argv[1]);
  auto database = Database::Initialize(path);
  require(database != nullptr, "initialize database");
  std::unique_ptr<Database::NewReport> report;
  require(database->PrepareNewCrashReport(&report) == Database::kNoError,
          "prepare synthetic report");
  const char fixture[] = "synthetic crash-report fixture";
  require(report->Writer()->Write(fixture, sizeof(fixture)), "write fixture");
  crashpad::UUID uuid;
  require(database->FinishedWritingCrashReport(std::move(report), &uuid) ==
              Database::kNoError,
          "finish synthetic report");
  if (mode != "pending") {
    require(
        database->SkipReportUpload(
            uuid, crashpad::Metrics::CrashSkippedReason::kUploadsDisabled) ==
            Database::kNoError,
        "mark report completed without uploading");
  }
  const auto directory =
      path.Append(mode == "pending" ? "pending" : "completed");
  const auto lock = directory.Append(uuid.ToString() + ".lock");
  int fd = -1;
  if (mode == "denied") {
    require(geteuid() != 0, "permission test must run unprivileged");
    require(chmod(directory.value().c_str(), 0500) == 0,
            "make directory read-only");
  } else {
    fd = open(lock.value().c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
              0600);
    require(fd >= 0, "hold exclusive report lock");
  }
  // A separate process attempts the same report while the parent holds its
  // lock.
  const pid_t child = fork();
  require(child >= 0, "fork contender");
  if (child == 0) {
    auto contender = Database::InitializeWithoutCreating(path);
    Database::Report found;
    _exit(contender && contender->LookUpCrashReport(uuid, &found) ==
                            Database::kBusyError
              ? 0
              : 1);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "contender must return busy");
  if (mode == "denied") {
    require(chmod(directory.value().c_str(), 0700) == 0, "restore permissions");
  } else {
    require(access(lock.value().c_str(), F_OK) == 0,
            "contender preserved held lock");
    require(close(fd) == 0 && unlink(lock.value().c_str()) == 0,
            "release lock");
  }
  Database::Report found;
  require(database->LookUpCrashReport(uuid, &found) == Database::kNoError,
          "report remains readable after lock release");
}
