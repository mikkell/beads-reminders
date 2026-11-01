import Foundation
import EventKit

public struct SyncConfiguration: Sendable {
    public let projectDirectory: String
    public let targetListName: String
    public let isDryRun: Bool

    public init(
        projectDirectory: String = FileManager.default.currentDirectoryPath,
        targetListName: String? = nil,
        isDryRun: Bool = false
    ) {
        self.projectDirectory = projectDirectory
        let folder = URL(fileURLWithPath: projectDirectory).lastPathComponent
        self.targetListName = targetListName ?? folder
        self.isDryRun = isDryRun
    }
}

private final class UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) {
        self.value = value
    }
}

public final class SyncEngine: @unchecked Sendable {
    private let config: SyncConfiguration
    private let executor: CommandExecuting
    private let store: EKEventStore
    private let bdPath: String

    public init(
        config: SyncConfiguration,
        executor: CommandExecuting = ProcessCommandExecutor(),
        store: EKEventStore = EKEventStore()
    ) {
        self.config = config
        self.executor = executor
        self.store = store
        self.bdPath = findBdPath(executor: executor)
    }

    @discardableResult
    public func run() async throws -> SyncSummary {
        print("🔄 Starting Beads <-> Apple Reminders two-way sync...")
        print("   Project: \(config.projectDirectory)")
        print("   Reminders List: \(config.targetListName)")
        if config.isDryRun {
            print("⚠️  DRY RUN MODE: No modifications will be saved.\n")
        }

        // 1. Request access
        let granted = try await store.requestFullAccessToReminders()
        guard granted else {
            throw SyncError.accessDenied
        }

        // 2. Locate list
        let calendars = store.calendars(for: .reminder)
        guard let targetCalendar = calendars.first(where: { $0.title.lowercased() == config.targetListName.lowercased() }) else {
            let available = calendars.map { $0.title }.joined(separator: ", ")
            throw SyncError.listNotFound(requested: config.targetListName, available: available)
        }

        // 3. Fetch reminders using Sendable box
        let remindersPredicate = store.predicateForReminders(in: [targetCalendar])
        let boxedReminders: UncheckedSendableBox<[EKReminder]> = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: remindersPredicate) { reminders in
                continuation.resume(returning: UncheckedSendableBox(reminders ?? []))
            }
        }
        let existingReminders = boxedReminders.value

        // 4. Fetch active beads
        let bdListResult = try executor.run(bdPath, arguments: ["list", "--status", "open,in_progress", "--limit", "0", "--json"], currentDirectory: config.projectDirectory)
        guard bdListResult.exitCode == 0 else {
            throw SyncError.commandFailed("bd list failed: \(bdListResult.stderr)")
        }

        let activeBeads = try parseBeadJSON(from: bdListResult.stdout)
        var activeBeadsMap = Dictionary(uniqueKeysWithValues: activeBeads.map { ($0.id, $0) })

        // Known issue prefixes, so hyphenated words (e.g. "in-app") are not mistaken for bead IDs
        var prefixes = issuePrefixes(fromBeadIDs: activeBeads.map { $0.id })
        if let prefixRes = try? executor.run(bdPath, arguments: ["config", "get", "issue_prefix"], currentDirectory: config.projectDirectory),
           prefixRes.exitCode == 0 {
            let configured = prefixRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !configured.isEmpty && !configured.contains(where: \.isWhitespace) {
                prefixes.insert(configured)
            }
        }

        var summary = SyncSummary()
        var handledBeadIDs = Set<String>()

        // 5. Scan Existing Reminders
        for reminder in existingReminders {
            let reminderTitle = reminder.title ?? ""
            let beadID = extractBeadID(from: reminderTitle, prefixes: prefixes) ?? (reminder.notes.flatMap { extractBeadID(from: $0, prefixes: prefixes) })

            if let beadID = beadID {
                handledBeadIDs.insert(beadID)

                if reminder.isCompleted {
                    // Closed in Reminders -> Close in Beads
                    if let _ = activeBeadsMap[beadID] {
                        print("  ✓ Closing bead [\(beadID)] (checked off in Apple Reminders)...")
                        if !config.isDryRun {
                            let closeRes = try executor.run(bdPath, arguments: ["close", beadID, "--reason", "Completed via Apple Reminders"], currentDirectory: config.projectDirectory)
                            if closeRes.exitCode == 0 {
                                summary.closedBeads += 1
                                activeBeadsMap.removeValue(forKey: beadID)
                            } else {
                                print("    ⚠️ Failed to close bead \(beadID): \(closeRes.stderr)")
                            }
                        } else {
                            summary.closedBeads += 1
                        }
                    }
                } else {
                    // Uncompleted in Reminders, verify if closed in Beads
                    if activeBeadsMap[beadID] == nil {
                        let showRes = try? executor.run(bdPath, arguments: ["show", beadID, "--json"], currentDirectory: config.projectDirectory)
                        if let showRes = showRes, showRes.exitCode == 0,
                           let beadIssues = try? parseBeadJSON(from: showRes.stdout),
                           let bead = beadIssues.first, bead.status == "closed" {
                            print("  ✓ Marking reminder [\(beadID)] as completed (closed in beads)...")
                            if !config.isDryRun {
                                reminder.isCompleted = true
                                reminder.completionDate = Date()
                                try store.save(reminder, commit: false)
                            }
                            summary.completedReminders += 1
                        }
                    }
                }
            } else if !reminder.isCompleted {
                // New reminder added on iPhone without Bead ID -> Create Bead!
                let cleanTitle = reminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanTitle.isEmpty {
                    print("  + Creating new bead from iPhone reminder: \"\(cleanTitle)\"...")
                    if !config.isDryRun {
                        var createArgs = ["create", cleanTitle, "--type", "task", "--silent"]
                        if let notes = reminder.notes, !notes.isEmpty {
                            createArgs += ["--description", notes]
                        }
                        let createRes = try executor.run(bdPath, arguments: createArgs, currentDirectory: config.projectDirectory)
                        if createRes.exitCode == 0 {
                            let newID = createRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                            print("    -> Assigned ID: \(newID)")
                            reminder.title = "[\(newID)] \(cleanTitle)"
                            try store.save(reminder, commit: false)
                            summary.createdBeads += 1
                            handledBeadIDs.insert(newID)
                        } else {
                            print("    ⚠️ Failed to create bead: \(createRes.stderr)")
                        }
                    } else {
                        summary.createdBeads += 1
                    }
                }
            }
        }

        // 6. Push Active Beads -> Reminders
        for (id, bead) in activeBeadsMap {
            if !handledBeadIDs.contains(id) {
                print("  + Adding reminder for active bead [\(id)] \(bead.title)...")
                if !config.isDryRun {
                    let newReminder = EKReminder(eventStore: store)
                    newReminder.calendar = targetCalendar
                    newReminder.title = "[\(id)] \(bead.title)"
                    newReminder.priority = eventKitPriority(for: bead.priority.rawValue)

                    var notesSections: [String] = []
                    notesSections.append("Priority: P\(bead.priority.rawValue) | Status: \(bead.status)")
                    if let type = bead.issueType {
                        notesSections.append("Type: \(type)")
                    }
                    if let desc = bead.description, !desc.isEmpty {
                        notesSections.append("\n\(desc)")
                    }
                    if let notes = bead.notes, !notes.isEmpty {
                        notesSections.append("\nNotes:\n\(notes)")
                    }
                    newReminder.notes = notesSections.joined(separator: "\n")
                    newReminder.isCompleted = false

                    try store.save(newReminder, commit: false)
                }
                summary.addedReminders += 1
            }
        }

        // 7. Commit changes
        if !config.isDryRun {
            try store.commit()
        }

        print("\n✅ Sync complete!")
        print("   • New reminders added: \(summary.addedReminders)")
        print("   • Reminders marked completed: \(summary.completedReminders)")
        print("   • Beads created from Reminders: \(summary.createdBeads)")
        print("   • Beads closed from Reminders: \(summary.closedBeads)")

        return summary
    }
}

public enum SyncError: LocalizedError {
    case accessDenied
    case listNotFound(requested: String, available: String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to Apple Reminders was not granted in macOS Privacy & Security."
        case let .listNotFound(requested, available):
            return "Reminders list '\(requested)' was not found. Available lists: \(available). Specify a list with --list <name>."
        case let .commandFailed(message):
            return message
        }
    }
}
