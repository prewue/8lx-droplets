/// Counts as whole phrases, one per case: "1 process", "2 processes". A word
/// glued to an ending cannot be translated.
enum Phrases {
    static func processes(_ count: Int) -> String { count == 1 ? "1 process" : "\(count) processes" }
    static func jobs(_ count: Int) -> String { count == 1 ? "1 launchd job" : "\(count) launchd jobs" }
    static func services(_ count: Int) -> String { count == 1 ? "1 system service" : "\(count) system services" }
    static func sessions(_ count: Int) -> String { count == 1 ? "1 terminal session" : "\(count) terminal sessions" }
    static func appsInBackground(_ count: Int) -> String { count == 1 ? "1 app in the background" : "\(count) apps in the background" }
    static func processesEnded(_ count: Int) -> String { count == 1 ? "1 process ended" : "\(count) processes ended" }
    static func processesWillBeKilled(_ count: Int) -> String { count == 1 ? "1 process will be killed" : "\(count) processes will be killed" }
    static func jobsWillBeTurnedOff(_ count: Int) -> String { count == 1 ? "1 launchd job will be turned off" : "\(count) launchd jobs will be turned off" }
    static func jobsTurnedOff(_ count: Int) -> String { count == 1 ? "1 launchd job turned off" : "\(count) launchd jobs turned off" }
    static func jobsStopped(_ count: Int) -> String { count == 1 ? "1 launchd job stopped" : "\(count) launchd jobs stopped" }
    static func servicesLeftRunning(_ count: Int) -> String { count == 1 ? "1 system service was left running." : "\(count) system services were left running." }
    static func startupJobs(_ count: Int, labels: String) -> String { count == 1 ? "1 launchd job starts at login: \(labels)" : "\(count) launchd jobs start at login: \(labels)" }
}
