import Darwin
import Foundation

/// A run's container directory, holding its writable layer and boot log.
///
/// Removed when the run ends, and also when it is interrupted or told to stop, where
/// `defer` never runs. A run that dies anyway (SIGKILL, a crash) leaves it behind for
/// `Store.prune`, which can tell nothing uses it any more because its lock is free.
final class RunDirectory {
    static let parent = Paths.store.appendingPathComponent("containers")
    private static let lockName = "lock"
    private static let signals = [SIGINT, SIGTERM, SIGHUP]

    let url: URL
    private let lock: Int32
    private let signalSources: [any DispatchSourceSignal]

    /// `onInterrupt` runs on a signal, before the directory is removed and the process exits.
    init(id: String, onInterrupt: @escaping @Sendable () -> Void) throws {
        let url = Self.parent.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Held until the process exits, however it exits: the kernel drops it then.
        let lock = open(url.appendingPathComponent(Self.lockName).path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            throw GoldenRunError("cannot lock \(url.path): \(String(cString: strerror(errno)))")
        }
        self.url = url
        self.lock = lock
        signalSources = Self.signals.map { signo in
            signal(signo, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signo, queue: .global())
            source.setEventHandler {
                onInterrupt()
                try? FileManager.default.removeItem(at: url)
                exit(128 + signo)
            }
            source.resume()
            return source
        }
    }

    func remove() {
        for source in signalSources {
            source.cancel()
        }
        for signo in Self.signals {
            signal(signo, SIG_DFL)
        }
        try? FileManager.default.removeItem(at: url)
        close(lock)
    }

    /// Whether no run holds the directory. One without a lock file is from a version
    /// before locks, or from a run that is creating it right now: give those an hour.
    static func isAbandoned(_ url: URL) -> Bool {
        let lock = open(url.appendingPathComponent(lockName).path, O_RDWR | O_CLOEXEC)
        guard lock >= 0 else {
            return age(of: url) > 60 * 60
        }
        defer { close(lock) }
        return flock(lock, LOCK_EX | LOCK_NB) == 0
    }
}

/// Seconds since the file or directory was last modified.
func age(of url: URL) -> TimeInterval {
    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    return -(modified ?? .distantPast).timeIntervalSinceNow
}
