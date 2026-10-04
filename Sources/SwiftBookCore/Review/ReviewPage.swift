import Foundation

/// A reference that needs a person's review: recorded, re-recorded, failed, or missing.
public struct ReviewEntry: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
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
    public struct Image: Codable, Hashable, Sendable {
        /// Such as "reference", "actual", or "diff".
        public var role: String
        public var path: String

        public init(role: String, path: String) {
            self.role = role
            self.path = path
        }
    }

    /// The story, as `Module/Group/Name`.
    public var story: String
    /// The variant's file name, such as `mac.light`.
    public var variant: String
    public var kind: Kind
    /// What the test reported.
    public var message: String
    public var images: [Image]

    public init(story: String, variant: String, kind: Kind, message: String, images: [Image]) {
        self.story = story
        self.variant = variant
        self.kind = kind
        self.message = message
        self.images = images
    }
}

/// An HTML page of references to review, grouped by module and group, with each story's variants
/// side by side.
public enum ReviewPage {
    /// Writes the page for `entries` to `url`, linking images relative to it. `subtitle` goes
    /// before the summary of entries.
    public static func write(_ entries: [ReviewEntry], to url: URL, subtitle: String? = nil)
        throws
    {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(
            html(entries, directory: url.deletingLastPathComponent(), subtitle: subtitle).utf8
        ).write(to: url, options: .atomic)
    }

    /// The page for `entries`, with image paths relative to `directory`.
    static func html(_ entries: [ReviewEntry], directory: URL, subtitle: String? = nil) -> String {
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
        let stories = Dictionary(grouping: entries, by: \.story)
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
                    out.append(variant(entry, directory: directory))
                }
                out.append("</div></section>")
            }
        }
        out.append("</body></html>")
        return out.joined(separator: "\n")
    }

    private static func variant(_ entry: ReviewEntry, directory: URL) -> String {
        var out = [
            "<div class=\"variant\"><div class=\"title\"><span class=\"badge \(entry.kind.rawValue)\">"
                + "\(label(entry.kind))</span> \(escape(entry.variant))</div>",
            "<pre>\(escape(entry.message))</pre><div class=\"images\">",
        ]
        for image in entry.images {
            let src =
                relativePath(to: URL(filePath: image.path), from: directory)
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? image.path
            out.append(
                "<figure><a href=\"\(src)\"><img loading=\"lazy\" src=\"\(src)\"></a>"
                    + "<figcaption>\(escape(image.role))</figcaption></figure>")
        }
        out.append("</div></div>")
        return out.joined()
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
        figure{margin:0;flex:1;min-width:0}figcaption{font-size:11px;color:var(--muted)}
        img{max-width:100%;border:1px solid var(--line);
        background:repeating-conic-gradient(#ccc 0 25%,#fff 0 50%) 0 0/12px 12px}
        </style></head><body>
        """
}
