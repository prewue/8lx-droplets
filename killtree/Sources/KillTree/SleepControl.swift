import Foundation
import IOKit.pwr_mgt

/// The two ways K*llTree keeps the Mac awake.
///
/// Keep Awake is a power assertion, the same one `caffeinate -i` takes. It
/// belongs to this process, so the system lets it go if Droppy ends, however
/// it ends.
///
/// Lid Closed Mode is `pmset disablesleep`, a system setting that outlives
/// the droplet, Droppy and a restart. So the setting itself is the only truth
/// here: it is read back from `pmset` rather than remembered, and a droplet
/// that comes back to it still on shows it on.
@MainActor
final class SleepControl: ObservableObject {
    @Published private(set) var keepsAwake = false
    @Published private(set) var lidClosed = false
    /// What Lid Closed Mode is being changed to, while the password is asked.
    @Published private(set) var lidWanted: Bool?
    /// The setting on this Mac as last read, demo data or not: it decides
    /// whether the droplet may be removed, and a removal cannot wait for a tool.
    private(set) var systemLidClosed = false
    /// The system rule that lets the switch work without a password is there.
    @Published private(set) var skipsPassword = false
    /// What that rule is being changed to, while the password is asked.
    @Published private(set) var ruleWanted: Bool?

    private var assertion: IOPMAssertionID?
    private var isDemo = false
    private var isReading = false

    var isActive: Bool { keepsAwake || lidClosed }

    // MARK: Modes

    /// The made-up Mac's switches only change the demo.
    func enterDemo() {
        releaseAssertion()
        isDemo = true
        keepsAwake = false
        lidClosed = false
        lidWanted = nil
        refresh()
    }

    func enterLive(then: ((_ lidClosed: Bool) -> Void)? = nil) {
        isDemo = false
        keepsAwake = false
        lidClosed = false
        refresh(then: then)
    }

    /// The droplet is going away: the assertion goes with it. Lid Closed Mode
    /// stays: turning it off asks for a password, and the next activation
    /// shows it on.
    func stop() {
        releaseAssertion()
        keepsAwake = false
    }

    /// Reads Lid Closed Mode back, so a change made elsewhere shows here.
    func refresh(then: ((_ lidClosed: Bool) -> Void)? = nil) {
        guard lidWanted == nil, !isReading else { return }
        isReading = true
        Task { @MainActor in
            let (isOn, hasRule) = await BlockingWork.run { (SleepSystem.isSleepDisabled(), SleepSystem.hasPasswordRule) }
            self.isReading = false
            self.systemLidClosed = isOn
            if self.ruleWanted == nil, !self.isDemo { self.skipsPassword = hasRule }
            // A change that started during the read reads back on its own.
            if self.lidWanted == nil, !self.isDemo {
                self.lidClosed = isOn
                then?(isOn)
            }
        }
    }

    // MARK: Switches

    /// Returns whether the Mac now does what was asked.
    @discardableResult
    func setKeepsAwake(_ on: Bool) -> Bool {
        if isDemo {
            keepsAwake = on
            return true
        }
        if on {
            guard assertion == nil else { return true }
            guard let id = SleepSystem.takeAssertion() else { return false }
            assertion = id
        } else {
            releaseAssertion()
        }
        keepsAwake = on
        return true
    }

    /// Asks for the password and changes the setting. `isDone` says whether
    /// the setting now is what was asked; refused, the switch goes back.
    func setLidClosed(_ on: Bool, isDone: @escaping (Bool) -> Void) {
        guard lidWanted == nil else { return }
        lidWanted = on
        Task { @MainActor in
            let isOn: Bool
            if self.isDemo {
                try? await Task.sleep(for: .milliseconds(400))
                isOn = on
            } else {
                isOn = await BlockingWork.run {
                    SleepSystem.setSleepDisabled(on)
                    return SleepSystem.isSleepDisabled()
                }
                self.systemLidClosed = isOn
            }
            self.lidClosed = isOn
            self.lidWanted = nil
            isDone(isOn == on)
        }
    }

