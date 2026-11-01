import ArgumentParser
import Containerization
import ContainerizationOS
import Foundation
import Virtualization

/// What translates the amd64 image's x86-64 code inside the arm64 VM.
enum Emulator: String, CaseIterable, ExpressibleByArgument {
    /// Apple's Rosetta for Linux: fast, but only promised through macOS 27.
    case rosetta
    /// QEMU user-mode emulation: slower, but needs nothing from macOS.
    case qemu

    static var isRosettaInstalled: Bool {
        VZLinuxRosettaDirectoryShare.availability == .installed
    }

    /// Rosetta when it is installed, QEMU otherwise.
    static func resolve(_ requested: Emulator?) -> Emulator {
        if let requested {
            return requested
        }
        if isRosettaInstalled {
            return .rosetta
        }
        log("Rosetta is not installed; emulating x86-64 with QEMU, which is slower.")
        return .qemu
    }

    /// The x86-64 ELF match Containerization registers for Rosetta, with QEMU's flags:
    /// P keeps argv[0], O and C hand QEMU the opened binary and its credentials, and
    /// F opens QEMU itself at registration, so it works inside the container's mounts.
    static var qemuBinfmtEntry: Binfmt.Entry {
        var entry = Binfmt.Entry.amd64()
        entry.flags = "POCF"
        return entry
    }
}
