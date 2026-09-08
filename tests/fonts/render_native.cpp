// Exercise native Linux text layout, including fallback and color emoji.
#include <QGuiApplication>
#include <QImage>
#include <QPainter>
#include <QTextLayout>
#include <QGlyphRun>
#include <pango/pangocairo.h>
#include <iostream>

bool colorAtTextSize(const QImage &image) {
    int top = image.height(), bottom = -1;
    for (int y = 0; y < image.height(); ++y)
        for (int x = 0; x < image.width(); ++x) {
            auto pixel = image.pixelColor(x, y);
            if (pixel.red() - pixel.blue() > 40) {
                top = std::min(top, y);
                bottom = std::max(bottom, y);
            }
        }
    // At 38 px, a 109 px bitmap must be scaled, not drawn at its native strike.
    return bottom - top >= 10 && bottom - top <= 60;
}

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    if (argc != 2) return 2;
    const QString directory = QString::fromLocal8Bit(argv[1]);
    const char *sample = "0123456789 café العربية 日本語 😀";
    QImage image(1000, 180, QImage::Format_ARGB32);
    image.fill(Qt::white);
    QPainter painter(&image);
    QFont font("sans-serif");
    font.setPixelSize(38);
    QTextLayout layout(QString::fromUtf8(sample), font);
    layout.beginLayout();
    auto line = layout.createLine();
    line.setLineWidth(980);
    layout.endLayout();
    for (const auto &run : layout.glyphRuns()) {
        for (auto glyph : run.glyphIndexes()) {
            if (glyph == 0) {
                std::cerr << "Qt selected a missing glyph\n";
                return 1;
            }
        }
        std::cout << "Qt: " << run.rawFont().familyName().toStdString() << '\n';
    }
    layout.draw(&painter, QPointF(10, 15));
    painter.end();
    if (!colorAtTextSize(image) || !image.save(directory + "/qt.png")) return 1;

    cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1000, 180);
    cairo_t *cr = cairo_create(surface);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_paint(cr);
    cairo_set_source_rgb(cr, 0, 0, 0);
    cairo_move_to(cr, 10, 15);
    PangoLayout *pl = pango_cairo_create_layout(cr);
    PangoFontDescription *description = pango_font_description_from_string("sans-serif 28");
    pango_layout_set_font_description(pl, description);
    pango_layout_set_text(pl, sample, -1);
    if (pango_layout_get_unknown_glyphs_count(pl) != 0) {
        std::cerr << "Pango selected missing glyphs\n";
        return 1;
    }
    pango_cairo_show_layout(cr, pl);
    auto status = cairo_surface_write_to_png(surface, (directory + "/pango.png").toLocal8Bit().constData());
    pango_font_description_free(description);
    g_object_unref(pl);
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
    if (status != CAIRO_STATUS_SUCCESS) return 1;
    QImage pangoImage(directory + "/pango.png");
    return colorAtTextSize(pangoImage) ? 0 : 1;
}
