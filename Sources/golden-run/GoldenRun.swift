import ArgumentParser
import Foundation

@main
struct GoldenRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "golden-run",
        abstract: "Run Flutter golden tests inside a pinned linux/amd64 image.",
        subcommands: [Test.self, Doctor.self, Pull.self, Shell.self],
        defaultSubcommand: Test.self
    )
}

struct NotImplemented: Error, CustomStringConvertible {
    let what: String
    var description: String { "\(what) is not implemented yet" }
}

extension GoldenRun {
    struct Test: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run `flutter test --tags golden` in the image (the default)."
        )

        @Flag(help: "Disable networking in the VM.")
        var offline = false

        @Option(help: "Number of CPUs for the VM.")
        var cpus = 4

        @Option(help: "Memory for the VM in MiB.")
        var memory: UInt64 = 4096

        /// Passed through to `flutter test`, e.g. `--update-goldens` or a test path.
        @Argument(parsing: .captureForPassthrough)
        var passthrough: [String] = []

        func run() async throws {
            throw NotImplemented(what: "test")
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

    struct Shell: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open a shell in the image for debugging."
        )

        func run() async throws {
            throw NotImplemented(what: "shell")
        }
    }
}
