import Foundation

@main
struct APIChecks {
    static func main() throws {
        let api = API(port: 45679)
        let url = api.url("api/v1/source/9223372036854775807/search", query: ["searchTerm": "A+B & 日本語?#", "pageNum": "2"])
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        precondition(components.queryItems?.first(where: { $0.name == "searchTerm" })?.value == "A+B & 日本語?#")
        precondition(url.path == "/api/v1/source/9223372036854775807/search")
        print("PASS: source search preserves Unicode and reserved URL characters")
        let json = #"{"id":"9223372036854775807","name":"Example","lang":"en","displayName":"Example","supportsLatest":true,"isConfigurable":false,"isNsfw":false}"#
        let source = try JSONDecoder().decode(Source.self, from: Data(json.utf8))
        precondition(source.id == "9223372036854775807")
        print("PASS: source IDs preserve signed 64-bit precision")
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("mihon-import-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let root = fixture.appendingPathComponent("Library/local")
        let pages = fixture.appendingPathComponent("Pages")
        let series = fixture.appendingPathComponent("Series")
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: series, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: pages.appendingPathComponent("001.PNG"))
        try Data().write(to: series.appendingPathComponent("Chapter 1.cbz"))
        let pagePlan = try LocalComicImport.plan(pages, root: root)
        let seriesPlan = try LocalComicImport.plan(series, root: root)
        precondition(pagePlan.destination.path == root.appendingPathComponent("Pages/Chapter 1").path)
        precondition(seriesPlan.destination.path == root.appendingPathComponent("Series").path)
        print("PASS: page folders and multi-chapter series keep their distinct layouts")
        do {
            _ = try LocalComicImport.plan(fixture, root: root)
            preconditionFailure("Recursive library import was accepted")
        } catch is APIError { print("PASS: importing an ancestor of library storage is rejected") }
        try FileManager.default.createDirectory(at: seriesPlan.destination, withIntermediateDirectories: true)
        do {
            _ = try LocalComicImport.plan(series, root: root)
            preconditionFailure("Duplicate series import was accepted")
        } catch is APIError { print("PASS: existing imported series are preserved") }
    }
}
