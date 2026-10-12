import SwiftUI

struct MangaDetailView: View {
    @ObservedObject var store: LibraryStore
    let manga: Manga
    @Environment(\.dismiss) private var dismiss
    @ViewState private var newCategory = ""
    @ViewState private var mangaCategories: Set<Int> = []
    @ViewState private var tab = 0
    private var current: Manga { store.selected ?? manga }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(current.title).font(.headline); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Divider()
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 16) {
                    CoverView(api: store.api, manga: current).frame(width: 180, height: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(current.title).font(.title2.bold()).textSelection(.enabled)
                    Text(current.author ?? current.artist ?? "Unknown author").foregroundStyle(.secondary)
                    Text(current.source?.displayName ?? store.sources.first(where: { $0.id == current.sourceId })?.displayName ?? "Source unavailable").font(.caption).foregroundStyle(.secondary)
                    Button { Task { await store.perform { try await store.toggleLibrary(current) } } } label: {
                        Label(current.inLibrary ? "In Library" : "Add to Library", systemImage: current.inLibrary ? "checkmark" : "plus")
                    }.buttonStyle(.borderedProminent).disabled(store.busy)
                    if current.inLibrary {
                        Menu("Categories") {
                            ForEach(store.categories.filter { $0.id != 0 }) { category in
                                Button {
                                    Task { await store.perform {
                                        let contains = mangaCategories.contains(category.id)
                                        try await store.api.action("manga/\(current.id)/category/\(category.id)", method: contains ? "DELETE" : "GET")
                                        await loadCategories()
                                        try await store.refresh()
                                    } }
                                } label: { Label(category.name, systemImage: mangaCategories.contains(category.id) ? "checkmark" : "circle") }
                            }
                        }
                        HStack {
                            TextField("New category", text: $newCategory).textFieldStyle(.roundedBorder)
                            Button { Task { await store.perform {
                                try await store.api.action("category", method: "POST", form: ["name": newCategory])
                                newCategory = ""
                                try await store.refresh()
                            } } } label: { Image(systemName: "plus") }.disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty || store.busy)
                        }
                    }
                    Spacer()
                }.frame(width: 210)
                VStack(alignment: .leading, spacing: 16) {
                    if let error = store.error {
                        Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled)
                        Button("Dismiss Error") { store.error = nil }
                    }
                    Picker("Details", selection: $tab) { Text("Chapters").tag(0); Text("About").tag(1); Text("Tracking").tag(2) }.pickerStyle(.segmented)
                    if store.detailLoading { ProgressView("Loading chapters…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if tab == 0 { chapterList }
                    else if tab == 1 {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(current.status?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Unknown status").font(.headline)
                                Text((current.genre ?? []).joined(separator: " · ")).foregroundStyle(.secondary)
                                Text(current.description ?? "No description available.").textSelection(.enabled).lineSpacing(5)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else { MangaTrackingView(store: store, manga: current) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.padding(26)
        }
        .frame(minWidth: 880, idealWidth: 960, minHeight: 620, idealHeight: 720)
        .task { await loadCategories() }
        .sheet(item: $store.reader, onDismiss: { Task { await store.show(current); await store.perform { try await store.refresh() } } }) { session in
            ReaderView(api: store.api, session: session, reportError: { store.error = $0 })
        }
    }

    private var chapterList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(store.chapters.count) chapters").font(.headline)
                Spacer()
                Button { Task { await store.show(current, onlineFetch: true) } } label: { Image(systemName: "arrow.clockwise") }.help("Fetch current details and chapters from the source").disabled(store.busy || store.detailLoading)
                Button("Continue Reading") {
                    if let chapter = store.chapters.first(where: { !$0.read }) ?? store.chapters.first { Task { await store.read(chapter) } }
                }.buttonStyle(.borderedProminent).disabled(store.chapters.isEmpty || store.busy)
            }
            List(store.chapters) { chapter in
                HStack(spacing: 12) {
                    Button { Task { await store.read(chapter) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: chapter.read ? "checkmark.circle.fill" : "circle").foregroundStyle(chapter.read ? Color.secondary : Color.indigo)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.name).lineLimit(2)
                                Text(chapter.scanlator ?? (chapter.downloaded ? "Available offline" : "Chapter \(chapter.index)")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if chapter.bookmarked { Image(systemName: "bookmark.fill").foregroundStyle(.indigo) }
                    Menu {
                        Button(chapter.read ? "Mark Unread" : "Mark Read") { edit(chapter, ["read": String(!chapter.read)]) }
                        Button(chapter.bookmarked ? "Remove Bookmark" : "Bookmark") { edit(chapter, ["bookmarked": String(!chapter.bookmarked)]) }
                        Button("Download for Offline Reading") { Task { await store.perform { try await store.api.action("download/\(chapter.mangaId)/chapter/\(chapter.index)"); try await store.api.action("downloads/start"); store.notice = "Chapter added to the download queue." } } }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                }.padding(.vertical, 7)
            }.listStyle(.plain)
        }
    }

    private func edit(_ chapter: Chapter, _ form: [String: String]) { Task { await store.perform { try await store.updateChapter(chapter, form: form) } } }
    private func loadCategories() async {
        do { let cats: [Category] = try await store.api.get("manga/\(current.id)/category"); mangaCategories = Set(cats.map(\.id)) }
        catch { store.error = error.localizedDescription }
    }
}
