import ClingCore
import Foundation

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage:
      cling index <root> <out.idx> [--ignore <patternsFile>]
      cling search <out.idx> <query...>
    """.utf8))
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage() }

switch cmd {
case "index":
    guard args.count >= 3 else { usage() }
    let root = args[1]
    let out = URL(fileURLWithPath: args[2])
    var patterns = [String]()
    if let i = args.firstIndex(of: "--ignore"), i + 1 < args.count,
       let text = try? String(contentsOfFile: args[i + 1], encoding: .utf8) {
        patterns = text.split(separator: "\n").map(String.init)
    }
    do {
        let n = try Indexer.build(root: root, ignore: IgnoreMatcher(patterns: patterns), output: out)
        print("indexed \(n) entries -> \(out.path)")
    } catch { FileHandle.standardError.write(Data("index failed: \(error)\n".utf8)); exit(1) }

case "search":
    guard args.count >= 3 else { usage() }
    let idx = URL(fileURLWithPath: args[1])
    let query = args[2...].joined(separator: " ")
    do {
        let reader = try IndexReader(url: idx)
        let hits = SearchEngine(reader: reader).search(query, maxResults: 200)
        for h in hits { print(h.path) }
    } catch { FileHandle.standardError.write(Data("search failed: \(error)\n".utf8)); exit(1) }

case "--version", "-v":
    print("cling \(ClingCore.version)")

default:
    usage()
}
