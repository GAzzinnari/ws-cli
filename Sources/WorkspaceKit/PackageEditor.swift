import Foundation

/// Rewrites a `Package.swift` so a set of packages resolve to local checkouts.
///
/// Line-based: each `.dependency(...)` / `.product(...)` is assumed to be on its
/// own line. A line "references" a package when it contains the package name as a
/// substring. At most one rewrite is applied per line.
public enum PackageEditor {

    /// One package to redirect.
    public struct Target: Sendable {
        public let packageName: String   // e.g. "networking"
        public let fullName: String      // e.g. "ios-networking"
        public let localPath: String     // absolute path to the local checkout

        public init(packageName: String, fullName: String, localPath: String) {
            self.packageName = packageName
            self.fullName = fullName
            self.localPath = localPath
        }
    }

    /// What changed for one package.
    public struct Report: Sendable {
        public let packageName: String
        public var dependencyLines: Int = 0
        public var productLines: Int = 0

        public var matched: Bool { dependencyLines + productLines > 0 }
    }

    /// The rewritten contents, plus a report per target (in the given order).
    public static func applyLocalOverrides(
        to contents: String,
        targets: [Target]
    ) -> (contents: String, reports: [Report]) {
        var reports = Dictionary(
            targets.map { ($0.packageName, Report(packageName: $0.packageName)) },
            uniquingKeysWith: { first, _ in first }
        )

        var lines = contents.components(separatedBy: "\n") // assume LF, the SwiftPM norm

        for index in lines.indices {
            let line = lines[index]

            for target in targets where line.contains(target.packageName) {
                if line.contains(".dependency(") {
                    lines[index] = rewriteDependencyLine(line, localPath: target.localPath)
                    reports[target.packageName]?.dependencyLines += 1
                    break
                }
                if line.contains(".product("), let rewritten = rewriteProductPackage(line, to: target.fullName) {
                    lines[index] = rewritten
                    reports[target.packageName]?.productLines += 1
                    break
                }
            }
        }

        return (lines.joined(separator: "\n"), targets.map { reports[$0.packageName]! })
    }

    // MARK: - Line rewrites

    /// `<indent>.dependency(…)<,>`  ->  `<indent>.dependency(path: "<localPath>")<,>`
    private static func rewriteDependencyLine(_ line: String, localPath: String) -> String {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let comma = line.trimmingCharacters(in: .whitespaces).hasSuffix(",") ? "," : ""
        return "\(indent).dependency(path: \"\(localPath)\")\(comma)"
    }

    /// Replace the `package: "…"` argument on a `.product(…)` line. Returns nil when
    /// the line has no `package:` argument.
    private static func rewriteProductPackage(_ line: String, to value: String) -> String? {
        guard let range = line.range(of: #"package:\s*"[^"]*""#, options: .regularExpression) else {
            return nil
        }
        return line.replacingCharacters(in: range, with: "package: \"\(value)\"")
    }
}
