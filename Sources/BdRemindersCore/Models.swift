import Foundation

public struct BeadIssue: Decodable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let description: String?
    public let notes: String?
    public let status: String
    public let priority: PriorityValue
    public let issueType: String?

    public init(
        id: String,
        title: String,
        description: String? = nil,
        notes: String? = nil,
        status: String,
        priority: PriorityValue,
        issueType: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.notes = notes
        self.status = status
        self.priority = priority
        self.issueType = issueType
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case notes
        case status
        case priority
        case issueType = "issue_type"
    }
}

public struct PriorityValue: Decodable, Sendable, Equatable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self.rawValue = intVal
        } else if let strVal = try? container.decode(String.self) {
            let digits = strVal.replacingOccurrences(of: "P", with: "")
            self.rawValue = Int(digits) ?? 2
        } else {
            self.rawValue = 2
        }
    }
}

public struct SyncSummary: Sendable, Equatable {
    public var addedReminders: Int = 0
    public var completedReminders: Int = 0
    public var createdBeads: Int = 0
    public var closedBeads: Int = 0

    public init(
        addedReminders: Int = 0,
        completedReminders: Int = 0,
        createdBeads: Int = 0,
        closedBeads: Int = 0
    ) {
        self.addedReminders = addedReminders
        self.completedReminders = completedReminders
        self.createdBeads = createdBeads
        self.closedBeads = closedBeads
    }
}

// MARK: - Utilities

/// Extracts a bead ID from free text.
///
/// Bracketed IDs (`[prefix-xxxx]`) and bare IDs (`prefix-xxxx`) are only recognised when
/// `prefix` is one of the project's known issue prefixes, so ordinary hyphenated words such as
/// "in-app" or "category-drag" are never mistaken for bead IDs. When no prefixes are known,
/// only the explicit bracketed form is recognised.
public func extractBeadID(from text: String, prefixes: Set<String>) -> String? {
    let idBody = #"[a-zA-Z0-9]+(?:\.[0-9]+)*"#
    let prefixPattern: String
    if prefixes.isEmpty {
        prefixPattern = #"[a-zA-Z0-9_-]+"#
    } else {
        prefixPattern = "(?:" + prefixes.sorted().map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")"
    }

    let bracketPattern = #"\[("# + prefixPattern + "-" + idBody + #")\]"#
    if let id = firstCapture(of: bracketPattern, in: text) {
        return id
    }

    guard !prefixes.isEmpty else { return nil }

    let wordPattern = #"(?<![a-zA-Z0-9_-])("# + prefixPattern + #"-[a-zA-Z0-9]{3,}(?:\.[0-9]+)*)(?![a-zA-Z0-9_-])"#
    return firstCapture(of: wordPattern, in: text)
}

private func firstCapture(of pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[range])
}

/// Derives issue prefixes (everything before the final `-xxxx` segment) from bead IDs.
public func issuePrefixes(fromBeadIDs ids: [String]) -> Set<String> {
    var result = Set<String>()
    for id in ids {
        let base = id.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? id
        if let hyphen = base.lastIndex(of: "-") {
            let prefix = String(base[base.startIndex..<hyphen])
            if !prefix.isEmpty { result.insert(prefix) }
        }
    }
    return result
}

public func eventKitPriority(for priorityValue: Int) -> Int {
    switch priorityValue {
    case 0, 1:
        return 1 // High (!!!)
    case 2:
        return 5 // Medium (!!)
    case 3, 4:
        return 9 // Low (!)
    default:
        return 0 // None
    }
}

public func parseBeadJSON(from output: String) throws -> [BeadIssue] {
    guard let openBracket = output.firstIndex(of: "["),
          let closeBracket = output.lastIndex(of: "]"),
          openBracket < closeBracket else {
        return []
    }
    let jsonSubstring = output[openBracket...closeBracket]
    let jsonData = Data(jsonSubstring.utf8)
    return try JSONDecoder().decode([BeadIssue].self, from: jsonData)
}
