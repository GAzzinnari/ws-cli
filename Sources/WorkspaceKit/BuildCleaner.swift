import Foundation

/// Finds and deletes `.build` directories anywhere under a root.
public struct BuildCleaner: Sendable {
    let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Every directory named `.build` under `root`, sorted by path. Does not
    /// descend into a matched `.build`, and does not follow directory symlinks.
    /// Nothing else is excluded.
    public func find() throws -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return []
        }

        var matches: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true else { continue }

            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent == ".build" {
                matches.append(url)
                enumerator.skipDescendants()
            }
        }

        return matches.sorted { $0.path < $1.path }
    }

    /// Delete each directory. Returns one entry per input; `failure` is nil on success.
    public func remove(_ dirs: [URL]) -> [(url: URL, failure: Error?)] {
        dirs.map { url in
            do {
                try FileManager.default.removeItem(at: url)
                return (url, nil)
            } catch {
                return (url, error)
            }
        }
    }

    /// Best-effort total allocated size of everything under `url`, in bytes.
    /// Entries that can't be read count as zero.
    public static func size(of url: URL) -> Int64 {
        let key: URLResourceKey = .totalFileAllocatedSizeKey
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [key],
            options: []
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            let size = (try? child.resourceValues(forKeys: [key]))?.totalFileAllocatedSize
            total += Int64(size ?? 0)
        }
        return total
    }
}
