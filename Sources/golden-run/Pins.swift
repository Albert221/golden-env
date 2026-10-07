import Foundation

/// Every external input golden-run depends on, pinned in one place.
enum Pins {
    /// Must match the Containerization package version in Package.swift.
    static let vminitReference = "ghcr.io/apple/containerization/vminit:0.48.0"

    /// Kata Containers static release that ships an arm64 `vmlinux.container`
    /// with virtio built in. Same source Containerization's Makefile uses.
    static let kataArchiveURL = URL(
        string: "https://github.com/kata-containers/kata-containers/releases/download/3.17.0/kata-static-3.17.0-arm64.tar.xz"
    )!
    /// Filled in once the archive has been downloaded and hashed.
    static let kernelSHA256: String? = nil
}

/// Where golden-run keeps its state on the host.
enum Paths {
    static let root: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("golden-run")

    static let kernel = root.appendingPathComponent("vmlinux")
    /// ImageStore root: OCI content, initfs.ext4, per-run container dirs.
    static let store = root.appendingPathComponent("store")
    static let pubCache = root.appendingPathComponent("pub-cache")
}
