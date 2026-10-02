// Anti-aliasing detection ported from pixelmatch (https://github.com/mapbox/pixelmatch), which
// implements "Anti-aliased Pixel and Intensity Slope Detector" by V. Vysniauskas, 2009.
//
// ISC License
//
// Copyright (c) 2025, Mapbox
//
// Permission to use, copy, modify, and/or distribute this software for any purpose with or
// without fee is hereby granted, provided that the above copyright notice and this permission
// notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS
// SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
// AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
// NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
// OF THIS SOFTWARE.

enum Antialiasing {
    /// Whether the differing pixel at (`x`, `y`) is likely anti-aliasing in either image: it sits on
    /// an intensity slope between a darkest and a brightest neighbor, and one of those neighbors
    /// lies in a flat region in both images.
    static func isAntialiased(x: Int, y: Int, _ a: Bitmap, _ b: Bitmap) -> Bool {
        isAntialiased(x: x, y: y, in: a, other: b) || isAntialiased(x: x, y: y, in: b, other: a)
    }

    private static func isAntialiased(x x1: Int, y y1: Int, in image: Bitmap, other: Bitmap) -> Bool
    {
        let width = image.width
        let height = image.height
        let x0 = max(x1 - 1, 0)
        let y0 = max(y1 - 1, 0)
        let x2 = min(x1 + 1, width - 1)
        let y2 = min(y1 + 1, height - 1)
        let center = y1 * width + x1
        let centerLuma = ColorMath.luma(image.rgb(center))
        var zeroes = x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2 ? 1 : 0
        var darkest = (delta: 0.0, x: 0, y: 0)
        var brightest = (delta: 0.0, x: 0, y: 0)

        for x in x0...x2 {
            for y in y0...y2 where x != x1 || y != y1 {
                let neighbor = y * width + x
                // Brightness delta from the center to this neighbor.
                let delta =
                    image.samePixel(center, neighbor)
                    ? 0 : centerLuma - ColorMath.luma(image.rgb(neighbor))
                if delta == 0 {
                    zeroes += 1
                    // More than two equal neighbors: a flat region, not an anti-aliased edge.
                    if zeroes > 2 { return false }
                } else if delta < darkest.delta {
                    darkest = (delta, x, y)
                } else if delta > brightest.delta {
                    brightest = (delta, x, y)
                }
            }
        }
        // No darker or no brighter neighbor: not on a slope.
        guard darkest.delta != 0, brightest.delta != 0 else { return false }
        return
            (hasManySiblings(darkest.x, darkest.y, image)
            && hasManySiblings(darkest.x, darkest.y, other))
            || (hasManySiblings(brightest.x, brightest.y, image)
                && hasManySiblings(brightest.x, brightest.y, other))
    }

    /// Whether the pixel at (`x1`, `y1`) has at least three identical neighbors.
    private static func hasManySiblings(_ x1: Int, _ y1: Int, _ image: Bitmap) -> Bool {
        let width = image.width
        let x0 = max(x1 - 1, 0)
        let y0 = max(y1 - 1, 0)
        let x2 = min(x1 + 1, width - 1)
        let y2 = min(y1 + 1, image.height - 1)
        let center = y1 * width + x1
        var zeroes = x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2 ? 1 : 0
        for x in x0...x2 {
            for y in y0...y2 where x != x1 || y != y1 {
                if image.samePixel(center, y * width + x) {
                    zeroes += 1
                    if zeroes > 2 { return true }
                }
            }
        }
        return false
    }
}
