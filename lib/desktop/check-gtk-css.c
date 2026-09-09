#include <gtk/gtk.h>

static void parsing_error(GtkCssProvider *provider, GtkCssSection *section,
                          const GError *error, gpointer data) {
    (void)provider;
    (void)section;
    g_printerr("%s\n", error->message);
    if (error->domain != GTK_CSS_PARSER_WARNING)
        *(gboolean *)data = TRUE;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        g_printerr("usage: check-gtk-css FILE\n");
        return 2;
    }
    /* Parsing a stylesheet needs no display or graphical session. */
    gboolean failed = FALSE;
    GtkCssProvider *provider = gtk_css_provider_new();
    g_signal_connect(provider, "parsing-error", G_CALLBACK(parsing_error), &failed);
    gtk_css_provider_load_from_path(provider, argv[1]);
    g_object_unref(provider);
    return failed ? 1 : 0;
}
