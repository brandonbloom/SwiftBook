// PNG row filters, in C so they're fast in debug builds too: Swift's unoptimized code is too slow
// for a loop over every byte of a reference.
#ifndef SWIFTBOOK_PNG_FILTERS_H
#define SWIFTBOOK_PNG_FILTERS_H

#include <stddef.h>
#include <stdint.h>

/// Writes `row` filtered with PNG filter `filter` (0 through 4) to `output`, given the unfiltered
/// row above it, and returns the sum of the filtered bytes' absolute values as signed bytes.
size_t swiftbook_png_filter_row(
    uint8_t filter, const uint8_t *row, const uint8_t *above, size_t count, size_t channels,
    uint8_t *output);

/// Reverses PNG filter `filter` on `row` in place, given the unfiltered row above it.
void swiftbook_png_unfilter_row(
    uint8_t filter, uint8_t *row, const uint8_t *above, size_t count, size_t channels);

/// Whether every pixel of 8-bit RGBA `rgba` has alpha 255.
int swiftbook_png_is_opaque(const uint8_t *rgba, size_t pixels);

/// Writes 8-bit RGBA `rgba` to `rgb` without its alpha.
void swiftbook_png_drop_alpha(const uint8_t *rgba, size_t pixels, uint8_t *rgb);

#endif
