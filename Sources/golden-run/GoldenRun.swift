import ArgumentParser
import Foundation

@main
struct GoldenRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "golden-run",
        abstract: "Run Flutter golden tests inside a pinned linux/amd64 image.",
        subcommands: [Test.self, Doctor.self, Pull.self, Load.self, Shell.self, Exec.self],
        defaultSubcommand: Test.self
    )
}

extension GoldenRun {
    struct Test: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run `flutter test --tags golden` in the image (the default).",
            discussion: """
                Arguments after the options go to `flutter test`, e.g.
                `golden-run --update-goldens` or `golden-run test/widgets/foo_test.dart`.
                """
        )

        @OptionGroup var vm: VMOptions

        @Flag(help: "Run every test, not only those tagged `golden`.")
        var allTests = false

        @Argument(parsing: .captureForPassthrough)
        var passthrough: [String] = []

        func run() async throws {
            var command = ["flutter", "test"]
            let flutterArguments = passthrough.first == "--" ? Array(passthrough.dropFirst()) : passthrough
            let selectsTags = flutterArguments.contains { $0 == "--tags" || $0 == "-t" || $0.hasPrefix("--tags=") }
            if !allTests && !selectsTags {
                command += ["--tags", "golden"]
            }
            try await vm.runInProject(command: command + flutterArguments)
        }
    }

    struct Doctor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check macOS, Rosetta, kernel, vminit and image state."
        )

        func run() async throws {
            let store = try Store()
            let os = ProcessInfo.processInfo.operatingSystemVersion
            print("macOS        \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
            print("rosetta      \(Rosetta.isInstalled ? "installed" : "MISSING (softwareupdate --install-rosetta --agree-to-license)")")
            print("state dir    \(Paths.root.path)")
            print("kernel       \(store.hasKernel ? Paths.kernel.lastPathComponent : "not fetched")")
            print("vminit       \(Pins.vminitReference) (\(store.hasInitfs ? "ready" : "not fetched"))")
        }
    }

    struct Pull: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fetch the kernel, vminit and the image without running anything."
        )

        func run() async throws {
            let store = try Store()
            try await store.ensureKernel()
            try await store.ensureInitfs()
        }
    }

    /// Imports a locally built image without a registry round trip.
    struct Load: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Load an image from an OCI layout directory (docker buildx --output type=oci,tar=false)."
        )

        @Argument(help: "Path to the OCI layout directory.", completion: .directory)
        var directory: String

        func run() async throws {
            let store = try Store()
            let images = try await store.images.load(from: URL(fileURLWithPath: directory))
            for image in images {
                print("\(image.reference) \(image.digest)")
            }
        }
    }

    /// Runs an arbitrary command in any amd64 image. For debugging the VM path itself.
    struct Exec: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a command in an arbitrary linux/amd64 image, with the current directory at /work.",
            shouldDisplay: false
        )

        @Option(name: .shortAndLong, help: "Image reference.")
        var image: String

        @Flag(help: "Disable networking in the VM.")
        var offline = false

        @Argument(parsing: .captureForPassthrough)
        var command: [String] = []

        func run() async throws {
            let command = command.first == "--" ? Array(command.dropFirst()) : command
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let runner = Runner(
                imageReference: image,
                command: command,
                workingDirectory: Project.guestRoot,
                shares: [(cwd, Project.guestRoot)],
                networking: !offline
            )
            try exitWithContainerStatus(await runner.run())
        }
    }

    struct Shell: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open a shell in the image, in the package directory."
        )

        @OptionGroup var vm: VMOptions

        func run() async throws {
            try await vm.runInProject(command: ["bash"])
        }
    }
}

/// Options shared by every command that runs in the project's image.
struct VMOptions: ParsableArguments {
    @Option(help: "Image reference; defaults to image= in golden-env.lock.")
    var image: String?

    @Flag(help: "Disable networking in the VM (pub get must already be satisfied).")
    var offline = false

    @Option(help: "Number of CPUs for the VM.")
    var cpus = 4

    @Option(help: "Memory for the VM in MiB.")
    var memory: UInt64 = 4096

    func runInProject(command: [String]) async throws {
        let project = try Project.locate(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        try project.prepareShares()
        let runner = Runner(
            imageReference: try image ?? project.lockedImage(),
            command: command,
            workingDirectory: project.guestPackageDirectory,
            shares: project.shares,
            networking: !offline,
            cpus: cpus,
            memoryInBytes: memory.mib()
        )
        try exitWithContainerStatus(await runner.run())
    }
}

private func exitWithContainerStatus(_ code: Int32) throws {
    if code != 0 {
        throw ExitCode(code)
    }
}
