#if os(macOS)
    import AppKit

    /// Composites vibrancy, which the window server applies and `cacheDisplay` ignores.
    ///
    /// Vibrant content, such as sidebar text, symbols, fills, and selection, is drawn in a
    /// placeholder color and carries a color-matrix filter, either a `vibrantColorMatrixSourceOver`
    /// compositing filter or a `vibrantColorMatrix` layer filter. Either way, its real color is the
    /// matrix applied to what's behind it, laid down through the layer's coverage (clipped by its
    /// ancestors) at the matrix's alpha. Captured directly, it draws in the placeholder color.
    ///
    /// Renders match the window server's rendering of an inactive window: the test process is
    /// never the active app, and AppKit draws sidebars in their inactive style there.
    ///
    /// This renders each vibrant layer alone for its coverage, captures the backdrop with them
    /// hidden, composites them in painter's order (colored from the result so far), then redraws
    /// content that was painted above vibrant layers, where they overlap.
    @MainActor enum Vibrancy {
        struct VibrantLayer {
            let layer: CALayer
            /// A 4×5 row-major color matrix: each output channel (red, green, blue, alpha) is a
            /// weighted sum of the backdrop's red, green, blue, and alpha, plus a bias.
            let matrix: [Double]
        }

        /// What a capture must composite itself.
        struct Plan {
            /// Vibrant layers in painter's order, outermost only.
            var vibrant: [VibrantLayer] = []
            /// Layers with content of their own painted after the first vibrant layer.
            var above: [CALayer] = []
        }

        static func plan(for root: CALayer) -> Plan {
            var plan = Plan()
            func visit(_ layer: CALayer) {
                guard layer.opacity > 0, !layer.isHidden else { return }
                if let matrix = colorMatrix(ofVibrant: layer) {
                    plan.vibrant.append(VibrantLayer(layer: layer, matrix: matrix))
                    return
                }
                if !plan.vibrant.isEmpty, hasOwnContent(layer) { plan.above.append(layer) }
                layer.sublayers?.forEach(visit)
            }
            visit(root)
            return plan
        }

        private static func hasOwnContent(_ layer: CALayer) -> Bool {
            layer.contents != nil || (layer.backgroundColor?.alpha ?? 0) > 0
                || layer.borderWidth > 0
        }

        /// The color matrix that colors `layer` from its backdrop, if it's vibrant.
        private static func colorMatrix(ofVibrant layer: CALayer) -> [Double]? {
            if let filter = layer.compositingFilter as? NSObject,
                String(describing: filter).hasPrefix("vibrantColorMatrix")
            {
                return colorMatrix(of: filter)
            }
            if let filters = layer.filters, filters.count == 1,
                let filter = filters[0] as? NSObject,
                String(describing: filter) == "vibrantColorMatrix"
            {
                return colorMatrix(of: filter)
            }
            return nil
        }

        /// A `CAFilter` input, or `nil` if the filter doesn't have it.
        private static func inputValue(_ key: String, of filter: NSObject) -> Any? {
            guard filter.responds(to: NSSelectorFromString("inputKeys")),
                let keys = filter.perform(NSSelectorFromString("inputKeys"))?.takeUnretainedValue()
                    as? [String],
                keys.contains(key)
            else { return nil }
            return filter.value(forKey: key)
        }

        /// A filter's `inputColorMatrix`, a `CAColorMatrix` of 20 floats in an `NSValue`.
        private static func colorMatrix(of filter: NSObject) -> [Double]? {
            guard let value = inputValue("inputColorMatrix", of: filter) as? NSValue else {
                return nil
            }
            var size = 0
            NSGetSizeAndAlignment(value.objCType, &size, nil)
            guard size == 20 * MemoryLayout<Float>.size else { return nil }
            var matrix = [Float](repeating: 0, count: 20)
            matrix.withUnsafeMutableBytes { value.getValue($0.baseAddress!, size: size) }
            return matrix.map(Double.init)
        }

        /// A plan's layers rendered alone, ready to composite over a backdrop.
        struct Rendered {
            var vibrant: [(region: Region, matrix: [Double])] = []
            var above: [Region] = []
        }

        /// Renders each layer of `plan` alone, as it is now, into regions of a capture of `root`
        /// that's `width`×`height` pixels.
        ///
        /// Render before capturing the backdrop: drawing a view into a bitmap can replace its
        /// layers, such as a search field's glass, until the window next displays.
        static func render(
            _ plan: Plan, root: CALayer, width: Int, height: Int, scale: Double
        ) -> Rendered {
            let size = (width: width, height: height)
            var rendered = Rendered()
            for vibrant in plan.vibrant {
                rendered.vibrant.append(
                    (render(vibrant.layer, alone: root, in: size, scale: scale), vibrant.matrix))
            }
            for layer in plan.above {
                rendered.above.append(
                    withSublayersHidden(layer) {
                        render(layer, alone: root, in: size, scale: scale)
                    })
            }
            return rendered
        }

        /// Composites `rendered` over `backdrop`, a capture with the vibrant layers hidden.
        static func composite(_ rendered: Rendered, over backdrop: Bitmap) -> Bitmap {
            var result = backdrop
            let width = backdrop.width
            var covered = [Bool](repeating: false, count: width * backdrop.height)
            for (source, m) in rendered.vibrant {
                source.forEachPixel(width: width) { index, sourceOffset in
                    let coverage = Double(source.pixels[sourceOffset + 3]) / 255
                    guard coverage > 0 else { return }
                    covered[index] = true
                    let offset = index * 4
                    let r = Double(result.pixels[offset]) / 255
                    let g = Double(result.pixels[offset + 1]) / 255
                    let b = Double(result.pixels[offset + 2]) / 255
                    // The backdrop is opaque, so its alpha is 1.
                    func channel(_ row: Int) -> Double {
                        var sum = m[row * 5 + 4] + m[row * 5 + 3]
                        sum += m[row * 5] * r
                        sum += m[row * 5 + 1] * g
                        sum += m[row * 5 + 2] * b
                        return min(max(sum, 0), 1)
                    }
                    let alpha = coverage * channel(3)
                    result.blend(channel(0), channel(1), channel(2), alpha: alpha, at: offset)
                }
            }
            // Content painted above vibrant layers was painted over by them; draw it again there.
            for source in rendered.above {
                source.forEachPixel(width: width) { index, sourceOffset in
                    guard covered[index] else { return }
                    let alpha = Double(source.pixels[sourceOffset + 3]) / 255
                    guard alpha > 0 else { return }
                    let r = Double(source.pixels[sourceOffset]) / 255 / alpha
                    let g = Double(source.pixels[sourceOffset + 1]) / 255 / alpha
                    let b = Double(source.pixels[sourceOffset + 2]) / 255 / alpha
                    result.blend(r, g, b, alpha: alpha, at: index * 4)
                }
            }
            return result
        }

        private static func withSublayersHidden<T>(_ layer: CALayer, _ body: () -> T) -> T {
            let sublayers = (layer.sublayers ?? []).filter { !$0.isHidden }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for sublayer in sublayers { sublayer.isHidden = true }
            defer {
                for sublayer in sublayers { sublayer.isHidden = false }
                CATransaction.commit()
            }
            return body()
        }

        /// A layer rendered alone: the pixels of a region of the capture.
        struct Region {
            /// The region's origin and size in capture pixels, rows top to bottom.
            let x: Int
            let y: Int
            let width: Int
            let height: Int
            /// Premultiplied RGBA.
            var pixels: [UInt8]

            /// Calls `body` with each pixel's index in the capture and offset in ``pixels``.
            func forEachPixel(width captureWidth: Int, _ body: (Int, Int) -> Void) {
                for row in 0..<height {
                    for column in 0..<width {
                        body((y + row) * captureWidth + x + column, (row * width + column) * 4)
                    }
                }
            }
        }

        /// Renders `layer` alone, positioned as within `root`, clipped by its ancestors, into the
        /// region of a `capture`-sized bitmap that it covers.
        private static func render(
            _ layer: CALayer, alone root: CALayer, in capture: (width: Int, height: Int),
            scale: Double
        )
            -> Region
        {
            let frame = root.convert(layer.bounds, from: layer)
            let x = max(Int((frame.minX * scale).rounded(.down)), 0)
            let y = max(Int((frame.minY * scale).rounded(.down)), 0)
            let maxX = min(Int((frame.maxX * scale).rounded(.up)), capture.width)
            let maxY = min(Int((frame.maxY * scale).rounded(.up)), capture.height)
            var region = Region(
                x: x, y: y, width: max(maxX - x, 0), height: max(maxY - y, 0), pixels: [])
            guard region.width > 0, region.height > 0 else { return region }
            region.pixels = [UInt8](repeating: 0, count: region.width * region.height * 4)
            region.pixels.withUnsafeMutableBytes { buffer in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: region.width, height: region.height,
                        bitsPerComponent: 8, bytesPerRow: region.width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                // Map root coordinates, which run top down (a hosting view is flipped), to the
                // region's pixels, whose rows also run top down.
                context.translateBy(x: CGFloat(-x), y: CGFloat(region.height + y))
                context.scaleBy(x: scale, y: -scale)
                if !root.isGeometryFlipped {
                    context.translateBy(x: 0, y: root.bounds.height)
                    context.scaleBy(x: 1, y: -1)
                }
                // Clip to ancestors that clip their content, such as a selection's rounded rect.
                var ancestor = layer.superlayer
                while let clipping = ancestor, clipping !== root {
                    if clipping.masksToBounds {
                        context.addPath(
                            CGPath(
                                roundedRect: root.convert(clipping.bounds, from: clipping),
                                cornerWidth: clipping.cornerRadius,
                                cornerHeight: clipping.cornerRadius,
                                transform: nil))
                        context.clip()
                    }
                    ancestor = clipping.superlayer
                }
                context.translateBy(x: frame.minX, y: frame.minY)
                if layer.isGeometryFlipped == root.isGeometryFlipped {
                    context.translateBy(x: 0, y: frame.height)
                    context.scaleBy(x: 1, y: -1)
                }
                layer.render(in: context)
            }
            return region
        }
    }
#endif
