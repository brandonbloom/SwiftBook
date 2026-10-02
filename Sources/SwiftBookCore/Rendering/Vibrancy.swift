#if os(macOS)
    import AppKit

    /// Composites vibrancy, which the window server applies and `cacheDisplay` ignores.
    ///
    /// Vibrant content (sidebar text and symbols, for example) is a layer whose
    /// `vibrantColorMatrixSourceOver` compositing filter colors it from what's behind it: the
    /// result is the filter's color matrix applied to the backdrop, masked by the layer's own
    /// coverage. Captured directly, that content draws in its placeholder color, black. This
    /// captures the backdrop with vibrant layers hidden, renders each vibrant layer alone for its
    /// coverage, and composites the matrix-colored backdrop through it.
    @MainActor enum Vibrancy {
        struct VibrantLayer {
            let layer: CALayer
            /// A 4×5 row-major color matrix: each output channel is a weighted sum of the
            /// backdrop's red, green, blue, and alpha, plus a bias.
            let matrix: [Float]
        }

        /// Vibrant layers whose color comes from the backdrop, outermost first.
        static func layers(in root: CALayer) -> [VibrantLayer] {
            var found: [VibrantLayer] = []
            func visit(_ layer: CALayer) {
                if layer.opacity > 0, !layer.isHidden, let matrix = backdropColorMatrix(of: layer) {
                    found.append(VibrantLayer(layer: layer, matrix: matrix))
                    return
                }
                layer.sublayers?.forEach(visit)
            }
            visit(root)
            return found
        }

        /// Whether `layer` is vibrant content this composites, rather than a vibrant background.
        static func colorsFromBackdrop(_ layer: CALayer) -> Bool {
            backdropColorMatrix(of: layer) != nil
        }

        /// The color matrix of a vibrancy filter that colors content from the backdrop. Filters
        /// marked backdrop-aware tint the layer's own background instead; those draw acceptably
        /// without the filter, so they're left alone.
        private static func backdropColorMatrix(of layer: CALayer) -> [Float]? {
            guard let filter = layer.compositingFilter as? NSObject,
                String(describing: filter).hasPrefix("vibrantColorMatrix"),
                filter.responds(to: NSSelectorFromString("inputKeys")),
                let keys = filter.perform(NSSelectorFromString("inputKeys"))?.takeUnretainedValue()
                    as? [String],
                keys.contains("inputColorMatrix"),
                let value = filter.value(forKey: "inputColorMatrix") as? NSValue
            else { return nil }
            if keys.contains("inputBackdropAware"),
                (filter.value(forKey: "inputBackdropAware") as? Bool) == true
            {
                return nil
            }
            // A CAColorMatrix: 20 floats.
            var size = 0
            NSGetSizeAndAlignment(value.objCType, &size, nil)
            guard size == 20 * MemoryLayout<Float>.size else { return nil }
            var matrix = [Float](repeating: 0, count: 20)
            matrix.withUnsafeMutableBytes { value.getValue($0.baseAddress!, size: size) }
            return matrix
        }

        /// Composites `layers` over `backdrop`, a capture of `root` with those layers hidden.
        static func composite(
            _ layers: [VibrantLayer], over backdrop: Bitmap, root: CALayer, scale: Double
        ) -> Bitmap {
            var result = backdrop
            for vibrant in layers {
                let coverage = render(
                    vibrant.layer, alone: root, width: backdrop.width, height: backdrop.height,
                    scale: scale)
                let m = vibrant.matrix.map(Double.init)
                for index in 0..<(backdrop.width * backdrop.height) {
                    let alpha = Double(coverage[index * 4 + 3]) / 255
                    guard alpha > 0 else { continue }
                    let offset = index * 4
                    let r = Double(backdrop.pixels[offset]) / 255
                    let g = Double(backdrop.pixels[offset + 1]) / 255
                    let b = Double(backdrop.pixels[offset + 2]) / 255
                    for channel in 0..<3 {
                        let row = channel * 5
                        // The backdrop is opaque, so its alpha term is the weight itself.
                        var sum = m[row] * r
                        sum += m[row + 1] * g
                        sum += m[row + 2] * b
                        sum += m[row + 3] + m[row + 4]
                        let tinted = min(max(sum, 0), 1)
                        let under = Double(result.pixels[offset + channel]) / 255
                        result.pixels[offset + channel] = UInt8(
                            (tinted * alpha + under * (1 - alpha)) * 255 + 0.5)
                    }
                }
            }
            return result
        }

        /// Renders `layer` alone, positioned as within `root`, into an RGBA bitmap the size of the
        /// capture. Only its alpha is used.
        private static func render(
            _ layer: CALayer, alone root: CALayer, width: Int, height: Int, scale: Double
        )
            -> [UInt8]
        {
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let frame = root.convert(layer.bounds, from: layer)
            pixels.withUnsafeMutableBytes { buffer in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                // The bitmap's rows run top to bottom, like the capture. The root's coordinates
                // run top down when it's flipped, as a hosting view's are.
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: scale, y: -scale)
                if !root.isGeometryFlipped {
                    context.translateBy(x: 0, y: root.bounds.height)
                    context.scaleBy(x: 1, y: -1)
                }
                context.translateBy(x: frame.minX, y: frame.minY)
                if layer.isGeometryFlipped == root.isGeometryFlipped {
                    context.translateBy(x: 0, y: frame.height)
                    context.scaleBy(x: 1, y: -1)
                }
                layer.render(in: context)
            }
            return pixels
        }
    }
#endif
