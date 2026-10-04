/// A story's stable identity: its module, its file (or `PreviewProvider` type), and its name.
///
/// Identities survive moving a preview within its file. They change when the preview is renamed,
/// moved to another file, or reordered relative to unnamed or same-named previews in its file.
public struct StoryID: Hashable, Sendable, CustomStringConvertible {
    public let module: String
    /// The declaring file's name without extension, or the `PreviewProvider` type's name.
    public let group: String
    /// The display name, made unique within the group.
    public let name: String

    public var description: String { "\(module)/\(group)/\(name)" }

    public init(module: String, group: String, name: String) {
        self.module = module
        self.group = group
        self.name = name
    }

    /// Assigns identities to stories listed in source order.
    ///
    /// Unnamed stories take their group's name, as Xcode's canvas labels them. Within a group, the
    /// second story with a given name gets " 2" appended, the third " 3", and so on. Xcode
    /// disambiguates by line number instead, which changes whenever code moves.
    public static func assign(_ stories: [(module: String, group: String, displayName: String?)])
        -> [StoryID]
    {
        var taken: Set<StoryID> = []
        return stories.map { story in
            let base = story.displayName ?? story.group
            var candidate = StoryID(module: story.module, group: story.group, name: base)
            var ordinal = 1
            while taken.contains(candidate) {
                ordinal += 1
                candidate = StoryID(
                    module: story.module, group: story.group, name: "\(base) \(ordinal)")
            }
            taken.insert(candidate)
            return candidate
        }
    }

    /// The group for a `#Preview` declared in `fileID` (`Module/File.swift`): the file name
    /// without its extension.
    public static func group(forFileID fileID: String) -> String {
        let file = fileID.split(separator: "/").last.map(String.init) ?? fileID
        guard let dot = file.lastIndex(of: "."), dot != file.startIndex else { return file }
        return String(file[..<dot])
    }
}
