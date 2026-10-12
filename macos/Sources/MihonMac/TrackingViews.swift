import AppKit
import SwiftUI

struct TrackingView: View {
    @ObservedObject var store: LibraryStore
    @ViewState private var login: Tracker?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageIntro(title: "Keep your lists in step", subtitle: "Connect a tracker, then link a title from its Tracking tab.")
            List(store.trackers) { tracker in
                HStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.title2).foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 4) { Text(tracker.name).font(.headline); Text(tracker.isLogin ? "Connected" : "Not connected").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if tracker.isLogin {
                        Button("Disconnect") { Task { await store.perform { try await store.api.action("track/logout", method: "POST", json: ["trackerId": tracker.id]); try await store.refresh() } } }
                    } else { Button("Connect…") { login = tracker } }
                }.padding(.vertical, 10)
            }.listStyle(.plain)
            Text("Available here: MyAnimeList, AniList, Kitsu, MangaUpdates, Shikimori, and Bangumi. Other Mihon trackers remain on the porting roadmap. Credentials stay in the local engine; connecting sends requests to the selected service.").font(.callout).foregroundStyle(.secondary)
        }.padding(28)
            .sheet(item: $login) { tracker in TrackerLoginView(store: store, tracker: tracker) }
    }
}

struct TrackerLoginView: View {
    @ObservedObject var store: LibraryStore
    let tracker: Tracker
    @Environment(\.dismiss) private var dismiss
    @ViewState private var username = ""
    @ViewState private var password = ""
    @ViewState private var callback = ""
    @ViewState private var failure: String?
    private var hasLoginInput: Bool { tracker.authUrl != nil ? !callback.isEmpty || (tracker.name == "AniList" && !password.isEmpty) : !username.isEmpty && !password.isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect \(tracker.name)").font(.title2.bold())
            if let auth = tracker.authUrl, let url = URL(string: auth) {
                Text("Authorize in your browser, then paste the complete redirected URL below. Your tracker account remains with its service.").foregroundStyle(.secondary)
                Button("Open \(tracker.name) Authorization") { NSWorkspace.shared.open(url) }
                SecureField("Complete callback URL", text: $callback).textFieldStyle(.roundedBorder)
                if tracker.name == "AniList" {
                    Text("If AniList displays an access token instead of a redirect, paste that token here. Enter authorization details only in this app.").font(.callout).foregroundStyle(.secondary)
                    SecureField("AniList access token (alternative)", text: $password).textFieldStyle(.roundedBorder)
                }
            } else {
                TextField("Username / email", text: $username).textFieldStyle(.roundedBorder)
                SecureField("Password / API token", text: $password).textFieldStyle(.roundedBorder)
            }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Connect") { connect() }.buttonStyle(.borderedProminent).disabled(store.busy || !hasLoginInput) }
        }.padding(28).frame(width: 540)
    }
    private func connect() { Task { await store.perform {
        do {
            var json: [String: Any] = ["trackerId": tracker.id]
            if tracker.authUrl != nil && !callback.isEmpty { json["callbackUrl"] = callback.trimmingCharacters(in: .whitespacesAndNewlines) }
            else { json["username"] = username; json["password"] = tracker.name == "AniList" ? password.trimmingCharacters(in: .whitespacesAndNewlines) : password }
            try await store.api.action("track/login", method: "POST", json: json)
            password = ""; callback = ""
            try await store.refresh()
            dismiss()
        } catch { failure = error.localizedDescription }
    } } }
}

struct MangaTrackingView: View {
    @ObservedObject var store: LibraryStore
    let manga: Manga
    @ViewState private var trackerId: Int? = nil
    @ViewState private var title = ""
    @ViewState private var results: [TrackSearch] = []
    @ViewState private var failure: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let failure { Text(failure).foregroundStyle(.red) }
                ForEach(manga.trackers ?? []) { tracker in
                    if let record = tracker.record {
                        GroupBox(tracker.name) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(record.title).font(.headline)
                                Text("Chapter \(record.lastChapterRead.formatted()) of \(record.totalChapters)").foregroundStyle(.secondary)
                                Picker("Status", selection: Binding(get: { record.status }, set: { update(record, ["status": $0]) })) {
                                    ForEach(tracker.statusList, id: \.self) { Text(tracker.statusTextMap[String($0)] ?? String($0)).tag($0) }
                                }.disabled(store.busy)
                                HStack {
                                    Button("Sync Read Progress") {
                                        let last = store.chapters.filter(\.read).map(\.chapterNumber).max() ?? record.lastChapterRead
                                        update(record, ["lastChapterRead": last])
                                    }
                                    if let url = URL(string: record.remoteUrl) { Link("Open Tracker", destination: url) }
                                    Spacer()
                                    Button("Unlink") { update(record, ["unbind": true]) }
                                }.disabled(store.busy)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Divider()
                Text("Link a tracker").font(.headline)
                Picker("Connected service", selection: $trackerId) {
                    Text("Choose a service").tag(nil as Int?)
                    ForEach(store.trackers.filter(\.isLogin)) { Text($0.name).tag(Optional($0.id)) }
                }
                HStack {
                    TextField("Search title", text: $title).textFieldStyle(.roundedBorder).onSubmit { search() }
                    Button("Search") { search() }.disabled(trackerId == nil || title.isEmpty || store.busy)
                }
                ForEach(results) { result in
                    HStack { VStack(alignment: .leading) { Text(result.title); Text("\(result.totalChapters) chapters").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Link") { bind(result) }.disabled(store.busy) }
                }
                if store.trackers.allSatisfy({ !$0.isLogin }) { Text("Connect a service from the Tracking section first.").foregroundStyle(.secondary) }
            }
        }.onAppear { title = manga.title }
    }
    private func search() { guard let trackerId else { return }; Task { await store.perform {
        let data = try await store.api.action("track/search", method: "POST", json: ["trackerId": trackerId, "title": title])
        results = try JSONDecoder().decode([TrackSearch].self, from: data)
    } } }
    private func bind(_ result: TrackSearch) { Task { await store.perform {
        try await store.api.action("track/bind", method: "POST", query: ["mangaId": String(manga.id), "trackerId": String(result.trackerId), "remoteId": String(result.remoteId), "private": "false"])
        let detail: Manga = try await store.api.get("manga/\(manga.id)/full")
        store.selected = detail
        results = []
    } } }
    private func update(_ record: TrackRecord, _ fields: [String: Any]) { Task { await store.perform {
        var json = fields; json["recordId"] = record.id
        try await store.api.action("track/update", method: "POST", json: json)
        let detail: Manga = try await store.api.get("manga/\(manga.id)/full")
        store.selected = detail
    } } }
}
