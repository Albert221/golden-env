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

    var guestPackageDirectory: String {
        let relative = package.path.dropFirst(root.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? Self.guestRoot : "\(Self.guestRoot)/\(relative)"
    }

    /// Per-package home for `.dart_tool`, so the container's package_config.json (which
    /// points into /opt/pub-cache) never replaces the host's and breaks the IDE.
    var dartToolCache: URL {
        let digest = SHA256.hash(data: Data(package.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return Paths.root.appendingPathComponent("dart-tool").appendingPathComponent(String(digest.prefix(16)))
    }

    var shares: [(host: URL, guest: String)] {
        [
            (root, Self.guestRoot),
            (Paths.pubCache, "/opt/pub-cache"),
            (dartToolCache, "\(guestPackageDirectory)/.dart_tool"),
        ]
    }

    static func locate(from start: URL) throws -> Project {
        let start = start.standardizedFileURL.resolvingSymlinksInPath()
        guard let package = ancestor(of: start, containing: "pubspec.yaml") else {
            throw GoldenRunError("no pubspec.yaml in \(start.path) or any parent directory")
        }
        let root = ancestor(of: package, containing: ".git") ?? package
        return Project(root: root, package: package)
    }

    /// Host directories every share needs before the VM can mount them.
    func prepareShares() throws {
        for directory in [Paths.pubCache, dartToolCache, package.appendingPathComponent(".dart_tool")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
