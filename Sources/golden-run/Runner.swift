import Containerization
import ContainerizationError
import ContainerizationEXT4
import ContainerizationOCI
import ContainerizationOS
import Foundation
import SystemPackage

/// Boots a linux/amd64 image in a throwaway micro VM under Rosetta.
///
/// ContainerManager is not used for the container itself: it unpacks and reads the
/// image config for `Platform.current` (arm64), which an amd64-only image lacks.
struct Runner {
    static let platform = Platform(arch: "amd64", os: "linux")

    var imageReference: String
    /// Replaces the image's CMD; its ENTRYPOINT still runs first, as with `docker run`.
    var command: [String] = []
    var workingDirectory: String?
    /// Mounted in order, so a share may sit inside an earlier one.
    var shares: [(host: URL, guest: String)] = []
    /// Defaults to the host user, so files written into shares stay the developer's.
    var user = ContainerizationOCI.User(uid: getuid(), gid: getgid())
    var networking = true
    var cpus = 4
    var memoryInBytes: UInt64 = 4.gib()

    func run() async throws -> Int32 {
        let store = try Store()
        let kernel = try await store.ensureKernel()
        let initfs = try await store.ensureInitfs()
        let image = try await Self.image(imageReference, in: store.images)

        let id = "golden-\(UUID().uuidString.prefix(8).lowercased())"
        let containerDir = Paths.store.appendingPathComponent("containers").appendingPathComponent(id)
        try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerDir) }

        // Shared read-only lower layer per image digest, fresh writable upper layer per run:
        // nothing a run writes outside the shares survives into the next one.
        let rootfs = try await Self.rootfs(for: image)
        let writable = try Self.emptyFilesystem(at: containerDir.appendingPathComponent("writable.ext4"), size: 4.gib())

        var network = networking ? try VmnetNetwork() : nil
        defer { try? network?.releaseInterface(id) }
        let interface = try network?.createInterface(id)

        let imageConfig = try await image.config(for: Self.platform).config
        let terminal = try? Terminal.current
        let vmm = VZVirtualMachineManager(kernel: kernel, initialFilesystem: initfs, rosetta: true)

        let container = try LinuxContainer(
            id,
            rootfs: rootfs,
            writableLayer: writable,
            vmm: vmm,
            vm: VMResources(cpus: cpus, memoryInBytes: memoryInBytes + VMResources.guestMemoryOverhead)
        ) { config in
            if let imageConfig {
                config.process = .init(from: imageConfig)
            }
            if !command.isEmpty {
                config.process.arguments = (imageConfig?.entrypoint ?? []) + command
            }
            if let workingDirectory {
                config.process.workingDirectory = workingDirectory
            }
            config.process.user = user
            if let terminal {
                config.process.setTerminalIO(terminal: terminal)
            } else {
                config.process.stdout = StandardStream(handle: .standardOutput)
                config.process.stderr = StandardStream(handle: .standardError)
            }
            config.cpus = cpus
            config.memoryInBytes = memoryInBytes
            if let interface {
                config.interfaces = [interface]
                if let gateway = interface.ipv4Gateway {
                    config.dns = DNS(nameservers: [gateway.description])
                }
            }
            for share in shares {
                config.mounts.append(.share(source: share.host.path, destination: share.guest))
            }
            config.bootLog = .file(path: containerDir.appendingPathComponent("boot.log"))
        }

        if let terminal {
            try terminal.setraw()
        }
        defer { terminal?.tryReset() }

        try await container.create()
        try await container.start()
        if let terminal {
            try? await container.resize(to: try terminal.size)
        }
        let status = try await container.wait()
        try await container.stop()
        return status.exitCode
    }

    /// Looks the image up locally and pulls only its amd64 manifest when missing.
    static func image(_ reference: String, in images: ImageStore) async throws -> Containerization.Image {
        // Docker-style shorthand: `debian:bookworm-slim` means docker.io/library/debian.
        var ref = try Reference.parse(reference)
        if ref.domain == nil {
            ref = try Reference.parse("docker.io/\(reference)")
        }
        ref.normalize()
        // `name:tag@digest` (the lockfile form) must resolve by digest; the tag is only
        // for humans. Reference.description and pull would both prefer the tag.
        let normalized = ref.digest.map { "\(ref.name)@\($0)" } ?? ref.description
        do {
            return try await images.get(reference: normalized)
        } catch let error as ContainerizationError where error.code == .notFound {
            log("Pulling \(normalized) (linux/amd64)...")
            return try await images.pull(reference: normalized, platform: platform)
        }
    }

    private static func rootfs(for image: Containerization.Image) async throws -> Containerization.Mount {
        // Keyed by the config digest, which identifies the filesystem: the same layers
        // loaded or pulled under another name or index must not unpack again.
        let config = try await image.manifest(for: platform).config.digest
        let directory = Paths.store.appendingPathComponent("rootfs")
        let path = directory.appendingPathComponent("\(config.replacingOccurrences(of: ":", with: "-")).ext4")
        if !FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            log("Unpacking \(image.reference) into an ext4 rootfs (once per image)...")
            // Unpack beside the final name and rename, so an interrupted unpack is never reused.
            let partial = directory.appendingPathComponent("\(UUID().uuidString).partial")
            defer { try? FileManager.default.removeItem(at: partial) }
            _ = try await EXT4Unpacker(capacityInBytes: 16.gib()).unpack(image, for: platform, at: partial)
            try FileManager.default.moveItem(at: partial, to: path)
        }
        return .block(format: "ext4", source: path.path, destination: "/", options: ["ro"])
    }

    private static func emptyFilesystem(at path: URL, size: UInt64) throws -> Containerization.Mount {
        let formatter = try EXT4.Formatter(FilePath(path.path), minDiskSize: size)
        try formatter.close()
        return .block(format: "ext4", source: path.path, destination: "/", options: [])
    }
}

/// Non-TTY stdout/stderr for CI and pipes.
private struct StandardStream: Writer {
    let handle: FileHandle
    func write(_ data: Data) throws { try handle.write(contentsOf: data) }
    func close() throws {}
}
