// A private Wayland surface tree with deterministic colors and buffer geometry.
// The child is deliberately square so a compositor-imposed radius is observable.
#include "xdg-shell-client-protocol.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_subcompositor *subcompositor;
static struct wl_shm *shm;
static struct xdg_wm_base *shell;
static struct wl_surface *parent;
static struct wl_surface *child;
static struct wl_subsurface *subsurface;
static int mode;
static bool configured;

static struct wl_buffer *buffer(int width, int height, uint32_t color) {
  size_t size = (size_t)width * height * 4;
  int fd = memfd_create("rounding-fixture", MFD_CLOEXEC);
  if (fd < 0 || ftruncate(fd, size) < 0) {
    abort();
  }
  uint32_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (pixels == MAP_FAILED) {
    abort();
  }
  for (size_t i = 0; i < size / 4; ++i) {
    pixels[i] = color;
  }
  struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
  struct wl_buffer *result =
      wl_shm_pool_create_buffer(pool, 0, width, height, width * 4, WL_SHM_FORMAT_ARGB8888);
  wl_shm_pool_destroy(pool);
  munmap(pixels, size);
  close(fd);
  return result;
}

static void ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
  (void)data;
  xdg_wm_base_pong(base, serial);
}
static const struct xdg_wm_base_listener shell_listener = {.ping = ping};
static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
    uint32_t version) {
  (void)data;
  (void)version;
  if (!strcmp(interface, "wl_compositor")) {
    compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
  }
  if (!strcmp(interface, "wl_subcompositor")) {
    subcompositor = wl_registry_bind(registry, name, &wl_subcompositor_interface, 1);
  }
  if (!strcmp(interface, "wl_shm")) {
    shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
  }
  if (!strcmp(interface, "xdg_wm_base")) {
    shell = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
  }
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}
static const struct wl_registry_listener registry_listener = {
    .global = global, .global_remove = removed};
static void configure(void *data, struct xdg_surface *surface, uint32_t serial) {
  (void)data;
  xdg_surface_ack_configure(surface, serial);
  if (configured) {
    return;
  }
  configured = true;
  if (mode && mode != 8) {
    child = wl_compositor_create_surface(compositor);
    subsurface = wl_subcompositor_get_subsurface(subcompositor, child, parent);
    int x = mode == 1 ? 100 : mode == 3 ? -20 : mode == 4 ? 450 : 0;
    int y = mode == 1 ? 100 : mode == 3 ? -20 : mode == 4 ? 290 : 0;
    bool full = mode == 2 || mode == 5 || mode == 7 || mode == 9;
    int width = full ? 480 : 120;
    int height = full ? 320 : 60;
    wl_subsurface_set_position(subsurface, x, y);
    if (mode == 9) {
      wl_subsurface_place_below(subsurface, parent);
    }
    uint32_t color = mode == 2 || mode == 9   ? 0xff808080
                     : mode == 5 || mode == 7 ? 0x80404040
                                              : 0xff00ff00;
    struct wl_buffer *b = buffer(width, height, color);
    wl_surface_attach(child, b, 0, 0);
    wl_surface_damage_buffer(child, 0, 0, width, height);
    wl_surface_commit(child);
  }
  uint32_t root_color = mode == 7 ? 0x80404040 : mode == 8 ? 0xc0606060 : 0xff808080;
  struct wl_buffer *b = buffer(480, 320, root_color);
  wl_surface_attach(parent, b, 0, 0);
  wl_surface_damage_buffer(parent, 0, 0, 480, 320);
  wl_surface_commit(parent);
}
static const struct xdg_surface_listener surface_listener = {.configure = configure};
static void toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t width,
    int32_t height, struct wl_array *states) {
  (void)data;
  (void)toplevel;
  (void)width;
  (void)height;
  (void)states;
}
static void toplevel_close(void *data, struct xdg_toplevel *toplevel) {
  (void)data;
  (void)toplevel;
  exit(0);
}
static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure, .close = toplevel_close};
int main(int argc, char **argv) {
  mode = argc > 1 ? atoi(argv[1]) : 0;
  display = wl_display_connect(NULL);
  if (!display) {
    return 1;
  }
  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  wl_display_roundtrip(display);
  if (!compositor || !subcompositor || !shm || !shell) {
    return 2;
  }
  xdg_wm_base_add_listener(shell, &shell_listener, NULL);
  parent = wl_compositor_create_surface(compositor);
  struct xdg_surface *surface = xdg_wm_base_get_xdg_surface(shell, parent);
  xdg_surface_add_listener(surface, &surface_listener, NULL);
  struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(surface);
  xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
  xdg_toplevel_set_app_id(toplevel, "rounding-fixture");
  xdg_toplevel_set_title(toplevel, "Subsurface rounding fixture");
  xdg_toplevel_set_min_size(toplevel, 480, 320);
  xdg_toplevel_set_max_size(toplevel, 480, 320);
  xdg_surface_set_window_geometry(surface, 0, 0, 480, 320);
  wl_surface_commit(parent);
  while (wl_display_dispatch(display) != -1) {
  }
  return 0;
}
