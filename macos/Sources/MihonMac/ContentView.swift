import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var backend: Backend

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed.fill").font(.title2).foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mihon Mac").font(.headline)
                        Text("Your reading space").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20)
                List(Shelf.allCases, selection: $store.shelf) { shelf in
                    Label(shelf.rawValue, systemImage: shelf.icon).tag(shelf).padding(.vertical, 5)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Label(backend.ready ? "On this Mac" : "Starting engine", systemImage: backend.ready ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(backend.ready ? Color.green : Color.secondary)
                    Text("Native macOS preview · 0.1").foregroundStyle(.secondary)
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if let error = store.error {
                    HStack { Image(systemName: "exclamationmark.triangle"); Text(error).textSelection(.enabled); Spacer(); Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .padding(12).background(.red.opacity(0.1))
                }
                if let notice = store.notice {
                    HStack { Image(systemName: "checkmark.circle"); Text(notice).lineLimit(4); Spacer(); Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .padding(12).background(.green.opacity(0.1))
                }
                if backend.ready {
                    switch store.shelf {
                    case .library, .history: LibraryView(store: store)
                    case .updates: UpdatesView(store: store)
                    case .downloads: DownloadsView(store: store)
                    case .browse: BrowseView(store: store)
                    case .extensions: ExtensionsView(store: store)
                    case .tracking: TrackingView(store: store)
                    case .backups: BackupView(store: store)
                    case .settings: ScrollView { SettingsView(store: store).padding(32).frame(maxWidth: 720) }.frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: "book.closed").font(.system(size: 52)).foregroundStyle(.indigo)
                        if backend.failure == nil { ProgressView() }
                        Text(backend.status).font(.title2)
                        if let failure = backend.failure {
                            Text(failure).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 500)
                            Button("Try Again") { Task { await backend.start(); if backend.ready { await store.perform { try await store.refresh() } } } }
                            Button("Open Engine Log") { NSWorkspace.shared.open(backend.dataRoot.appendingPathComponent("engine.log")) }
                        } else { Text("Preparing sources, reading progress, and backups.").foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(store.shelf.rawValue)
            .toolbar {
                ToolbarItem { if store.busy { ProgressView().controlSize(.small) } }
                ToolbarItem { Button { Task { await store.perform { try await store.refresh() } } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(!backend.ready || store.busy) }
                ToolbarItem { Button { store.importComics() } label: { Label("Import Comics", systemImage: "plus") }.disabled(!backend.ready || store.busy) }
            }
        }
        .onChange(of: store.shelf) { _, _ in store.query = "" }
        .sheet(item: $store.selected) { manga in MangaDetailView(store: store, manga: manga) }
    }
}

struct PageIntro: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyShelf: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(.indigo)
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }
}

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageIntro(title: store.shelf == .history ? "Pick up where you left off" : "Your library", subtitle: store.shelf == .history ? "Recently read titles, with progress saved on this Mac." : "\(store.library.count) \(store.library.count == 1 ? "title" : "titles") · a quiet place for your collection")
            HStack {
                TextField("Search your library", text: $store.query).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Picker("Category", selection: $store.categoryId) {
                    Text("All categories").tag(nil as Int?)
                    ForEach(store.categories) { Text($0.name).tag(Optional($0.id)) }
                }.frame(maxWidth: 240).disabled(store.busy)
                .onChange(of: store.categoryId) { _, id in Task { await store.perform { try await store.filterCategory(id) } } }
                Spacer()
            }
            if store.visibleLibrary.isEmpty {
                EmptyShelf(symbol: "books.vertical", title: store.library.isEmpty ? "Make room for your next story" : "No titles here yet", subtitle: "Import local comics, restore your Mihon backup, or add a title from Browse.")
                if store.library.isEmpty {
                    HStack { Button("Import Comics…") { store.importComics() }; Button("Restore Backup…") { store.restoreBackup() }; Button("Browse Sources") { store.shelf = .browse } }.frame(maxWidth: .infinity).padding(.bottom, 60)
                }
            } else { MangaGrid(store: store, items: store.visibleLibrary) }
        }.padding(28)
    }
}

struct MangaGrid: View {
    @ObservedObject var store: LibraryStore
    let items: [Manga]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 195), spacing: 22)], alignment: .leading, spacing: 26) {
                ForEach(items) { manga in
                    Button { Task { await store.show(manga) } } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            CoverView(api: store.api, manga: manga).aspectRatio(0.69, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topLeading) {
                                    if let count = manga.unreadCount, count > 0 { Text("\(count)").font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 4).background(.indigo, in: Capsule()).foregroundStyle(.white).padding(7) }
                                }
                            Text(manga.title).font(.headline).foregroundStyle(.primary).lineLimit(2).frame(height: 36, alignment: .topLeading)
                            Text(manga.source?.displayName ?? (manga.sourceId == "0" ? "Local collection" : store.sources.first(where: { $0.id == manga.sourceId })?.displayName ?? "Source unavailable")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Open \(manga.title)")
                }
            }.padding(.bottom, 16)
        }
    }
}

struct CoverView: View {
    let api: API
    let manga: Manga
    var body: some View {
        AsyncImage(url: api.url("api/v1/manga/\(manga.id)/thumbnail")) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { ZStack { Color.indigo.opacity(0.09); Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.indigo.opacity(0.4)) } }
        }
    }
}

struct BrowseView: View {
    @ObservedObject var store: LibraryStore
    @ViewState private var term = ""
    @ViewState private var latest = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageIntro(title: "Find your next read", subtitle: "Browse installed sources. Add extensions to discover more.")
            HStack {
                Picker("Source", selection: $store.selectedSource) {
                    Text("Choose a source").tag(nil as Source?)
                    ForEach(store.sources) { Text("\($0.displayName) · \($0.id == "0" ? "On this Mac" : $0.lang.uppercased())").tag(Optional($0)) }
                }.frame(maxWidth: 320)
                TextField("Search source", text: $term).textFieldStyle(.roundedBorder).onSubmit { search() }
                Button("Search") { search() }.disabled(store.selectedSource == nil || store.busy)
                Toggle("Latest", isOn: $latest).toggleStyle(.checkbox).disabled(store.selectedSource?.supportsLatest != true)
                    .onChange(of: latest) { _, _ in search() }
            }
            .onChange(of: store.selectedSource) { _, source in if let source { term = ""; latest = false; Task { await store.browse(source) } } }
            if store.sourceManga.isEmpty {
                EmptyShelf(symbol: "safari", title: store.busy ? "Finding stories…" : "Choose a source to explore", subtitle: "Local source reads imported comics. Online sources appear after you install their extensions.")
            } else { MangaGrid(store: store, items: store.sourceManga) }
            if store.hasNextPage {
                Button("Load More") { if let source = store.selectedSource { Task { await store.browse(source, term: term, page: store.sourcePage + 1, latest: latest) } } }.disabled(store.busy).frame(maxWidth: .infinity)
            }
        }.padding(28)
    }
    private func search() { if let source = store.selectedSource { Task { await store.browse(source, term: term, latest: latest) } } }
}
