#define _GNU_SOURCE
#include <EGL/egl.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

/* Model vendor thread cleanup at process exit. Owner teardown must dispose of
 * GL resources before exit callbacks; this makes the observed lifetime defect
 * deterministic on Mesa without requiring the desktop's proprietary driver. */
static void release_thread(void) {
  fputs("EGL_LIFETIME_WITNESS: exit thread cleanup\n", stderr);
  eglReleaseThread();
}

EGLBoolean eglMakeCurrent(
    EGLDisplay display, EGLSurface draw, EGLSurface read, EGLContext context) {
  EGLBoolean (*make_current)(EGLDisplay, EGLSurface, EGLSurface, EGLContext) =
      dlsym(RTLD_NEXT, "eglMakeCurrent");
  if (!make_current) {
    fputs("EGL_LIFETIME_ERROR: missing real context binding function\n", stderr);
    _Exit(87);
  }
  EGLBoolean result = make_current(display, draw, read, context);
  static atomic_flag armed = ATOMIC_FLAG_INIT;
  if (result == EGL_TRUE && context != EGL_NO_CONTEXT && !atomic_flag_test_and_set(&armed)) {
    if (atexit(release_thread) != 0) {
      fputs("EGL_LIFETIME_ERROR: cannot register exit thread cleanup\n", stderr);
      _Exit(87);
    }
    fputs("EGL_LIFETIME_WITNESS: armed\n", stderr);
  }
  return result;
}

/* Exercise real GL cleanup, including zero-valued shaders: an unloaded vendor
 * dispatch function is unsafe even when the requested operation is a no-op. */
void glDeleteProgram(unsigned int program) {
  fprintf(stderr, "EGL_LIFETIME_WITNESS: delete program %u\n", program);
  if (eglGetCurrentContext() == EGL_NO_CONTEXT) {
    fputs("EGL_LIFETIME_ERROR: shader deletion without a current context\n", stderr);
    _Exit(86);
  }
  void (*delete_program)(unsigned int) = dlsym(RTLD_NEXT, "glDeleteProgram");
  if (!delete_program) {
    fputs("EGL_LIFETIME_ERROR: missing real shader deletion function\n", stderr);
    _Exit(87);
  }
  delete_program(program);
}
