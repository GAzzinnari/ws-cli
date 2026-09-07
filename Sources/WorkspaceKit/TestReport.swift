import Foundation

/// Structured summary of a `jarvis test` run, extracted from its console output.
public struct TestReport: Sendable {
    public struct Failure: Sendable {
        public let test: String        // "Suite.testName"
        public let location: String?   // "File.swift:88"
        public let message: String?
    }

    public var errors: [String] = []
    public var warnings: [String] = []   // unique messages, in first-seen order
    public var warningCount: Int = 0     // total occurrences
    public var tests: Int?
    public var failed: Int?
    public var skipped: Int?
    public var duration: Double?
    public var failures: [Failure] = []

    /// Whether a test-count line was seen at all (build may have failed first).
    public var ranTests: Bool { tests != nil }

    public init() {}
}
