import Foundation

/// Pulls a `TestReport` out of the console text `jarvis test` produces. jarvis
/// pipes xcodebuild through **xcbeautify**, so the primary shapes are
/// xcbeautify's (`❌`/`⚠️` diagnostics, `✔`/`✖` test lines, ANSI colour); raw
/// xcodebuild patterns are kept as a fallback. Line-oriented and regex-based —
/// best-effort, not a grammar.
public enum TestOutputParser {

    public static func parse(_ output: String) -> TestReport {
        var report = TestReport()

        let ansi = regex("\u{1B}\\[[0-9;]*m")

        // xcbeautify: shared shapes, applied to the text after the leading symbol.
        let locColMsg = regex(#"^(.+?):(\d+):(\d+): (.*)$"#)   // file:line:col: message
        let locMsg    = regex(#"^(.+?):(\d+): (.*)$"#)          // file:line: message (XCTest assertion)
        let xcbTest   = regex(#"^\[([^\]]+)\] (\S+).*\(([\d.]+) seconds?\)\s*$"#) // [Target] name … (N seconds)

        // raw xcodebuild fallbacks
        let executed   = regex(#"Executed (\d+) tests?, with (\d+) failures?.* in ([\d.]+)(?: \([\d.]+\))? seconds"#)
        let assertion  = regex(#"^(.+):(\d+): error: -\[([\w.]+) (\w+)\] : (.*)$"#)
        let failedCase = regex(#"Test Case '-\[([\w.]+) (\w+)\]' failed"#)
        let skippedCase = regex(#"Test Case '-\[[\w.]+ \w+\]' skipped"#)
        let stIssue = regex(#"✘ Test "(.+?)" recorded an issue at (.+?):(\d+)"#)
        let stRun   = regex(#"Test run with (\d+) tests? (passed|failed)(?: after ([\d.]+) seconds)?"#)

        var warningSeen = Set<String>()
        var errorSeen = Set<String>()
        var failureIndex: [String: Int] = [:]
        var skippedCount = 0
        var sawSymbolTests = false
        var symbolDuration = 0.0

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = replacingAll(ansi, in: String(rawLine), with: "")
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let head = line.first

            // xcbeautify test result: "✔/✖ [Target] testName on 'device' (0.000 seconds)"
            if head == "✔" || head == "✖" {
                let rest = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if let g = match(xcbTest, rest) {
                    sawSymbolTests = true
                    report.tests = (report.tests ?? 0) + 1
                    symbolDuration += Double(g[3]) ?? 0
                    if head == "✖" {
                        report.failed = (report.failed ?? 0) + 1
                        upsertFailure(&report.failures, &failureIndex,
                                      key: "\(g[1]).\(g[2])", location: nil, message: nil)
                    }
                    continue
                }
            }

            // xcbeautify warning: "⚠️  file:line:col: message"
            if head == "⚠️" || head == "\u{26A0}" {
                let rest = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                let message = (match(locColMsg, rest)?[4] ?? match(locMsg, rest)?[3] ?? rest)
                    .trimmingCharacters(in: .whitespaces)
                report.warningCount += 1
                if warningSeen.insert(message).inserted { report.warnings.append(message) }
                continue
            }

            // xcbeautify: "❌ file:line:col: message" is a build error;
            //             "❌ file:line: message" (no column) is an XCTest assertion.
            if head == "❌" {
                let rest = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if let g = match(locColMsg, rest) {
                    let message = g[4].trimmingCharacters(in: .whitespaces)
                    if errorSeen.insert(message).inserted { report.errors.append(message) }
                } else if let g = match(locMsg, rest) {
                    let location = "\((g[1] as NSString).lastPathComponent):\(g[2])"
                    let message = g[3].trimmingCharacters(in: .whitespaces)
                    let key = report.failures.last?.test ?? message
                    upsertFailure(&report.failures, &failureIndex, key: key, location: location, message: message)
                } else if errorSeen.insert(rest).inserted {
                    report.errors.append(rest)
                }
                continue
            }

            // --- raw xcodebuild fallbacks ---
            if let g = match(assertion, line) {
                upsertFailure(&report.failures, &failureIndex,
                              key: "\(lastComponent(g[3])).\(g[4])",
                              location: "\((g[1] as NSString).lastPathComponent):\(g[2])",
                              message: g[5].trimmingCharacters(in: .whitespaces))
                continue
            }
            if let g = match(stIssue, line) {
                upsertFailure(&report.failures, &failureIndex, key: g[1],
                              location: "\((g[2] as NSString).lastPathComponent):\(g[3])", message: nil)
                continue
            }
            if let g = match(failedCase, line) {
                upsertFailure(&report.failures, &failureIndex,
                              key: "\(lastComponent(g[1])).\(g[2])", location: nil, message: nil)
                continue
            }
            if match(skippedCase, line) != nil {
                skippedCount += 1
                continue
            }
            if !sawSymbolTests, let g = match(executed, line) {
                report.tests = (report.tests ?? 0) + (Int(g[1]) ?? 0)
                report.failed = (report.failed ?? 0) + (Int(g[2]) ?? 0)
                report.duration = (report.duration ?? 0) + (Double(g[3]) ?? 0)
                continue
            }
            if report.tests == nil, let g = match(stRun, line) {
                report.tests = Int(g[1])
                report.duration = Double(g[3])
                continue
            }
            if let r = line.range(of: "error: ") {
                let message = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !message.isEmpty, errorSeen.insert(message).inserted { report.errors.append(message) }
                continue
            }
            if line.contains("** BUILD FAILED **") {
                if errorSeen.insert("build failed").inserted { report.errors.append("build failed") }
                continue
            }
            if let r = line.range(of: "warning: ") {
                let message = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !message.isEmpty {
                    report.warningCount += 1
                    if warningSeen.insert(message).inserted { report.warnings.append(message) }
                }
            }
        }

        if sawSymbolTests, report.duration == nil { report.duration = symbolDuration }
        report.skipped = skippedCount > 0 ? skippedCount : nil
        if report.failed == nil, !report.failures.isEmpty { report.failed = report.failures.count }
        return report
    }

    // MARK: - Helpers

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static func replacingAll(_ re: NSRegularExpression, in string: String, with template: String) -> String {
        re.stringByReplacingMatches(in: string, range: NSRange(string.startIndex..., in: string), withTemplate: template)
    }

    /// All capture groups (index 0 is the whole match), or nil if no match.
    private static func match(_ re: NSRegularExpression, _ line: String) -> [String]? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = re.firstMatch(in: line, range: range) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: line).map { String(line[$0]) } ?? ""
        }
    }

    private static func lastComponent(_ dotted: String) -> String {
        dotted.split(separator: ".").last.map(String.init) ?? dotted
    }

    private static func upsertFailure(
        _ list: inout [TestReport.Failure],
        _ index: inout [String: Int],
        key: String,
        location: String?,
        message: String?
    ) {
        if let i = index[key] {
            let existing = list[i]
            list[i] = TestReport.Failure(
                test: existing.test,
                location: existing.location ?? location,
                message: existing.message ?? message
            )
        } else {
            list.append(TestReport.Failure(test: key, location: location, message: message))
            index[key] = list.count - 1
        }
    }
}
