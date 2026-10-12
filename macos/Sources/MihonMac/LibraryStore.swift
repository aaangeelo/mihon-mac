import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    let backend: Backend
    var api: API { backend.api }
    @Published var shelf: Shelf = .library
    @Published var library: [Manga] = []
    @Published var categories: [Category] = []
    @Published var sources: [Source] = []
    @Published var extensions: [SourceExtension] = []
    @Published var trackers: [Tracker] = []
    @Published var selected: Manga?
    @Published var chapters: [Chapter] = []
    @Published var selectedSource: Source?
    @Published var sourceManga: [Manga] = []
    @Published var sourcePage = 1
    @Published var hasNextPage = false
    @Published var query = ""
    @Published var categoryId: Int? = nil
    @Published var filteredCategoryIds: Set<Int>? = nil
    @Published var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published var reader: ReadingSession?
    @Published var detailLoading = false
    private var detailRequest = UUID()
    private var browseRequest = UUID()

    init(backend: Backend) { self.backend = backend }

    var visibleLibrary: [Manga] {
        let rows = library.filter {
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) && (filteredCategoryIds == nil || filteredCategoryIds!.contains($0.id))
        }
        return shelf == .history ? rows.filter { ($0.lastReadAt ?? 0) > 0 }.sorted { ($0.lastReadAt ?? 0) > ($1.lastReadAt ?? 0) } : rows.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await operation() } catch { self.error = error.localizedDescription }
    }

    func refresh() async throws {
        let cats: [Category] = try await api.get("category")
        var all: [Int: Manga] = [:]
        for cat in cats {
            let items: [Manga] = try await api.get("category/\(cat.id)")
            for item in items { all[item.id] = item }
        }
        categories = cats.sorted { $0.order < $1.order }
        library = Array(all.values)
        sources = try await api.get("source/list")
        trackers = try await api.get("track/list")
        if let categoryId { try await filterCategory(categoryId) }
    }

    func filterCategory(_ id: Int?) async throws {
        categoryId = id
        guard let id else { filteredCategoryIds = nil; return }
        let items: [Manga] = try await api.get("category/\(id)")
        guard categoryId == id else { return }
        filteredCategoryIds = Set(items.map(\.id))
    }

    func show(_ manga: Manga, onlineFetch: Bool = false) async {
        let request = UUID()
        detailRequest = request
        selected = manga
        chapters = []
        detailLoading = true
        do {
            // Cached details and chapters allow downloaded content to open offline.
            // The engine initializes new titles when needed; explicit refresh fetches updates.
            let query = ["onlineFetch": String(onlineFetch)]
            let detail: Manga = try await api.get("manga/\(manga.id)/full", query: query)
            let list: [Chapter] = try await api.get("manga/\(manga.id)/chapters", query: query)
            guard request == detailRequest else { return }
            selected = detail
            chapters = list.sorted { $0.index < $1.index }
        } catch {
            if request == detailRequest { self.error = error.localizedDescription }
        }
        if request == detailRequest { detailLoading = false }
    }

    func browse(_ source: Source, term: String = "", page: Int = 1, latest: Bool = false) async {
        let request = UUID()
        browseRequest = request
        selectedSource = source
        if page == 1 { sourceManga = [] }
        busy = true
        do {
            let path = term.isEmpty ? "source/\(source.id)/\(latest ? "latest" : "popular")/\(page)" : "source/\(source.id)/search"
            let result: MangaPage = try await api.get(path, query: term.isEmpty ? [:] : ["searchTerm": term, "pageNum": String(page)])
            guard request == browseRequest else { return }
            if page == 1 { sourceManga = result.mangaList } else {
                let existing = Set(sourceManga.map(\.id))
                sourceManga += result.mangaList.filter { !existing.contains($0.id) }
            }
            sourcePage = page
            hasNextPage = result.hasNextPage
        } catch { if request == browseRequest { self.error = error.localizedDescription } }
        if request == browseRequest { busy = false }
    }

    func toggleLibrary(_ manga: Manga) async throws {
        try await api.action("manga/\(manga.id)/library", method: manga.inLibrary ? "DELETE" : "GET")
        if selected?.id == manga.id { selected?.inLibrary.toggle() }
        try await refresh()
    }

    func updateChapter(_ chapter: Chapter, form: [String: String]) async throws {
        try await api.action("manga/\(chapter.mangaId)/chapter/\(chapter.index)", method: "PATCH", form: form)
        chapters = try await api.get("manga/\(chapter.mangaId)/chapters")
        chapters.sort { $0.index < $1.index }
        try await refresh()
    }

    func read(_ chapter: Chapter) async {
        guard let manga = selected else { return }
        let readingChapters = chapters
        await perform {
            let loaded: Chapter = try await api.get("manga/\(chapter.mangaId)/chapter/\(chapter.index)")
            guard loaded.pageCount > 0 else { throw APIError(message: "This chapter has no readable pages.") }
            guard selected?.id == manga.id else { return }
            reader = ReadingSession(manga: manga, chapter: loaded, chapters: readingChapters)
        }
    }

    func importComics() {
        let panel = NSOpenPanel()
        panel.title = "Import local comics"
        panel.message = "Choose CBZ/ZIP comics, page-image folders, or series folders containing chapters. Files are copied into your library."
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.zip, UTType(filenameExtension: "cbz") ?? .data, .folder]
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await perform {
            let root = backend.dataRoot.appendingPathComponent("local")
            let plans = try urls.map { try LocalComicImport.plan($0, root: root) }
            guard Set(plans.map(\.name)).count == plans.count else {
                throw APIError(message: "Some selected comics have the same name. Import them separately with different names.")
            }
            for plan in plans {
                try FileManager.default.createDirectory(at: plan.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: plan.source, to: plan.destination)
            }
            sources = try await api.get("source/list")
            guard let local = sources.first(where: { $0.id == "0" }) else { throw APIError(message: "The local source is unavailable.") }
            var names = Set(plans.map(\.name))
            var pageNumber = 1
            repeat {
                let page: MangaPage = try await api.get("source/\(local.id)/popular/\(pageNumber)")
                for manga in page.mangaList where names.contains(manga.title) {
                    try await api.action("manga/\(manga.id)/library")
                    names.remove(manga.title)
                }
                guard page.hasNextPage else { break }
                pageNumber += 1
            } while !names.isEmpty
            guard names.isEmpty else { throw APIError(message: "Files were copied, but these titles need a refresh in Browse → Local source: \(names.sorted().joined(separator: ", ")).") }
            try await refresh()
            shelf = .library
            notice = "Imported \(urls.count) local comic\(urls.count == 1 ? "" : "s")."
        } }
    }

    func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mihon-mac-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).tachibk"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await perform {
            let data = try await api.data("api/v1/backup/export")
            try data.write(to: url, options: .atomic)
            notice = "Saved backup to \(url.lastPathComponent)."
        } }
    }

    func restoreBackup() {
        let panel = NSOpenPanel()
        panel.title = "Restore a Mihon / Tachiyomi backup"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await perform {
            let data = try Data(contentsOf: url)
            let result = try await api.data("api/v1/backup/validate", method: "POST", body: data, contentType: "application/octet-stream")
            let pretty = (try? JSONSerialization.jsonObject(with: result)).flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) }.flatMap { String(data: $0, encoding: .utf8) } ?? "Backup is valid."
            let alert = NSAlert()
            alert.messageText = "Restore \(url.lastPathComponent)?"
            alert.informativeText = "This merges its library, chapters, history and supported tracking records into this Mac. Android settings and some metadata are not preserved.\n\nValidation:\n\(pretty)"
            alert.addButton(withTitle: "Restore")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            // Preserve the complete Android input, including fields this engine cannot decode.
            let originals = backend.dataRoot.appendingPathComponent("android-imports")
            try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
            try data.write(to: originals.appendingPathComponent("\(UUID().uuidString).tachibk"), options: .atomic)
            // Keep a recovery snapshot before merging.
            let recovery = try await api.data("api/v1/backup/export")
            let directory = backend.dataRoot.appendingPathComponent("pre-restore")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try recovery.write(to: directory.appendingPathComponent("\(UUID().uuidString).tachibk"), options: .atomic)
            let report = try await api.data("api/v1/backup/import", method: "POST", body: data, contentType: "application/octet-stream")
            try await refresh()
            notice = "Restore finished. " + (String(data: report, encoding: .utf8) ?? "")
        } }
    }
}

struct ReadingSession: Identifiable {
    let id = UUID()
    let manga: Manga
    let chapter: Chapter
    let chapters: [Chapter]
}
