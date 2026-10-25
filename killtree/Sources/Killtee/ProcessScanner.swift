import Darwin
import Foundation
import Security

/// One process as the kernel and its code signature describe it.
struct RawProcess: Sendable, Hashable {
    let pid: pid_t
    let ppid: pid_t
    let uid: uid_t
    let path: String
    /// Footprint the way Activity Monitor counts memory. 0 for processes of
    /// another user, which the kernel does not report to us.
    let memory: UInt64
    let signature: CodeSignature?
    /// The terminal it runs in ("ttys004"): a command-line tool someone is
    /// using, never an app's leftover.
    let tty: String?
    let startedAt: Date?

    var hasTerminal: Bool { tty != nil }
}

/// What the code signature of an executable says about who made it.
struct CodeSignature: Sendable, Hashable {
    let teamID: String?
    let identifier: String?
    /// "Adobe Inc." out of "Developer ID Application: Adobe Inc. (JQ525L2MZD)".
    let organization: String?
    /// Signed without a certificate (ad hoc, or by a linker): no developer
    /// vouches for it, so it is tied to an app only by other evidence.
    let isAdhoc: Bool

    /// Code Apple ships: an Apple identifier, or Apple's certificate without
    /// a team.
    var isApple: Bool {
        identifier?.hasPrefix("com.apple.") == true || (teamID == nil && !isAdhoc)
    }
}

/// Reads the process table, paths, memory and signatures. Thread-safe; the
/// expensive part (signatures) is cached by path and modification date.
final class ProcessScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var signatures: [String: (stamp: Date?, signature: CodeSignature?)] = [:]
    private var verdicts: [String: Bool?] = [:]

    /// Paths that only ever hold Apple's code.
    static let systemPrefixes = [
        "/System/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/usr/lib/", "/usr/share/",
        "/bin/", "/sbin/", "/Library/Apple/",
        "/private/var/db/", "/Library/Developer/CommandLineTools/"
    ]

    /// Without signatures it is a cheap look at the process table, for the
    /// moment of closing.
    func scan(signatures withSignatures: Bool = true) -> [RawProcess] {
        let me = getuid()
        return Self.allProcesses().compactMap { pid, ppid, uid, tty, startedAt in
            // The user, root, and service accounts (Red Giant runs as
            // _mxappservice). Apple's own daemon accounts sit under 500.
            guard pid > 1, uid == me || uid == 0 || uid >= 500 else { return nil }
            guard let path = Self.path(of: pid), !Self.systemPrefixes.contains(where: path.hasPrefix) else { return nil }
            return RawProcess(
                pid: pid,
                ppid: ppid,
                uid: uid,
                path: path,
                memory: Self.footprint(of: pid),
                signature: withSignatures ? signature(at: path) : nil,
                tty: tty,
                startedAt: startedAt
            )
        }
    }

    /// The signature of the code at `path`, cached until the file changes.
    func signature(at path: String) -> CodeSignature? {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        lock.lock()
        if let cached = signatures[path], cached.stamp == stamp {
            lock.unlock()
            return cached.signature
        }
        lock.unlock()
        let signature = Self.readSignature(at: path)
        lock.lock()
        signatures[path] = (stamp, signature)
        lock.unlock()
        return signature
    }

    /// Every process macOS holds one of `apps` responsible for, the app
    /// itself included, wherever it lives: Safari's Web Content runs from
    /// /System, which `scan()` leaves out.
    func responsibleTrees(for apps: Set<pid_t>) -> [pid_t: [RawProcess]] {
        guard !apps.isEmpty else { return [:] }
        let me = getuid()
        var trees: [pid_t: [RawProcess]] = [:]
        for (pid, ppid, uid, tty, startedAt) in Self.allProcesses() where uid == me {
            let owner = apps.contains(pid) ? pid : Self.responsiblePID(of: pid).flatMap { apps.contains($0) ? $0 : nil }
            guard let owner, let path = Self.path(of: pid) else { continue }
            trees[owner, default: []].append(RawProcess(
                pid: pid,
                ppid: ppid,
                uid: uid,
                path: path,
                memory: Self.footprint(of: pid),
                signature: nil,
                tty: tty,
                startedAt: startedAt
            ))
        }
        return trees
    }

    /// Whether the code running as `pid` still satisfies its own signature:
    /// the binary on disk can be replaced while the old one runs. `nil` when
    /// the system will not say (another user's process).
    func verifyRunning(pid: pid_t, path: String) -> Bool? {
        let key = "\(pid):\(path)"
        lock.lock()
        if let cached = verdicts[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        var verdict: Bool?
        if SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code {
            verdict = SecCodeCheckValidity(code, [], nil) == errSecSuccess
        }
        lock.lock()
        verdicts[key] = verdict
        lock.unlock()
        return verdict
    }

    static func userName(of uid: uid_t) -> String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else { return "uid \(uid)" }
        return String(cString: name)
    }

    // MARK: Kernel

    private static func allProcesses() -> [(pid_t, pid_t, uid_t, String?, Date?)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // The table grows between the two calls; leave room.
        size += size / 8
        let count = size / MemoryLayout<kinfo_proc>.stride
        var table = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, u_int(mib.count), &table, &size, nil, 0) == 0 else { return [] }
        let filled = size / MemoryLayout<kinfo_proc>.stride
        return table.prefix(filled).map { entry in
            let started = entry.kp_proc.p_starttime
            return (
                entry.kp_proc.p_pid,
                entry.kp_eproc.e_ppid,
                entry.kp_eproc.e_ucred.cr_uid,
                ttyName(entry.kp_eproc.e_tdev),
                started.tv_sec > 0 ? Date(timeIntervalSince1970: TimeInterval(started.tv_sec)) : nil
            )
        }
    }

    private static func ttyName(_ device: dev_t) -> String? {
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        return String(cString: name)
    }

    /// The command line, without the executable's directory:
    /// "npm run dev", "postgres -D /opt/homebrew/var/postgresql@18".
    static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // The executable path, then padding.
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while index < size, arguments.count < argc {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        if let first = arguments.first, first.hasPrefix("/") {
            arguments[0] = (first as NSString).lastPathComponent
        }
        return arguments
    }

    /// The folder it runs in, which names the project a server or a tool is for.
    static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty || path == "/" ? nil : path
    }

    /// TCP ports each process listens on, from one `lsof` call.
    static func listeningPorts() -> [pid_t: [Int]] {
        guard let output = Launchctl.run(executable: "/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pn"]).output else {
            return [:]
        }
        var ports: [pid_t: Set<Int>] = [:]
        var current: pid_t = 0
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                current = pid_t(line.dropFirst()) ?? 0
            } else if line.hasPrefix("n"), let colon = line.lastIndex(of: ":"), let port = Int(line[line.index(after: colon)...]) {
                ports[current, default: []].insert(port)
            }
        }
        return ports.mapValues { $0.sorted() }
    }

    static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func footprint(of pid: pid_t) -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : 0
    }

    /// Whether a process still exists.
    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: Responsibility

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    /// The process macOS holds responsible for `pid`, the way Activity Monitor
    /// attributes helpers to their app. A private symbol, so it is optional.
    private static let responsibleFunction: ResponsibleFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    static func responsiblePID(of pid: pid_t) -> pid_t? {
        guard let function = responsibleFunction else { return nil }
        let responsible = function(pid)
        return responsible > 0 && responsible != pid ? responsible : nil
    }

    // MARK: Signatures

    private static func readSignature(at path: String) -> CodeSignature? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else {
            return nil
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else {
            return nil
        }
        let teamID = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String
        var organization: String?
        let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        if let leaf = certificates.first, let summary = SecCertificateCopySubjectSummary(leaf) as String? {
            organization = Self.organization(fromSummary: summary)
        }
        return CodeSignature(teamID: teamID, identifier: identifier, organization: organization, isAdhoc: certificates.isEmpty)
    }

    /// "Developer ID Application: Adobe Inc. (JQ525L2MZD)" → "Adobe".
    static func organization(fromSummary summary: String) -> String? {
        var name = summary
        if let colon = name.firstIndex(of: ":") {
            name = String(name[name.index(after: colon)...])
        }
        if let paren = name.lastIndex(of: "(") {
            name = String(name[..<paren])
        }
        name = name.trimmingCharacters(in: .whitespaces)
        for suffix in [", Inc.", " Inc.", ", Inc", " Inc", ", LLC", " LLC", " Ltd.", " Ltd", " GmbH", " Corporation", " Corp.", " AB", " B.V.", " Limited"] {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
        return name.isEmpty ? nil : name
    }
}

