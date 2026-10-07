import Foundation
import Virtualization

enum Rosetta {
    static var isInstalled: Bool {
        VZLinuxRosettaDirectoryShare.availability == .installed
    }
}
