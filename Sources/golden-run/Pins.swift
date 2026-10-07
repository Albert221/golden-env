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
    static let kataArchiveSHA256 = "647c7612e6edf789d5e14698c48c99d8bac15ad139ffaa1c8bb7d229f748d181"
    /// `vmlinux.container` is a symlink to this file inside the archive.
    static let kernelPathInArchive = "./opt/kata/share/kata-containers/vmlinux-6.12.28-153"
    static let kernelSHA256 = "67bac9f416af4cdc9b151e4ba4962d6515e0ad7acc53816761cf964aa6af6ea0"
}

/// Where golden-run keeps its state on the host.
enum Paths {
    static let root: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("golden-run")

    static let kernel = root.appendingPathComponent("vmlinux-\(Pins.kernelSHA256.prefix(12))")
    /// ImageStore root: OCI content, initfs, per-run container dirs.
    static let store = root.appendingPathComponent("store")
    /// Keyed by the vminit reference so bumping the pin never reuses a stale initfs.
    static let initfs = store.appendingPathComponent(
        "initfs-\(Pins.vminitReference.split(separator: ":").last!).ext4"
    )
    static let pubCache = root.appendingPathComponent("pub-cache")
}
