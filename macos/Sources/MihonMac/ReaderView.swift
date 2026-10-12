import SwiftUI

struct ReaderView: View {
    let api: API
    let session: ReadingSession
    let reportError: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewState private var chapter: Chapter
    @ViewState private var page: Int
    @ViewState private var loadedPage: Int? = nil
    @ViewState private var changing = false
    @ViewState private var error: String?
    @ViewState private var zoom: Double = 1
    @ViewState private var scrollPage: Int?
    @ViewState private var webtoonFrames: [Int: CGRect] = [:]
    @ViewState private var saveTask: Task<Void, Never>?
    @AppStorage("readerRTL") private var rtl = false
    @AppStorage("readerMode") private var mode = "Paged"
    @AppStorage("readerDark") private var dark = true

    init(api: API, session: ReadingSession, reportError: @escaping (String) -> Void) {
        self.api = api; self.session = session; self.reportError = reportError
        _chapter = State(initialValue: session.chapter)
        _page = State(initialValue: min(max(0, session.chapter.lastPageRead), max(0, session.chapter.pageCount - 1)))
        _scrollPage = State(initialValue: min(max(0, session.chapter.lastPageRead), max(0, session.chapter.pageCount - 1)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { Task { await saveTask?.value; dismiss() } } label: { Label("Close", systemImage: "xmark") }.keyboardShortcut(.cancelAction)
                VStack(alignment: .leading, spacing: 2) { Text(session.manga.title).font(.headline).lineLimit(1); Text(chapter.name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Picker("Mode", selection: $mode) { Text("Paged").tag("Paged"); Text("Webtoon").tag("Webtoon") }.frame(width: 150)
                Toggle("Right to left", isOn: $rtl).toggleStyle(.checkbox)
                Toggle("Dark", isOn: $dark).toggleStyle(.checkbox)
            }.padding(14)
            if let error {
                HStack { Text(error).foregroundStyle(.red); Spacer(); Button("Retry") { self.error = nil; loadedPage = nil }; Button("Dismiss") { self.error = nil } }.padding(12)
            }
            if changing { ProgressView("Loading chapter…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if mode == "Webtoon" {
                GeometryReader { viewport in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(0..<max(0, chapter.pageCount), id: \.self) { index in
                                    pageImage(index).frame(maxWidth: 900).id(index)
                                }
                            }.frame(maxWidth: .infinity).scrollTargetLayout()
                        }.coordinateSpace(name: "reader-scroll").background(dark ? Color.black : Color.white)
                            .scrollPosition(id: $scrollPage, anchor: .top)
                            .onAppear { scrollPage = page }
                            .onChange(of: chapter.id) { _, _ in scrollPage = page }
                            .onChange(of: scrollPage) { _, _ in
                                recordVisibleScrollPage(webtoonFrames, height: viewport.size.height)
                            }
                            .onPreferenceChange(PageFrames.self) { frames in
                                webtoonFrames = frames
                                recordVisibleScrollPage(frames, height: viewport.size.height)
                            }
                }
            } else {
                GeometryReader { geometry in
                    ScrollView([.vertical, .horizontal]) {
                        pageImage(page).frame(width: geometry.size.width * zoom, height: geometry.size.height * zoom)
                    }.background(dark ? Color.black : Color.white).id("\(chapter.id)-\(page)")
                }
            }
            HStack(spacing: 20) {
                Button { changeChapter(-1) } label: { Label("Previous Chapter", systemImage: "backward.end") }.disabled(changing || neighbor(-1) == nil)
                Spacer()
                if mode == "Paged" {
                    Menu {
                        Button("Fit Page") { zoom = 1 }
                        Button("150%") { zoom = 1.5 }
                        Button("200%") { zoom = 2 }
                        Button("300%") { zoom = 3 }
                    } label: { Image(systemName: "plus.magnifyingglass") }.menuStyle(.borderlessButton).frame(width: 42).help("Reader zoom")
                    Button { step(rtl ? 1 : -1) } label: { Image(systemName: "chevron.left") }.keyboardShortcut(.leftArrow, modifiers: []).disabled(changing || (rtl ? page >= chapter.pageCount - 1 : page == 0))
                    Text("\(page + 1) / \(chapter.pageCount)").monospacedDigit().frame(width: 100)
                    Button { step(rtl ? -1 : 1) } label: { Image(systemName: "chevron.right") }.keyboardShortcut(.rightArrow, modifiers: []).disabled(changing || (rtl ? page == 0 : page >= chapter.pageCount - 1))
                    Button("Next Page") { step(1) }.keyboardShortcut(.space, modifiers: []).disabled(changing || page >= chapter.pageCount - 1)
                } else { Text("\(chapter.pageCount) pages · continuous scroll").foregroundStyle(.secondary) }
                Spacer()
                Button { changeChapter(1) } label: { Label("Next Chapter", systemImage: "forward.end") }.disabled(changing || neighbor(1) == nil)
            }.padding(14)
        }.frame(minWidth: 950, minHeight: 720)
    }

    private func pageImage(_ index: Int) -> some View {
        AsyncImage(url: api.url("api/v1/manga/\(chapter.mangaId)/chapter/\(chapter.index)/page/\(index)")) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: PageFrames.self, value: mode == "Webtoon" ? [index: geometry.frame(in: .named("reader-scroll"))] : [:])
                    })
                    .onAppear { if mode == "Paged" { displayed(index) } }
            case .failure: VStack(spacing: 12) { Image(systemName: "exclamationmark.triangle"); Text("Couldn’t load page \(index + 1)"); Button("Reload Chapter") { reloadChapter() } }.foregroundStyle(dark ? .white : .black).frame(height: 460)
            default: ProgressView("Page \(index + 1)").frame(height: 460).foregroundStyle(dark ? .white : .black)
            }
        }
    }

    private func displayed(_ index: Int) {
        // Persist only pages that actually loaded, and serialize writes to keep progress ordered.
        guard loadedPage != index else { return }
        loadedPage = index
        let previous = saveTask
        let current = chapter
        saveTask = Task {
            await previous?.value
            do {
                var form = ["lastPageRead": String(index)]
                if index == current.pageCount - 1 { form["read"] = "true" }
                try await api.action("manga/\(current.mangaId)/chapter/\(current.index)", method: "PATCH", form: form)
            } catch { self.error = "Couldn’t save progress: \(error.localizedDescription)"; reportError(self.error!) }
        }
    }

    private func recordVisibleScrollPage(_ frames: [Int: CGRect], height: Double) {
        // Position bindings and layout preferences arrive separately, including on reverse scroll.
        // Lazy stacks preload images outside the viewport; those frames must not count as read.
        if let index = scrollPage, let frame = frames[index], frame.maxY > 0, frame.minY < height {
            page = index
            displayed(index)
        }
    }

    private func step(_ delta: Int) { page = min(max(0, page + delta), chapter.pageCount - 1); loadedPage = nil }
    private func neighbor(_ delta: Int) -> Chapter? {
        let ordered = session.chapters.sorted { $0.index < $1.index }
        guard let index = ordered.firstIndex(where: { $0.id == chapter.id }), ordered.indices.contains(index + delta) else { return nil }
        return ordered[index + delta]
    }
    private func changeChapter(_ delta: Int) { if let next = neighbor(delta) { load(next) } }
    private func reloadChapter() { load(chapter) }
    private func load(_ next: Chapter) {
        changing = true
        Task {
            await saveTask?.value
            do {
                let loaded: Chapter = try await api.get("manga/\(next.mangaId)/chapter/\(next.index)")
                guard loaded.pageCount > 0 else { throw APIError(message: "This chapter has no readable pages.") }
                chapter = loaded
                page = min(max(0, loaded.lastPageRead), loaded.pageCount - 1)
                loadedPage = nil
            } catch { self.error = error.localizedDescription }
            changing = false
        }
    }
}

private struct PageFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
