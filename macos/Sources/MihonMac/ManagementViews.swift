import AppKit
import SwiftUI

struct ExtensionsView: View {
    @ObservedObject var store: LibraryStore
    @ViewState private var repository = ""
    @ViewState private var search = ""
    @ViewState private var installedOnly = false
    @ViewState private var repositories: [String] = []

    private var filtered: [SourceExtension] {
        store.extensions.filter { (!installedOnly || $0.installed) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.lang.localizedCaseInsensitiveContains(search)) }
            .sorted { left, right in
                if left.installed != right.installed { return left.installed }
                if left.isNsfw != right.isNsfw { return !left.isNsfw }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageIntro(title: "Sources, your way", subtitle: "Add a repository you trust, then install its source extensions.")
            HStack {
                TextField("Extension repository index URL", text: $repository).textFieldStyle(.roundedBorder)
                Button("Add Repository") { addRepository() }.disabled(repository.isEmpty || store.busy)
            }
            ForEach(repositories, id: \.self) { repo in
                HStack { Text(repo).font(.caption).textSelection(.enabled); Spacer(); Button("Remove") { Task { await store.perform {
                    _ = try await store.api.graphql("mutation($input: RemoveExtensionStoreInput!) { removeExtensionStore(input: $input) { clientMutationId } }", variables: ["input": ["indexUrl": repo]])
                    try await load()
                } } }.disabled(store.busy) }
            }
            HStack {
                TextField("Filter extensions by name or language", text: $search).textFieldStyle(.roundedBorder)
                Toggle("Installed", isOn: $installedOnly).toggleStyle(.checkbox)
                Button("Refresh List") { Task { await store.perform { try await load() } } }.disabled(store.busy)
            }
            if filtered.isEmpty { EmptyShelf(symbol: "puzzlepiece.extension", title: "No extensions to show", subtitle: repositories.isEmpty ? "Add your repository’s index URL above." : "Try Refresh List or clear the name and Installed filters.") }
            else {
                List(filtered) { ext in
                    HStack(spacing: 14) {
                        Image(systemName: "puzzlepiece.extension").font(.title2).foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ext.name).font(.headline)
                            Text("\(ext.lang.uppercased()) · \(ext.versionName)\(ext.isNsfw ? " · NSFW" : "")\(ext.obsolete ? " · obsolete" : "")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if ext.hasUpdate { Button("Update") { action("update", ext) }.disabled(store.busy) }
                        Button(ext.installed ? "Uninstall" : "Install") { action(ext.installed ? "uninstall" : "install", ext) }.disabled(store.busy || ext.obsolete)
                    }.padding(.vertical, 7)
                }.listStyle(.plain)
            }
        }.padding(28).task { await store.perform { try await load() } }
    }

    private func load() async throws {
        let result = try await store.api.graphql("{ extensionStores { nodes { indexUrl } } }")
        repositories = ((result["extensionStores"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { $0["indexUrl"] as? String }
        store.extensions = try await store.api.get("extension/list")
    }
    private func addRepository() {
        guard let url = URL(string: repository.trimmingCharacters(in: .whitespacesAndNewlines)), ["https", "http"].contains(url.scheme ?? ""), url.host != nil else { store.error = "Enter a complete repository index URL."; return }
        Task { await store.perform {
            _ = try await store.api.graphql("mutation($input: AddExtensionStoreInput!) { addExtensionStore(input: $input) { extensionStore { indexUrl } } }", variables: ["input": ["indexUrl": url.absoluteString]])
            repository = ""
            try await load()
            for _ in 0..<5 where store.extensions.isEmpty {
                try await Task.sleep(for: .seconds(1))
                try await load()
            }
            store.notice = "Repository added. Choose the source extensions you want to install."
        } }
    }
    private func action(_ action: String, _ ext: SourceExtension) { Task { await store.perform {
        try await store.api.action("extension/\(action)/\(ext.pkgName)")
        try await load()
        try await store.refresh()
    } } }
}

struct BackupView: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageIntro(title: "Bring your library with you", subtitle: "Import and export Mihon / Tachiyomi compatible library backups.")
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Restore from Android", systemImage: "arrow.down.doc").font(.title3.bold())
                    Text("Select a .tachibk or .proto.gz backup. Validation reports missing sources and trackers before you restore. A recovery backup is saved on this Mac first.").foregroundStyle(.secondary)
                    Button("Choose Backup to Restore…") { store.restoreBackup() }.buttonStyle(.borderedProminent).disabled(store.busy)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Save your progress", systemImage: "arrow.up.doc").font(.title3.bold())
                    Text("Exports library titles, categories, chapter progress, history, and supported tracking records. Comic files and downloaded page images must be copied separately.").foregroundStyle(.secondary)
                    Button("Export Library Backup…") { store.exportBackup() }.disabled(store.busy)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Compatibility: Android app/source preferences, extension stores, notes, excluded scanlators, and some update metadata do not round-trip through this engine. Keep your original Android backup.").font(.callout).foregroundStyle(.secondary)
            Spacer()
        }.padding(32).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsView: View {
    @ObservedObject var store: LibraryStore
    @AppStorage("readerRTL") private var rtl = false
    @AppStorage("readerDark") private var dark = true
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageIntro(title: "Make yourself at home", subtitle: "Your app and library live on this Mac.")
            GroupBox("Reader") {
                VStack(alignment: .leading, spacing: 12) { Toggle("Read right to left", isOn: $rtl); Toggle("Dark reading background", isOn: $dark) }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Library storage") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.backend.dataRoot.path).font(.caption).textSelection(.enabled).foregroundStyle(.secondary)
                    HStack {
                        Button("Show Library Folder") { NSWorkspace.shared.open(store.backend.dataRoot) }
                        Button("Open Engine Log") { NSWorkspace.shared.open(store.backend.dataRoot.appendingPathComponent("engine.log")) }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Advanced features") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The bundled Suwayomi control panel provides source preferences, advanced filters, downloads, scheduled updates, automatic backups, and migration tools while native screens are being built.").foregroundStyle(.secondary)
                    Button("Open Local Control Panel") { NSWorkspace.shared.open(store.api.base) }.disabled(!store.backend.ready)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Mihon Mac 0.1 · unofficial native macOS preview\nSwiftUI + AppKit · Suwayomi 2.4.2366 compatibility engine\nCore native screens are implemented; full Android parity is in progress.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
