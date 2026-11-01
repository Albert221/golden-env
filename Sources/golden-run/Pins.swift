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

    /// The static arm64 `qemu-x86_64` used when Rosetta is not available: the binfmt image
    /// Docker's buildx installs, pulled for linux/arm64. Only one file of one layer is kept.
    static let qemuImageReference =
        "docker.io/tonistiigi/binfmt:qemu-v10.2.3-68@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0"
    static let qemuLayerDigest = "sha256:3491c3e68b6627d582b29b6d3717b344af3b271eed64c5a784fe3871fbfb9a18"
    static let qemuPathInLayer = "usr/bin/qemu-x86_64"
    static let qemuSHA256 = "ec12fffdcc022364c20aa9d12d5b1f8c22d037526da3f1fb119c5cd92d378130"
}

/// Where golden-run keeps its state on the host.
enum Paths {
    static let root: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("golden-run")

    static let kernel = root.appendingPathComponent("vmlinux-\(Pins.kernelSHA256.prefix(12))")
    /// Holds only `qemu-x86_64`; the whole directory is shared with the VM.
    static let qemu = root.appendingPathComponent("qemu-\(Pins.qemuSHA256.prefix(12))")
    /// ImageStore root: OCI content, initfs, per-run container dirs.
    static let store = root.appendingPathComponent("store")
    /// Keyed by the vminit reference so bumping the pin never reuses a stale initfs.
    static let initfs = store.appendingPathComponent(
        "initfs-\(Pins.vminitReference.split(separator: ":").last!).ext4"
    )
    /// Used only when the host has no pub cache of its own.
    static let privatePubCache = root.appendingPathComponent("pub-cache")

    /// The host's pub cache, shared into the VM so dependencies the developer already
    /// fetched (including git dependencies over their SSH keys) resolve offline there.
    static var hostPubCache: URL {
        if let custom = ProcessInfo.processInfo.environment["PUB_CACHE"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        let standard = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pub-cache")
        return FileManager.default.fileExists(atPath: standard.path) ? standard : privatePubCache
    }
}
