import Foundation
import SwiftUI

// Use the property wrapper explicitly: macOS 27 CLT ships State macros without
// the Xcode-only SwiftUIMacros plugin. This alias also builds with older SDKs.
typealias ViewState<Value> = SwiftUI.State<Value>

struct Manga: Decodable, Identifiable, Hashable {
    let id: Int
    let sourceId: String
    let title: String
    var inLibrary: Bool
    var author: String?
    var artist: String?
    var description: String?
    var genre: [String]?
    var status: String?
    var unreadCount: Int?
    var chapterCount: Int?
    var downloadCount: Int?
    var lastReadAt: Int64?
    var source: Source?
    var trackers: [MangaTracker]?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Source: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let lang: String
    let displayName: String
    let supportsLatest: Bool
    let isConfigurable: Bool
    let isNsfw: Bool
}

struct Chapter: Decodable, Identifiable, Hashable {
    let id: Int
    let mangaId: Int
    let name: String
    let index: Int
    var read: Bool
    var bookmarked: Bool
    var downloaded: Bool
    var pageCount: Int
    var lastPageRead: Int
    var chapterNumber: Double
    var scanlator: String?
}

struct Category: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let order: Int
    var size: Int?
}

struct MangaPage: Decodable {
    let mangaList: [Manga]
    let hasNextPage: Bool
}

struct SourceExtension: Decodable, Identifiable {
    let pkgName: String
    var id: String { pkgName }
    let name: String
    let lang: String
    let versionName: String
    let installed: Bool
    let hasUpdate: Bool
    let obsolete: Bool
    let isNsfw: Bool
}

struct Tracker: Decodable, Identifiable {
    let id: Int
    let name: String
    let isLogin: Bool
    let authUrl: String?
}

struct TrackSearch: Decodable, Identifiable {
    let remoteId: Int64
    var id: Int64 { remoteId }
    let trackerId: Int
    let title: String
    let summary: String
    let totalChapters: Int
}

struct TrackRecord: Decodable, Identifiable {
    let id: Int
    let title: String
    let lastChapterRead: Double
    let totalChapters: Int
    let status: Int
    let score: Double
    let remoteUrl: String
}

struct MangaTracker: Decodable, Identifiable {
    let id: Int
    let name: String
    let statusList: [Int]
    let statusTextMap: [String: String]
    let scoreList: [String]
    let record: TrackRecord?
}

enum Shelf: String, CaseIterable, Identifiable {
    case library = "Library", updates = "Updates", history = "History", downloads = "Downloads", browse = "Browse", extensions = "Extensions"
    case tracking = "Tracking", backups = "Backups", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .library: "books.vertical"
        case .updates: "sparkles"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .browse: "safari"
        case .extensions: "puzzlepiece.extension"
        case .tracking: "chart.line.uptrend.xyaxis"
        case .backups: "externaldrive"
        case .settings: "gearshape"
        }
    }
}

struct RecentChapter: Decodable, Identifiable {
    let manga: Manga
    let chapter: Chapter
    var id: Int { chapter.id }
}

struct RecentPage: Decodable {
    let page: [RecentChapter]
    let hasNextPage: Bool
}

struct DownloadState: Decodable {
    let state: String
    let queue: [DownloadItem]
}

struct DownloadItem: Decodable, Identifiable {
    let state: String
    let progress: Double
    let tries: Int
    let position: Int
    let manga: DownloadManga
    let chapter: DownloadChapter
    var id: Int { chapter.id }
}

struct DownloadManga: Decodable { let id: Int; let title: String }
struct DownloadChapter: Decodable { let id: Int; let name: String; let mangaId: Int; let sourceOrder: Int }
