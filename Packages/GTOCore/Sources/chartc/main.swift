import Foundation
import ChartCompiler
import ChartData

// Compiles Data/ into the app's range book. Run from the repo root:
//   swift run --package-path Packages/GTOCore chartc --data Data --out Packages/GTOCore/Sources/ChartData/Resources/6max-100.json
// Add --check to fail if the book is out of date instead of rewriting it.

func value(of flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("chartc: \(message)\n".utf8))
    exit(1)
}

guard let dataPath = value(of: "--data"), let outPath = value(of: "--out") else {
    fail("usage: chartc --data <dir> --out <file> [--check]")
}

let dataDirectory = URL(fileURLWithPath: dataPath, isDirectory: true)
let outURL = URL(fileURLWithPath: outPath)

do {
    let patchData = try Data(contentsOf: dataDirectory.appendingPathComponent(BookCompiler.patchFileName))
    let patches = try JSONDecoder().decode(PatchFile.self, from: patchData)
    let csv = try Data(contentsOf: dataDirectory.appendingPathComponent(patches.source.file))
    let legacy = try BookCompiler.importLegacy(
        Data(contentsOf: dataDirectory.appendingPathComponent(BookCompiler.legacyFileName)),
        rules: patches.actionRules
    )

    let book = try BookCompiler.compile(csv: csv, patches: patches, legacy: legacy)
    let findings = BookValidator.validate(book)
    findings.forEach { print($0) }

    let errors = findings.filter { $0.severity == .error }
    guard errors.isEmpty else { fail("\(errors.count) validation errors") }

    let output = try BookCompiler.encode(book)
    if CommandLine.arguments.contains("--check") {
        guard (try? Data(contentsOf: outURL)) == output else { fail("\(outPath) is out of date") }
        print("\(outPath) is up to date")
    } else {
        try output.write(to: outURL)
        print("Wrote \(book.spots.count) spots, \(book.patches.count) patches and \(book.disputes.count) disputes to \(outPath)")
    }
} catch {
    fail(String(describing: error))
}