// MARK: - Paths

enum BundlePath {
    /// The outermost `.app` in a path: `/Applications/Figma.app` for every
    /// helper inside Figma.
    static func outermostApp(in path: String) -> String? {
        guard let range = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) else {
            return nil
        }
        return String(path[..<range.upperBound]).trimmingSuffix("/")
    }

    /// The innermost `.app` in a path: `Figma Helper (Renderer).app`.
    static func innermostApp(in path: String) -> String? {
        guard let range = path.range(of: ".app/", options: .backwards) else { return nil }
        return String(path[..<range.upperBound]).trimmingSuffix("/")
    }

    /// The name a person recognises: the bundle's name for an app's main
    /// executable, the file name for anything else.
    static func displayName(for path: String) -> String {
        let executable = (path as NSString).lastPathComponent
        // A binary named by its version (~/.local/share/claude/versions/2.1.310)
        // reads as the tool it is: "claude 2.1.310".
        if executable.allSatisfy({ $0.isNumber || $0 == "." }), executable.contains(".") {
            let components = (path as NSString).pathComponents
            if components.count >= 3 { return "\(components[components.count - 3]) \(executable)" }
        }
        // An app's main executable reads as the app: "Adobe Desktop Service",
        // not "Adobe Desktop Service" twice or a lowercase binary name.
        if let app = innermostApp(in: path), path == app + "/Contents/MacOS/" + executable {
            return ((app as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        return executable
    }

    private static let runtimes: [String] = [
        "node", "nodejs", "bun", "deno", "python", "ruby", "perl", "php", "java", "dotnet", "lua", "Rscript", "julia"
    ]

    /// A language runtime: what it runs is someone's script, whoever signed it.
    static func isRuntime(_ path: String) -> Bool {
        let executable = (path as NSString).lastPathComponent
        return runtimes.contains { executable == $0 || (executable.hasPrefix($0) && executable.dropFirst($0.count).allSatisfy { $0.isNumber || $0 == "." }) }
    }

    /// "com.apple.WebKit.WebContent" → "Web Content".
    static func readableServiceName(_ path: String) -> String {
        let executable = (path as NSString).lastPathComponent
        guard executable.hasPrefix("com."), let last = executable.split(separator: ".").last else {
            return displayName(for: path)
        }
        var name = ""
        for (index, character) in last.enumerated() {
            if index > 0, character.isUppercase, let previous = name.last, previous.isLowercase { name.append(" ") }
            name.append(character)
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Code the system launches on its own schedule: app extensions, system
    /// extensions. Killing them only makes the system start them again.
    static func isSystemManaged(_ path: String) -> Bool {
        path.contains(".appex/") || path.contains(".systemextension/") || path.contains("/Library/SystemExtensions/")
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
