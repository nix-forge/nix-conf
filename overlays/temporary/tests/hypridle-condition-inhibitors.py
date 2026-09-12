"""Execute the packaged retry loop with native conditions and D-Bus inhibitors."""

import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - compile and execute a local test
import sys
import tempfile
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index(
    "        for (auto& l : m_sWaylandIdleState.listeners) {",
    source.index("// Check condition_cmd retries"),
)
end = source.index('\n    }\n\n    Debug::log(ERR, "[core] Terminated");', start)
loop = source[start:end]

program = (
    r"""
#include <cstdint>
#include <stdexcept>
#include <vector>
enum { LOG };
namespace Debug { template<typename... T> void log(T...) {} }
struct Listener {
    bool conditionPending = true, ignoreInhibit = false, onTimeoutFired = false;
    int64_t conditionRetryAt = 0, conditionRetry = 5;
    const char *conditionCmd = "condition", *onTimeout = "action";
};
int probes = 0, actions = 0;
bool condition = true;
bool runConditionCmd(const char*) { ++probes; return condition; }
void spawn(const char*) { ++actions; }
struct Daemon {
    struct { std::vector<Listener> listeners{Listener{}}; } m_sWaylandIdleState;
    int m_iInhibitLocks = 0;
    void retry(int64_t now) {
"""
    + loop
    + r"""
    }
};
void require(bool value) { if (!value) throw std::runtime_error("retry regression"); }
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
    require(probes == 1 && actions == 0 && listener.conditionPending);
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
"""
)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    cpp = root / "retry.cc"
    binary = root / "retry"
    cpp.write_text(program)
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - compiler from the build sandbox
        [os.environ.get("CXX", "c++"), "-std=c++17", str(cpp), "-o", str(binary)],
        check=True,
    )
    subprocess.run([str(binary)], check=True)  # ruff: ignore[subprocess-without-shell-equals-true] - compiler and executable from the build sandbox
sys.stdout.write("Hypridle condition/inhibitor regression passed\n")
