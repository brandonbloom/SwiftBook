import Foundation
import ImageIO

/// A reference that needs a person's review: recorded, re-recorded, failed, or missing.
package struct ReviewEntry: Codable, Hashable, Sendable {
    package enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// A reference recorded where there wasn't one.
        case new
        /// A reference re-recorded over one that differed.
        case changed
        /// A snapshot that doesn't match its reference.
        case failed
        /// A reference that doesn't exist and wasn't recorded.
        case missing
        /// A reference that was removed.
        case deleted
    }

    /// An image to show, with what it is.
    package struct Image: Codable, Hashable, Sendable {
        /// Such as "reference", "actual", or "diff".
        package var role: String
        package var path: String

        package init(role: String, path: String) {
            self.role = role
            self.path = path
        }
    }

    /// The story, as `Module/Group/Name`.
    package var story: String
    /// The variant's file name, such as `mac.light`.
    package var variant: String
    package var kind: Kind
    /// What the test reported.
    package var message: String
    package var images: [Image]
    /// Where the images differ, if they were compared and did.
    package var region: ImageDiff.PixelRect?

    package init(
        story: String, variant: String, kind: Kind, message: String, images: [Image],
        region: ImageDiff.PixelRect? = nil
    ) {
        self.story = story
        self.variant = variant
        self.kind = kind
        self.message = message
        self.images = images
        self.region = region
    }
}

