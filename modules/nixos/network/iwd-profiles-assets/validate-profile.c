/* Validate native IWD keyfiles through the same ELL parser used by IWD. */
#define _POSIX_C_SOURCE 200809L
#include <ell/ell.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

int main(void) {
  char *data = NULL;
  size_t capacity = 0;
  ssize_t length = getdelim(&data, &capacity, '\0', stdin);
  if (length < 0 || ferror(stdin) || !feof(stdin)) {
    free(data);
    return EXIT_FAILURE;
  }
  struct l_settings *settings = l_settings_new();
  bool valid = l_settings_load_from_data(settings, data, (size_t)length);
  char **groups = valid ? l_settings_get_groups(settings) : NULL;
  valid = valid && groups && groups[0];
  l_strfreev(groups);
  l_settings_free(settings);
  free(data);
  return valid ? EXIT_SUCCESS : EXIT_FAILURE;
}
