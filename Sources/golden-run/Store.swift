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
