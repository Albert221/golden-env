import CryptoKit
import Foundation

/// The Flutter package being tested and the repository it lives in.
struct Project {
    static let guestRoot = "/work"
    static let lockFileName = "golden-env.lock"

    /// Shared at /work: the git root, so path dependencies elsewhere in a monorepo resolve.
    let root: URL
    /// The directory holding pubspec.yaml; tests run here.
    let package: URL
    /// The pub workspace root (`workspace:` in its pubspec) when the package belongs to one.
    /// `pub get` writes the workspace's package_config.json there, not in the package.
    let workspace: URL?

    var guestPackageDirectory: String { guestPath(of: package) }

    /// Every `.dart_tool` a run writes package_config.json into. Each one is redirected to
    /// a per-directory home in the state dir: the container's copy points into
    /// /opt/pub-cache and would break the analyzer, formatter and IDE on the host.
    var dartToolDirectories: [URL] {
        guard let workspace, workspace.path != package.path else { return [package] }
        return [workspace, package]
    }

    var shares: [(host: URL, guest: String)] {
        [(root, Self.guestRoot), (Paths.pubCache, "/opt/pub-cache")]
            + dartToolDirectories.map { (Self.dartToolCache(for: $0), "\(guestPath(of: $0))/.dart_tool") }
    }

    private func guestPath(of directory: URL) -> String {
        let relative = directory.path.dropFirst(root.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? Self.guestRoot : "\(Self.guestRoot)/\(relative)"
    }

    private static func dartToolCache(for directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(directory.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return Paths.root.appendingPathComponent("dart-tool").appendingPathComponent(String(digest.prefix(16)))
    }

    static func locate(from start: URL) throws -> Project {
        let start = start.standardizedFileURL.resolvingSymlinksInPath()
        guard let package = ancestor(of: start, containing: "pubspec.yaml") else {
            throw GoldenRunError("no pubspec.yaml in \(start.path) or any parent directory")
        }
        let root = ancestor(of: package, containing: ".git") ?? package
        return Project(root: root, package: package, workspace: workspaceRoot(of: package, within: root))
    }

    /// Host directories every share needs before the VM can mount them.
    func prepareShares() throws {
        var directories = [Paths.pubCache]
        for directory in dartToolDirectories {
            directories += [Self.dartToolCache(for: directory), directory.appendingPathComponent(".dart_tool")]
        }
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// The nearest pubspec.yaml at or above the package, inside the shared root, that
    /// declares a top-level `workspace:` list.
    private static func workspaceRoot(of package: URL, within root: URL) -> URL? {
        var directory = package
        while true {
            let pubspec = directory.appendingPathComponent("pubspec.yaml")
            if let contents = try? String(contentsOf: pubspec, encoding: .utf8),
                contents.split(whereSeparator: \.isNewline).contains(where: { $0.hasPrefix("workspace:") })
            {
                return directory
            }
            if directory.path == root.path { return nil }
            directory = directory.deletingLastPathComponent()
        }
    }

    /// `image=` from golden-env.lock, looked up from the package up to the repo root.
    func lockedImage() throws -> String {
        var directory = package
        while true {
            let lock = directory.appendingPathComponent(Self.lockFileName)
            if let contents = try? String(contentsOf: lock, encoding: .utf8) {
                guard let image = Self.value(of: "image", in: contents) else {
                    throw GoldenRunError("\(lock.path) has no image= line")
                }
                return image
            }
            if directory.path == root.path { break }
            directory = directory.deletingLastPathComponent()
        }
        throw GoldenRunError("no \(Self.lockFileName) between \(package.path) and \(root.path); pass --image or add one with image=<reference>")
    }

    private static func value(of key: String, in contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            if line[..<equals].trimmingCharacters(in: .whitespaces) == key {
                return line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func ancestor(of start: URL, containing name: String) -> URL? {
        var directory = start
        while true {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }
}
