#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <vector>
enum { LOG };
namespace Debug {
template <typename... T> void log(T...) {}
} // namespace Debug
struct Listener {
  bool conditionPending = true, ignoreInhibit = false, onTimeoutFired = false;
  int64_t conditionRetryAt = 0, conditionRetry = 5;
  const char *conditionCmd = "condition", *onTimeout = "action";
};
int probes = 0, actions = 0;
bool condition = true;
bool runConditionCmd(const char *) {
  ++probes;
  return condition;
}
void spawn(const char *) { ++actions; }
struct Daemon {
  struct {
    std::vector<Listener> listeners{Listener{}};
  } m_sWaylandIdleState;
  int m_iInhibitLocks = 0;
  void retry(int64_t now) {
    // @retryLoop@
  }
};
void require(bool value) {
  if (!value) {
    throw std::runtime_error("retry regression");
  }
}
int main() {
  Daemon daemon;
  auto &listener = daemon.m_sWaylandIdleState.listeners[0];
  condition = false;
  daemon.retry(0);
  require(probes == 1 && actions == 0 && listener.conditionPending);
  // Native work ends after Zen acquires a D-Bus video inhibitor.
  condition = true;
  daemon.m_iInhibitLocks = 1;
  daemon.retry(5);
  if (!(probes == 1 && actions == 0 && listener.conditionPending)) {
    std::fputs("Pending condition bypassed an active inhibitor\n", stderr);
    return 23;
  }
  daemon.m_iInhibitLocks = 0;
  daemon.retry(6);
  require(actions == 1 && listener.onTimeoutFired && !listener.conditionPending);
  // Explicit overrides, such as locked OLED sleep, still run.
  listener = Listener{};
  listener.ignoreInhibit = true;
  daemon.m_iInhibitLocks = 1;
  daemon.retry(7);
  require(actions == 2 && !listener.conditionPending);
}
