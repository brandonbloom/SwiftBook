import Foundation

/// Color math for perceptual comparison.
enum ColorMath {
    /// CIEDE2000 color difference between two sRGB colors (0–255 per channel). Below about 1 is
    /// imperceptible; about 2 is noticeable only on close inspection.
    static func deltaE2000(_ rgb1: (Double, Double, Double), _ rgb2: (Double, Double, Double))
        -> Double
    {
        let (l1, a1, b1) = lab(rgb1)
        let (l2, a2, b2) = lab(rgb2)
        let c1 = (a1 * a1 + b1 * b1).squareRoot()
        let c2 = (a2 * a2 + b2 * b2).squareRoot()
        let cMean = (c1 + c2) / 2
        let cMean7 = pow(cMean, 7)
        let g = 0.5 * (1 - (cMean7 / (cMean7 + pow(25, 7))).squareRoot())
        let a1p = a1 * (1 + g)
        let a2p = a2 * (1 + g)
        let c1p = (a1p * a1p + b1 * b1).squareRoot()
        let c2p = (a2p * a2p + b2 * b2).squareRoot()
        let h1p = hueAngle(b1, a1p)
        let h2p = hueAngle(b2, a2p)

        let deltaL = l2 - l1
        let deltaC = c2p - c1p
        var deltaHue = h2p - h1p
        if c1p * c2p == 0 {
            deltaHue = 0
        } else if deltaHue > 180 {
            deltaHue -= 360
        } else if deltaHue < -180 {
            deltaHue += 360
        }
        let deltaH = 2 * (c1p * c2p).squareRoot() * sin(radians(deltaHue / 2))

        let lMean = (l1 + l2) / 2
        let cMeanP = (c1p + c2p) / 2
        var hMean = h1p + h2p
        if c1p * c2p != 0 {
            if abs(h1p - h2p) <= 180 {
                hMean /= 2
            } else {
                hMean = h1p + h2p < 360 ? (hMean + 360) / 2 : (hMean - 360) / 2
            }
        }
        let t =
            1 - 0.17 * cos(radians(hMean - 30)) + 0.24 * cos(radians(2 * hMean))
            + 0.32 * cos(radians(3 * hMean + 6)) - 0.20 * cos(radians(4 * hMean - 63))
        let deltaTheta = 30 * exp(-pow((hMean - 275) / 25, 2))
        let cMeanP7 = pow(cMeanP, 7)
        let rC = 2 * (cMeanP7 / (cMeanP7 + pow(25, 7))).squareRoot()
        let lOffset = pow(lMean - 50, 2)
        let sL = 1 + 0.015 * lOffset / (20 + lOffset).squareRoot()
        let sC = 1 + 0.045 * cMeanP
        let sH = 1 + 0.015 * cMeanP * t
        let rT = -sin(radians(2 * deltaTheta)) * rC
        let l = deltaL / sL
        let c = deltaC / sC
        let h = deltaH / sH
        return (l * l + c * c + h * h + rT * c * h).squareRoot()
    }

    /// CIE L*a*b* (D65) for an sRGB color.
    static func lab(_ rgb: (Double, Double, Double)) -> (Double, Double, Double) {
        func linear(_ c: Double) -> Double {
            let c = c / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let (r, g, b) = (linear(rgb.0), linear(rgb.1), linear(rgb.2))
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 216 / 24389 ? cbrt(t) : (24389 / 27 * t + 16) / 116 }
        let (fx, fy, fz) = (f(x), f(y), f(z))
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// The YIQ luma of an sRGB color, as pixelmatch uses for anti-aliasing detection.
    @inline(__always) static func luma(_ rgb: (Double, Double, Double)) -> Double {
        rgb.0 * 0.29889531 + rgb.1 * 0.58662247 + rgb.2 * 0.11448223
    }

    private static func hueAngle(_ b: Double, _ a: Double) -> Double {
        guard a != 0 || b != 0 else { return 0 }
        let degrees = atan2(b, a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}
