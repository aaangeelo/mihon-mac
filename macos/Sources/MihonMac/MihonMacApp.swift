import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var backend: Backend?
    func applicationWillTerminate(_ notification: Notification) { backend?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MihonMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var backend: Backend
    @StateObject private var store: LibraryStore

    init() {
        let engine = Backend()
        _backend = StateObject(wrappedValue: engine)
        _store = StateObject(wrappedValue: LibraryStore(backend: engine))
    }

    var body: some Scene {
        WindowGroup("Mihon Mac") {
            ContentView(store: store, backend: backend)
                .frame(minWidth: 920, minHeight: 640)
                .tint(.indigo)
                .task {
                    delegate.backend = backend
                    await backend.start()
                    if backend.ready { await store.perform { try await store.refresh() } }
                }
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Comics…") { store.importComics() }.keyboardShortcut("o").disabled(!backend.ready)
                Button("Restore Backup…") { store.restoreBackup() }.disabled(!backend.ready)
                Button("Export Backup…") { store.exportBackup() }.disabled(!backend.ready)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh Library") { Task { await store.perform { try await store.refresh() } } }.keyboardShortcut("r").disabled(!backend.ready)
            }
        }
        Settings { SettingsView(store: store).padding(28).frame(width: 580) }
    }
}
