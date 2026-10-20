#include "SwiftBookPNGFilters.h"

static inline uint8_t paeth(uint8_t a, uint8_t b, uint8_t c) {
    int p = (int)a + (int)b - (int)c;
    int pa = p > a ? p - a : a - p;
    int pb = p > b ? p - b : b - p;
    int pc = p > c ? p - c : c - p;
    return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

size_t swiftbook_png_filter_row(
    uint8_t filter, const uint8_t *row, const uint8_t *above, size_t count, size_t channels,
    uint8_t *output) {
    size_t cost = 0;
    for (size_t x = 0; x < count; x++) {
        uint8_t a = x >= channels ? row[x - channels] : 0;
        uint8_t b = above[x];
        uint8_t c = x >= channels ? above[x - channels] : 0;
        uint8_t predicted;
        switch (filter) {
        case 1: predicted = a; break;
        case 2: predicted = b; break;
        case 3: predicted = (uint8_t)(((unsigned)a + b) / 2); break;
        case 4: predicted = paeth(a, b, c); break;
        default: predicted = 0;
        }
        uint8_t value = (uint8_t)(row[x] - predicted);
        output[x] = value;
        cost += value < 128 ? value : 256 - value;
    }
    return cost;
}

void swiftbook_png_unfilter_row(
    uint8_t filter, uint8_t *row, const uint8_t *above, size_t count, size_t channels) {
    for (size_t x = 0; x < count; x++) {
        uint8_t a = x >= channels ? row[x - channels] : 0;
        uint8_t b = above[x];
        uint8_t c = x >= channels ? above[x - channels] : 0;
        switch (filter) {
        case 1: row[x] = (uint8_t)(row[x] + a); break;
        case 2: row[x] = (uint8_t)(row[x] + b); break;
        case 3: row[x] = (uint8_t)(row[x] + ((unsigned)a + b) / 2); break;
        case 4: row[x] = (uint8_t)(row[x] + paeth(a, b, c)); break;
        default: break;
        }
    }
}

int swiftbook_png_is_opaque(const uint8_t *rgba, size_t pixels) {
    for (size_t i = 0; i < pixels; i++) {
        if (rgba[i * 4 + 3] != 255) return 0;
    }
    return 1;
}

void swiftbook_png_drop_alpha(const uint8_t *rgba, size_t pixels, uint8_t *rgb) {
    for (size_t i = 0; i < pixels; i++) {
        rgb[i * 3] = rgba[i * 4];
        rgb[i * 3 + 1] = rgba[i * 4 + 1];
        rgb[i * 3 + 2] = rgba[i * 4 + 2];
    }
}
