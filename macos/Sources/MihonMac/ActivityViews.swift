import SwiftUI

struct DownloadsView: View {
    @ObservedObject var store: LibraryStore
    @ViewState private var state: DownloadState?
    @ViewState private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageIntro(title: "Ready when you are", subtitle: "Download chapter pages to read without an internet connection.")
            HStack {
                Label(state?.state == "STARTED" ? "Downloading" : "Paused", systemImage: state?.state == "STARTED" ? "arrow.down.circle" : "pause.circle").foregroundStyle(.secondary)
                Spacer()
                Button(state?.state == "STARTED" ? "Pause" : "Start") { action(state?.state == "STARTED" ? "stop" : "start") }.disabled(store.busy)
                Button("Clear Queue") { action("clear") }.disabled(store.busy || state?.queue.isEmpty != false)
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            if state?.queue.isEmpty != false { EmptyShelf(symbol: "arrow.down.circle", title: "Your download queue is clear", subtitle: "Open a title, then choose Download for Offline Reading from a chapter’s menu.") }
            else {
                List(state?.queue ?? []) { item in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.manga.title).font(.headline)
                            Text(item.chapter.name).foregroundStyle(.secondary)
                            ProgressView(value: item.progress).frame(maxWidth: 420)
                        }
                        Spacer()
                        VStack(alignment: .trailing) { Text(item.state.capitalized); Text(item.progress.formatted(.percent.precision(.fractionLength(0)))).foregroundStyle(.secondary) }
                        Button("Remove") { Task { await store.perform { try await store.api.action("download/\(item.chapter.mangaId)/chapter/\(item.chapter.sourceOrder)", method: "DELETE"); await load() } } }.disabled(store.busy)
                    }.padding(.vertical, 10)
                }.listStyle(.plain)
            }
        }.padding(28).task {
            while !Task.isCancelled { await load(); do { try await Task.sleep(for: .seconds(3)) } catch { return } }
        }
    }
    private func load() async {
        do {
            let result = try await store.api.graphql("{ downloadStatus { state queue { state progress tries position manga { id title } chapter { id name mangaId sourceOrder } } } }")
            if let object = result["downloadStatus"] { state = try JSONDecoder().decode(DownloadState.self, from: JSONSerialization.data(withJSONObject: object)); failure = nil }
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
    private func action(_ action: String) { Task { await store.perform { try await store.api.action("downloads/\(action)"); await load() } } }
}

struct UpdatesView: View {
    @ObservedObject var store: LibraryStore
    @ViewState private var items: [RecentChapter] = []
    @ViewState private var page = 0
    @ViewState private var hasNext = false
    @ViewState private var updating = false
    @ViewState private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageIntro(title: "The next chapter awaits", subtitle: "New chapters found in your library. Check your sources for updates.")
            HStack {
                if updating { ProgressView().controlSize(.small); Text("Checking library…").foregroundStyle(.secondary) }
                Spacer()
                Button("Check for New Chapters") { Task { await store.perform { try await store.api.action("update/fetch", method: "POST", form: [:]); updating = true } } }.disabled(store.busy || updating)
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            if items.isEmpty { EmptyShelf(symbol: "sparkles", title: "You’re caught up", subtitle: "New chapters will appear here after a library update.") }
            else {
                List(items) { item in
                    Button { Task { await store.show(item.manga); await store.read(item.chapter) } } label: {
                        HStack(spacing: 14) {
                            CoverView(api: store.api, manga: item.manga).frame(width: 45, height: 64).clipped().clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 5) { Text(item.manga.title).font(.headline); Text(item.chapter.name).foregroundStyle(.secondary) }
                            Spacer()
                            Image(systemName: item.chapter.read ? "checkmark.circle" : "play.circle").foregroundStyle(.indigo)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.vertical, 5)
                }.listStyle(.plain)
            }
            if hasNext { Button("Load More") { Task { await load(next: true) } }.frame(maxWidth: .infinity) }
        }.padding(28).task {
            while !Task.isCancelled { await load(); do { try await Task.sleep(for: .seconds(5)) } catch { return } }
        }
    }
    private func load(next: Bool = false) async {
        do {
            if !next {
                let data = try await store.api.action("update/summary")
                let summary = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                updating = summary?["running"] as? Bool ?? false
                if page > 0 { return }
            }
            let number = next ? page + 1 : 0
            let result: RecentPage = try await store.api.get("update/recentChapters/\(number)")
            if next { let ids = Set(items.map(\.id)); items += result.page.filter { !ids.contains($0.id) } } else { items = result.page }
            page = number; hasNext = result.hasNextPage; failure = nil
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
}