/// An HTML page of references to review.
///
/// A change that covers the same region in several stories, such as a new row in a shared
/// sidebar, comes first as one group: a representative in full, then the others' diff images in
/// a grid. Everything else is grouped by module and group, with each story's variants side by
/// side.
package enum ReviewPage {
    /// Writes the page for `entries` to `url`. `subtitle` goes before the summary of entries.
    /// With `inlineImages`, the page holds its images itself, so it can be sent as one file;
    /// otherwise it links to them relative to `url`.
    package static func write(
        _ entries: [ReviewEntry], to url: URL, subtitle: String? = nil, inlineImages: Bool = false
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(
            html(
                entries, directory: url.deletingLastPathComponent(), subtitle: subtitle,
                inlineImages: inlineImages
            ).utf8
        ).write(to: url, options: .atomic)
    }

    /// The entries that test runs saved under the artifacts root `base`.
    package static func savedEntries(under base: URL) -> [ReviewEntry] {
        var entries: [ReviewEntry] = []
        for kind in ["failures", "recorded"] {
            let enumerator = FileManager.default.enumerator(
                at: base.appending(path: kind), includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "json", let data = try? Data(contentsOf: url),
                    let entry = try? JSONDecoder().decode(ReviewEntry.self, from: data)
                else { continue }
                entries.append(entry)
            }
        }
        return entries
    }

    /// How many stories a change must cover the same region in to be shown as one group.
    static let sharedStories = 3

    /// How much two regions must overlap, as their intersection's share of their union, to
    /// count as the same.
    static let sameRegion = 0.8

    /// Groups of entries that changed the same region, each spanning at least ``sharedStories``
    /// stories, and the entries in no group. Groups and their entries are in story order.
    static func sharedChanges(_ entries: [ReviewEntry]) -> (
        shared: [[ReviewEntry]], rest: [ReviewEntry]
    ) {
        var groups: [(region: ImageDiff.PixelRect, entries: [ReviewEntry])] = []
        var rest: [ReviewEntry] = []
        for entry in entries.sorted(by: { ($0.story, $0.variant) < ($1.story, $1.variant) }) {
            guard let region = entry.region else {
                rest.append(entry)
                continue
            }
            if let index = groups.firstIndex(where: { overlap($0.region, region) >= sameRegion }) {
                groups[index].entries.append(entry)
            } else {
                groups.append((region, [entry]))
            }
        }
        var shared: [[ReviewEntry]] = []
        for group in groups {
            if Set(group.entries.map(\.story)).count >= sharedStories {
                shared.append(group.entries)
            } else {
                rest += group.entries
            }
        }
        return (shared, rest.sorted { ($0.story, $0.variant) < ($1.story, $1.variant) })
    }

    /// The area of `a` and `b`'s intersection over that of their union.
    static func overlap(_ a: ImageDiff.PixelRect, _ b: ImageDiff.PixelRect) -> Double {
        let width = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
        let height = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
        guard width > 0, height > 0 else { return 0 }
        let intersection = Double(width * height)
        return intersection / (Double(a.width * a.height + b.width * b.height) - intersection)
    }

    /// The page for `entries`, with image paths relative to `directory`, or the images
    /// themselves with `inlineImages`.
    static func html(
        _ entries: [ReviewEntry], directory: URL, subtitle: String? = nil,
        inlineImages: Bool = false
    ) -> String {
        let images = Images(directory: directory, inline: inlineImages)
        var out = [header]
        let counts = ReviewEntry.Kind.allCases.compactMap { kind -> String? in
            let count = entries.filter { $0.kind == kind }.count
            return count == 0 ? nil : "\(count) \(label(kind).lowercased())"
        }
        out.append(
            "<h1>SwiftBook review</h1><p class=\"muted\">"
                + (subtitle.map { escape($0) + ": " } ?? "")
                + (counts.isEmpty
                    ? "Nothing to review." : escape(counts.joined(separator: " · "))) + "</p>")
        let (shared, rest) = sharedChanges(entries)
        if !shared.isEmpty { out.append("<h2>Shared changes</h2>") }
        for group in shared {
            let first = group[0]
            let region = first.region!
            out.append(
                "<section class=\"story\"><h3>\(group.count) references in "
                    + "\(Set(group.map(\.story)).count) stories changed within "
                    + "\(region.width)×\(region.height) at (\(region.x), \(region.y))</h3>"
                    + "<div class=\"variants\">"
                    + variant(first, title: "\(first.story) \(first.variant)", images: images)
                    + "</div><div class=\"thumbs\">")
            for entry in group.dropFirst() {
                guard
                    let image = entry.images.first(where: { $0.role == "diff" })
                        ?? entry.images.last
                else { continue }
                out.append(
                    "<figure>\(images.figure(image))<figcaption>"
                        + "\(escape(entry.story)) \(escape(entry.variant))</figcaption></figure>")
            }
            out.append("</div></section>")
        }
        let stories = Dictionary(grouping: rest, by: \.story)
        let groups = Dictionary(grouping: stories.keys) { story in
            story.split(separator: "/").dropLast().joined(separator: "/")
        }
        for group in groups.keys.sorted() {
            out.append("<h2>\(escape(group))</h2>")
            for story in groups[group]!.sorted() {
                let name = story.split(separator: "/").last.map(String.init) ?? story
                out.append(
                    "<section class=\"story\"><h3>\(escape(name))</h3><div class=\"variants\">")
                for entry in stories[story]!.sorted(by: { $0.variant < $1.variant }) {
                    out.append(variant(entry, title: entry.variant, images: images))
                }
                out.append("</div></section>")
            }
        }
        out.append("</body></html>")
        return out.joined(separator: "\n")
    }

    private static func variant(_ entry: ReviewEntry, title: String, images: Images) -> String {
        var out = [
            "<div class=\"variant\"><div class=\"title\"><span class=\"badge \(entry.kind.rawValue)\">"
                + "\(label(entry.kind))</span> \(escape(title))</div>",
            "<pre>\(escape(entry.message))</pre><div class=\"images\">",
        ]
        for image in entry.images {
            out.append(
                "<figure>\(images.figure(image))<figcaption>\(escape(image.role))</figcaption>"
                    + "</figure>")
        }
        out.append("</div></div>")
        return out.joined()
    }

    /// How the page refers to images: linked relative to `directory`, or inlined.
    private struct Images {
        let directory: URL
        let inline: Bool

        /// `image` for a figure: a link to it around it, or, inlined, the image alone.
        func figure(_ image: ReviewEntry.Image) -> String {
            if inline {
                let source =
                    (try? Data(contentsOf: URL(filePath: image.path))).map {
                        Self.inlineSource(png: $0, role: image.role)
                    } ?? image.path
                return "<img src=\"\(source)\">"
            }
            let source =
                relativePath(to: URL(filePath: image.path), from: directory)
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? image.path
            return "<a href=\"\(source)\"><img loading=\"lazy\" src=\"\(source)\"></a>"
        }

        /// The widest an inlined image other than a diff is, in pixels: a phone shows images
        /// side by side at about this size.
        static let inlineWidth = 700

        /// A data URL for `png`, to keep a page that holds its own images small enough to send.
        /// Diff images stay full-size PNGs, so a change of a pixel or two stays visible. Others
        /// are scaled down to ``inlineWidth`` and stored as JPEG.
        static func inlineSource(png: Data, role: String) -> String {
            guard role != "diff",
                let source = CGImageSourceCreateWithData(png as CFData, nil),
                let jpeg = CGImageSourceCreateThumbnailAtIndex(
                    source, 0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: inlineMaxPixelSize(source),
                        kCGImageSourceCreateThumbnailWithTransform: true,
                    ] as CFDictionary
                ).flatMap(jpegData)
            else { return "data:image/png;base64,\(png.base64EncodedString())" }
            return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        }

        /// The longest side that makes the image ``inlineWidth`` wide, or its own size if
        /// it's narrower.
        private static func inlineMaxPixelSize(_ source: CGImageSource) -> Int {
            let properties =
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? inlineWidth
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? inlineWidth
            guard width > inlineWidth else { return max(width, height) }
            return max(inlineWidth, height * inlineWidth / width)
        }

        private static func jpegData(_ image: CGImage) -> Data? {
            let data = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    data, "public.jpeg" as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(
                destination, image,
                [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            return CGImageDestinationFinalize(destination) ? data as Data : nil
        }
    }

    private static func label(_ kind: ReviewEntry.Kind) -> String {
        switch kind {
        case .new: "New"
        case .changed: "Re-recorded"
        case .failed: "Failed"
        case .missing: "Missing"
        case .deleted: "Deleted"
        }
    }

    /// `url`'s path relative to `directory`, or its absolute path if they share no ancestor.
    static func relativePath(to url: URL, from directory: URL) -> String {
        let target = url.standardizedFileURL.pathComponents
        let base = directory.standardizedFileURL.pathComponents
        let common = zip(target, base).prefix { $0 == $1 }.count
        guard common > 1 else { return url.path }
        return (Array(repeating: "..", count: base.count - common) + target.dropFirst(common))
            .joined(separator: "/")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(
            of: "<", with: "&lt;"
        )
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let header = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"><title>SwiftBook Review</title>
        <style>
        :root{--bg:#fafafa;--fg:#1d1d1f;--muted:#6e6e73;--card:#fff;--line:#d2d2d7;
        --new:#1f7a3a;--changed:#9a5b00;--failed:#c0262d;--missing:#6e6e73}
        @media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#1c1c1e;--fg:#f5f5f7;
        --muted:#a1a1a6;--card:#2c2c2e;--line:#3a3a3c;--new:#4cc26a;--changed:#f0a830;--failed:#ff5f57;
        --missing:#a1a1a6}}
        :root[data-theme="dark"]{--bg:#1c1c1e;--fg:#f5f5f7;--muted:#a1a1a6;--card:#2c2c2e;--line:#3a3a3c;
        --new:#4cc26a;--changed:#f0a830;--failed:#ff5f57;--missing:#a1a1a6}
        body{background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,system-ui,sans-serif;
        margin:0 auto;padding:24px 16px;max-width:1600px}
        h1{font-size:24px;margin:0}h2{font-size:18px;margin:32px 0 8px;padding-top:16px;
        border-top:1px solid var(--line)}h3{font-size:14px;margin:0 0 8px}
        .muted{color:var(--muted)}
        .story{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px;
        margin:12px 0}
        .variants{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,520px),1fr));gap:16px}
        .title{font-weight:600;margin-bottom:4px}
        .badge{display:inline-block;font-size:11px;font-weight:600;padding:1px 6px;border-radius:4px;
        color:#fff}.badge.new{background:var(--new)}.badge.changed{background:var(--changed)}
        .badge.failed{background:var(--failed)}.badge.missing,.badge.deleted{background:var(--missing)}
        pre{white-space:pre-wrap;font-size:12px;color:var(--muted);margin:4px 0 8px}
        .images{display:flex;gap:8px;align-items:flex-start}
                .thumbs{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px;
        margin-top:12px}
        figure{margin:0;flex:1;min-width:0}figcaption{font-size:11px;color:var(--muted)}
        img{max-width:100%;border:1px solid var(--line);
        background:repeating-conic-gradient(#ccc 0 25%,#fff 0 50%) 0 0/12px 12px}
        </style></head><body>
        """
}
