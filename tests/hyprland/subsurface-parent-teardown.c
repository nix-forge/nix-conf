/* Exercise mapped subsurface teardown after its parent wl_surface is gone.
  * Run only through check-subsurface-teardown.sh, which creates a nested
  * compositor.
  */
#define _GNU_SOURCE
#include "xdg-shell-client-protocol.h"
#include "color-management-v1-client-protocol.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
static struct wl_compositor *compositor;
static struct wl_subcompositor *subcompositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm;
static struct wp_color_manager_v1 *color_manager;
static int configured;
static int rendered;
static int description_ready;
static void image_ready(void *data, struct wp_image_description_v1 *description,
                        uint32_t identity) {
  description_ready = 1;
}
static void image_failed(void *data, struct wp_image_description_v1 *description,
                        uint32_t cause, const char *message) {
  description_ready = -1;
}
static const struct wp_image_description_v1_listener image_listener = {
    .ready = image_ready, .failed = image_failed};
static void frame_done(void *data, struct wl_callback *callback,
                        uint32_t time) {
  rendered = 1;
  wl_callback_destroy(callback);
}
static const struct wl_callback_listener frame_listener = {frame_done};
static void ping(void *d, struct xdg_wm_base *w, uint32_t s) {
  xdg_wm_base_pong(w, s);
}
static const struct xdg_wm_base_listener wm_listener = {.ping = ping};
static void global(void *d, struct wl_registry *r, uint32_t n, const char *i,
                    uint32_t v) {
  if (!strcmp(i, "wl_compositor"))
    compositor = wl_registry_bind(r, n, &wl_compositor_interface, 4);
  if (!strcmp(i, "wl_subcompositor"))
    subcompositor = wl_registry_bind(r, n, &wl_subcompositor_interface, 1);
  if (!strcmp(i, "wl_shm"))
    shm = wl_registry_bind(r, n, &wl_shm_interface, 1);
  if (!strcmp(i, "wp_color_manager_v1"))
    color_manager = wl_registry_bind(r, n, &wp_color_manager_v1_interface, 1);
  if (!strcmp(i, "xdg_wm_base")) {
    wm = wl_registry_bind(r, n, &xdg_wm_base_interface, 1);
    xdg_wm_base_add_listener(wm, &wm_listener, NULL);
  }
}
static void removed(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener registry_listener = {global, removed};
static void configure(void *d, struct xdg_surface *s, uint32_t serial) {
  xdg_surface_ack_configure(s, serial);
  configured = 1;
}
static const struct xdg_surface_listener surface_listener = {configure};
static struct wl_buffer *buffer(int size) {
  int fd = memfd_create("hyprland-regression", 0);
  assert(fd >= 0);
  assert(ftruncate(fd, size * size * 4) == 0);
  void *data =
      mmap(NULL, size * size * 4, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  assert(data != MAP_FAILED);
  memset(data, 0xff, size * size * 4);
  struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size * size * 4);
  struct wl_buffer *b = wl_shm_pool_create_buffer(pool, 0, size, size, size * 4,
                                                  WL_SHM_FORMAT_XRGB8888);
  wl_shm_pool_destroy(pool);
  munmap(data, size * size * 4);
  close(fd);
  return b;
}
static void map(struct wl_surface *s, int size) {
  wl_surface_attach(s, buffer(size), 0, 0);
  wl_surface_damage(s, 0, 0, size, size);
  wl_surface_commit(s);
}
int main(int argc, char **argv) {
  struct wl_display *d = wl_display_connect(NULL);
  assert(d);
  struct wl_registry *r = wl_display_get_registry(d);
  wl_registry_add_listener(r, &registry_listener, NULL);
  assert(wl_display_roundtrip(d) >= 0);
  assert(compositor && subcompositor && shm && wm);
  struct wl_surface *root = wl_compositor_create_surface(compositor);
  struct xdg_surface *x = xdg_wm_base_get_xdg_surface(wm, root);
  xdg_surface_add_listener(x, &surface_listener, NULL);
  struct xdg_toplevel *top = xdg_surface_get_toplevel(x);
  xdg_toplevel_set_app_id(top, "hyprland-subsurface-regression");
  wl_surface_commit(root);
  while (!configured)
    assert(wl_display_dispatch(d) >= 0);
  map(root, 200);
  assert(wl_display_roundtrip(d) >= 0);
  struct wl_surface *parent = wl_compositor_create_surface(compositor);
  struct wl_subsurface *p =
      wl_subcompositor_get_subsurface(subcompositor, parent, root);
  wl_subsurface_set_desync(p);
  map(parent, 100);
  struct wl_surface *child = wl_compositor_create_surface(compositor);
  struct wl_subsurface *c =
      wl_subcompositor_get_subsurface(subcompositor, child, parent);
  wl_subsurface_set_desync(c);
  struct wl_callback *frame = wl_surface_frame(child);
  wl_callback_add_listener(frame, &frame_listener, NULL);
  map(child, 50);
  wl_surface_commit(parent);
  wl_surface_commit(root);
  assert(wl_display_roundtrip(d) >= 0);
  while (!rendered)
    assert(wl_display_dispatch(d) >= 0);
  puts("Mapped root, parent, child");
  fflush(stdout);
  if (argc > 1 && !strcmp(argv[1], "disconnect")) {
    wl_display_disconnect(d);
    return 0;
  }
  if (argc > 1 && !strcmp(argv[1], "child-first")) {
    wl_subsurface_destroy(c);
    wl_surface_destroy(child);
    assert(wl_display_roundtrip(d) >= 0);
    wl_subsurface_destroy(p);
    wl_surface_destroy(parent);
    assert(wl_display_roundtrip(d) >= 0);
    wl_display_disconnect(d);
    return 0;
  }
  wl_surface_destroy(parent);
  assert(wl_display_roundtrip(d) >= 0);
  if (argc > 1 && !strcmp(argv[1], "feedback")) {
    assert(color_manager);
    struct wp_color_management_surface_feedback_v1 *feedback =
        wp_color_manager_v1_get_surface_feedback(color_manager, child);
    struct wp_image_description_v1 *description =
        wp_color_management_surface_feedback_v1_get_preferred(feedback);
    wp_image_description_v1_add_listener(description, &image_listener, NULL);
    while (!description_ready)
      assert(wl_display_dispatch(d) >= 0);
    assert(description_ready == 1);
    puts("Preferred color description ready for orphaned child");
    wp_image_description_v1_destroy(description);
    wp_color_management_surface_feedback_v1_destroy(feedback);
  }
  puts("Destroyed intermediate parent; unmapping child");
  fflush(stdout);
  wl_subsurface_destroy(c);
  int result = wl_display_roundtrip(d);
  printf("roundtrip after child teardown: %d\n", result);
  wl_display_disconnect(d);
  return result < 0;
}
