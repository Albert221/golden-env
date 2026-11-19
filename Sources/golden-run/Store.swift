import Containerization
import ContainerizationError
import CryptoKit
import Foundation

/// The host-side artifacts a run needs: an arm64 kernel, the vminit initfs and images.
struct Store {
    let images: ImageStore

    init() throws {
        try FileManager.default.createDirectory(at: Paths.root, withIntermediateDirectories: true)
        images = try ImageStore(path: Paths.store)
    }

    // MARK: Kernel

    var hasKernel: Bool { FileManager.default.fileExists(atPath: Paths.kernel.path) }

    /// Downloads the Kata release once, extracts the kernel and keeps only that.
    @discardableResult
    func ensureKernel() async throws -> Kernel {
        if !hasKernel {
            try await fetchKernel()
        }
        return Kernel(path: Paths.kernel, platform: .linuxArm)
    }

    private func fetchKernel() async throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("golden-run-kernel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        log("Downloading kernel (Kata 3.17.0, 290 MB once)...")
        let (downloaded, response) = try await URLSession.shared.download(from: Pins.kataArchiveURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GoldenRunError("kernel download failed: \(response)")
        }
        let archive = work.appendingPathComponent("kata.tar.xz")
        try FileManager.default.moveItem(at: downloaded, to: archive)
        try verify(archive, sha256: Pins.kataArchiveSHA256)

        try run("/usr/bin/tar", ["-xJf", archive.path, "-C", work.path, Pins.kernelPathInArchive])
        let extracted = work.appendingPathComponent(Pins.kernelPathInArchive)
        try verify(extracted, sha256: Pins.kernelSHA256)
        try FileManager.default.moveItem(at: extracted, to: Paths.kernel)
        log("Kernel ready: \(Paths.kernel.lastPathComponent)")
    }

    // MARK: vminit

    var hasInitfs: Bool { FileManager.default.fileExists(atPath: Paths.initfs.path) }

    /// Pulls the vminit image and writes it out as an ext4 block file once per version.
    @discardableResult
    func ensureInitfs() async throws -> Mount {
        let mount = Mount.block(format: "ext4", source: Paths.initfs.path, destination: "/", options: ["ro"])
        if hasInitfs {
            return mount
        }
        log("Pulling \(Pins.vminitReference)...")
        let initImage = try await images.getInitImage(reference: Pins.vminitReference)
        _ = try await initImage.initBlock(at: Paths.initfs, for: .linuxArm)
        log("Initfs ready: \(Paths.initfs.lastPathComponent)")
        return mount
    }

    // MARK: Cleanup

    /// Deletes what killed runs and older versions of golden-run left behind: container
    /// directories no run holds, half-unpacked rootfs files, and kernels and initfs files
    /// that are no longer pinned. Also `.dart_tool` copies of packages that haven't run
    /// in a month, which a run rebuilds in seconds. Images and their rootfs stay.
    func prune() {
        var stale = contents(of: RunDirectory.parent).filter {
            $0.lastPathComponent.hasPrefix("golden-") && RunDirectory.isAbandoned($0)
        }
        stale += contents(of: Paths.root).filter {
            $0.lastPathComponent.hasPrefix("vmlinux-") && $0.lastPathComponent != Paths.kernel.lastPathComponent
        }
        stale += contents(of: Paths.store).filter {
            $0.lastPathComponent.hasPrefix("initfs-") && $0.pathExtension == "ext4"
                && $0.lastPathComponent != Paths.initfs.lastPathComponent
        }
        // An unpack writes all the time, so one untouched for an hour was interrupted.
        stale += contents(of: Paths.store.appendingPathComponent("rootfs")).filter {
            $0.pathExtension == "partial" && age(of: $0) > 60 * 60
        }
        // Project.prepareShares marks a package's copy as used on every run.
        stale += contents(of: Paths.dartToolCaches).filter { age(of: $0) > 30 * 24 * 60 * 60 }

        var removed = 0
        var freed: Int64 = 0
        for url in stale {
            let size = allocatedSize(of: url)
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
                freed += size
            }
        }
        if removed > 0 {
            let size = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
            log("Removed \(removed) stale item\(removed == 1 ? "" : "s") from \(Paths.root.path) (\(size))")
        }
    }
}

private func contents(of directory: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
}

/// Bytes on disk, not the apparent size: a writable layer is a 4 GiB sparse file.
private func allocatedSize(of url: URL) -> Int64 {
    let key = URLResourceKey.totalFileAllocatedSizeKey
    let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [key])?.compactMap { $0 as? URL } ?? []
    return ([url] + files).reduce(0) { total, file in
        total + Int64((try? file.resourceValues(forKeys: [key]))?.totalFileAllocatedSize ?? 0)
    }
}

struct GoldenRunError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("golden-run: \(message)\n".utf8))
}

private func verify(_ file: URL, sha256 expected: String) throws {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    guard actual == expected else {
        throw GoldenRunError("sha256 mismatch for \(file.lastPathComponent): expected \(expected), got \(actual)")
    }
}

private func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw GoldenRunError("\(executable) exited with \(process.terminationStatus)")
    }
}
