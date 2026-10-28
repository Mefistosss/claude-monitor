import Foundation

/// Sums token usage from Claude Code session logs (`~/.claude/projects/*/*.jsonl`).
enum LogScanner {
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                var input_tokens: Int?
                var output_tokens: Int?
                var cache_creation_input_tokens: Int?
                var cache_read_input_tokens: Int?
            }
            var id: String?
            var usage: Usage?
        }
        var timestamp: String?
        var requestId: String?
        var message: Message?
    }

    static var projectDirs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
        ]
    }

    static func lastHours(_ hours: Double) -> UsageSnapshot.TokenStats {
        let since = Date.now.addingTimeInterval(-hours * 3600)
        let fm = FileManager.default
        let decoder = JSONDecoder()
        var stats = UsageSnapshot.TokenStats()
        // Claude Code writes one line per content block, all sharing the same usage.
        var seen = Set<String>()

        for dir in projectDirs {
            guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                guard let modified, modified >= since, let data = try? Data(contentsOf: url) else { continue }

                for rawLine in data.split(separator: UInt8(ascii: "\n")) {
                    // Cheap prefilter before JSON decoding.
                    guard rawLine.count > 20, rawLine.range(of: Data("\"usage\"".utf8)) != nil,
                          let line = try? decoder.decode(Line.self, from: rawLine),
                          let usage = line.message?.usage,
                          let date = UsageFetcher.parseDate(line.timestamp), date >= since
                    else { continue }

                    let key = "\(line.message?.id ?? "")|\(line.requestId ?? "")"
                    if key != "|" {
                        guard seen.insert(key).inserted else { continue }
                    }
                    stats.input += usage.input_tokens ?? 0
                    stats.output += usage.output_tokens ?? 0
                    stats.cacheCreation += usage.cache_creation_input_tokens ?? 0
                    stats.cacheRead += usage.cache_read_input_tokens ?? 0
                    stats.requests += 1
                }
            }
        }
        return stats
    }
}
