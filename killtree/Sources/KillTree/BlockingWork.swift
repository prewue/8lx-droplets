import Foundation

/// Where everything that can wait on something else runs: tools, signals and
/// the wait between them, files. Never the main actor, which draws the notch,
/// and never Swift's cooperative threads, where a blocked thread holds up every
/// other task.
enum BlockingWork {
    private static let queue = DispatchQueue(label: "killtree.work", qos: .utility, attributes: .concurrent)
    /// One at a time, in order: the last state saved is the state on disk.
    private static let files = DispatchQueue(label: "killtree.files", qos: .utility)

    static func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    static func write(_ work: @escaping @Sendable () -> Void) {
        files.async(execute: work)
    }
}
