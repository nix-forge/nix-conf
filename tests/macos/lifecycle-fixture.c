/* Disposable native process: changing VERSION changes its signed Mach-O UUID. */
#include <unistd.h>
int main(void) {
  volatile int version = VERSION;
  while (version > 0) {
    pause();
  }
  return version;
}