    /// Adds or takes away the system rule, behind one password. `isDone` says
    /// whether it is now what was asked; refused, the switch goes back.
    func setSkipsPassword(_ on: Bool, isDone: @escaping (Bool) -> Void) {
        guard ruleWanted == nil else { return }
        ruleWanted = on
        Task { @MainActor in
            let hasRule: Bool
            if self.isDemo {
                try? await Task.sleep(for: .milliseconds(400))
                hasRule = on
            } else {
                hasRule = await BlockingWork.run {
                    _ = on ? SleepSystem.installPasswordRule() : SleepSystem.removePasswordRule()
                    return SleepSystem.hasPasswordRule
                }
            }
            self.skipsPassword = hasRule
            self.ruleWanted = nil
            isDone(hasRule == on)
        }
    }

    private func releaseAssertion() {
        guard let assertion else { return }
        IOPMAssertionRelease(assertion)
        self.assertion = nil
    }
}

/// The blocking part, off the main thread.
enum SleepSystem {
    private static let pmset = "/usr/bin/pmset"

    static func takeAssertion() -> IOPMAssertionID? {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            "PreventUserIdleSystemSleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "K*llTree: Keep Awake" as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    /// `pmset -g` has a `SleepDisabled` line while the setting is on; without
    /// one it is off.
    static func isSleepDisabled() -> Bool {
        let output = Launchctl.run(executable: pmset, ["-g"]).output ?? ""
        return isSleepDisabled(pmsetOutput: output)
    }

    static func isSleepDisabled(pmsetOutput: String) -> Bool {
        pmsetOutput.split(separator: "\n").contains { line in
            let words = line.split(whereSeparator: \.isWhitespace)
            return words.first == "SleepDisabled" && words.last == "1"
        }
    }

    /// Through the rule when it is there. Otherwise, or if the rule stopped
    /// working, one administrator prompt. Refused, nothing changes.
    @discardableResult
    static func setSleepDisabled(_ on: Bool) -> Bool {
        let value = on ? "1" : "0"
        if hasPasswordRule,
           Launchctl.run(executable: "/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", value], timeout: Launchctl.changeDeadline).status == 0 {
            return true
        }
        return Launchctl.runAsAdministrator(["\(pmset) -a disablesleep \(value)"])
    }

    // MARK: The password rule

    private static let ruleFolder = "/etc/sudoers.d"
    private static let ruleName = "killtree-lid-closed"

    static var hasPasswordRule: Bool {
        FileManager.default.fileExists(atPath: "\(ruleFolder)/\(ruleName)")
    }

    /// Allows one person these two commands, exactly, and nothing else. `nil`
    /// for a name the rule's syntax has no safe way to hold.
    static func ruleLine(user: String) -> String? {
        guard !user.isEmpty, !user.hasPrefix("-"),
              user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else { return nil }
        return "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
    }

    /// Writes the rule to a hidden file, which sudo ignores, and moves it into
    /// place only once `visudo` has accepted it: a bad file in that folder
    /// would break `sudo` for the whole Mac.
    static func installCommand(user: String, folder: String = ruleFolder, setsOwner: Bool = true) -> String? {
        guard let line = ruleLine(user: user) else { return nil }
        var steps = [
            "t=$(/usr/bin/mktemp \(folder)/.\(ruleName).XXXXXX)",
            "/usr/bin/printf '%s\\n' '\(line)' > \"$t\""
        ]
        if setsOwner { steps.append("/usr/sbin/chown root:wheel \"$t\"") }
        steps += [
            "/bin/chmod 440 \"$t\"",
            "/usr/sbin/visudo -cf \"$t\" >/dev/null",
            "/bin/mv -f \"$t\" \(folder)/\(ruleName)"
        ]
        return "umask 077; " + steps.joined(separator: " && ") + " || { /bin/rm -f \"$t\"; exit 1; }"
    }

    @discardableResult
    static func installPasswordRule() -> Bool {
        guard let command = installCommand(user: NSUserName()) else { return false }
        return Launchctl.runAsAdministrator([command])
    }

    @discardableResult
    static func removePasswordRule() -> Bool {
        Launchctl.runAsAdministrator(["/bin/rm -f \(ruleFolder)/\(ruleName)"])
    }
}
