import Darwin
import Foundation

/// Small wrappers around `sysctl(3)` for walking the process tree.
public enum ProcessTree {
    /// Executable names that identify the Claude Code process. The native
    /// installer ships a `claude` binary; npm installs run under `node`.
    public static let claudeProcessNames: Set<String> = ["claude", "node"]

    /// How far up the tree `claudePID()` looks. Hooks run under `sh -c`, so the
    /// Claude process is normally the grandparent.
    static let maxAncestorDepth = 6

    public static func parentPID(of pid: Int32) -> Int32? {
        guard let info = kinfo(for: pid) else { return nil }
        return info.kp_eproc.e_ppid
    }

    public static func processName(of pid: Int32) -> String? {
        guard var info = kinfo(for: pid) else { return nil }
        return withUnsafePointer(to: &info.kp_proc.p_comm) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                String(cString: $0)
            }
        }
    }

    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// Walks up from `pid` (exclusive) and returns the first ancestor whose
    /// executable name is in `names`.
    public static func findAncestor(startingAt pid: Int32, named names: Set<String>) -> Int32? {
        var current = pid
        for _ in 0..<maxAncestorDepth {
            guard let parent = parentPID(of: current), parent > 1 else { return nil }
            if let name = processName(of: parent), names.contains(name) { return parent }
            current = parent
        }
        return nil
    }

    /// The PID of the Claude Code process running this hook, falling back to
    /// the direct parent when no recognizable ancestor is found.
    public static func claudePID() -> Int32 {
        findAncestor(startingAt: getpid(), named: claudeProcessNames) ?? getppid()
    }

    // MARK: - Private

    private static func kinfo(for pid: Int32) -> kinfo_proc? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
