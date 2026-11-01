import Foundation
import BdRemindersCore

func printHelp() {
    print("""
    bd-reminders: Two-way sync between Beads (bd) issues and Apple Reminders.

    USAGE:
      bd-reminders [options]

    OPTIONS:
      -p, --project <path>    Path to beads project directory (default: current directory)
      -l, --list <name>       Name of target Reminders list (default: project folder name)
      --dry-run               Preview sync operations without making changes
      -h, --help              Show this help message
    """)
}

let args = CommandLine.arguments

if args.contains("-h") || args.contains("--help") {
    printHelp()
    exit(0)
}

let isDryRun = args.contains("--dry-run")

var projectDir = FileManager.default.currentDirectoryPath
if let pIndex = args.firstIndex(where: { $0 == "-p" || $0 == "--project" }), pIndex + 1 < args.count {
    projectDir = NSString(string: args[pIndex + 1]).expandingTildeInPath
}

var targetListName: String? = nil
if let lIndex = args.firstIndex(where: { $0 == "-l" || $0 == "--list" }), lIndex + 1 < args.count {
    targetListName = args[lIndex + 1]
}

let config = SyncConfiguration(
    projectDirectory: projectDir,
    targetListName: targetListName,
    isDryRun: isDryRun
)

let engine = SyncEngine(config: config)

Task {
    do {
        try await engine.run()
        exit(0)
    } catch {
        print("❌ Error: \(error.localizedDescription)")
        exit(1)
    }
}

RunLoop.main.run()
