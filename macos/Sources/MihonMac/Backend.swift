import AppKit
import Foundation
import CryptoKit

@MainActor
final class Backend: ObservableObject {
    @Published var ready = false
    @Published var status = "Starting your library…"
    @Published var failure: String?
    let port: Int
    let dataRoot: URL
    let api: API
    private var process: Process?
    private var log: FileHandle?
    private var starting = false

    init() {
        let env = ProcessInfo.processInfo.environment
        port = Int(env["MIHON_PORT"] ?? "45679") ?? 45679
        api = API(port: port)
        dataRoot = env["MIHON_DATA"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MihonMac")
    }

    func start() async {
        guard process == nil, !starting else { return }
        starting = true
        defer { starting = false }
        failure = nil
        do {
            try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
            let root = ProcessInfo.processInfo.environment["MIHON_RUNTIME"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.resourceURL!.appendingPathComponent("Runtime")
            let java = root.appendingPathComponent("jre/bin/java")
            let jar = root.appendingPathComponent("Suwayomi-Server.jar")
            guard FileManager.default.isExecutableFile(atPath: java.path), FileManager.default.fileExists(atPath: jar.path) else {
                throw APIError(message: "The bundled reader engine is missing. Rebuild using macos/scripts/build-app.sh.")
            }
            // AndroidCompat/ClassGraph cannot discover resources in a JAR whose
            // pathname has spaces. Stage only the JAR/bootstrap in a safe cache;
            // the complete runtime remains bundled with the application.
            let engine = FileManager.default.temporaryDirectory.appendingPathComponent("MihonMac-engine-2.4.2366")
            try FileManager.default.createDirectory(at: engine, withIntermediateDirectories: true)
            let cachedJar = engine.appendingPathComponent("Suwayomi-Server.jar")
            let expectedSHA = "af9feb20af9d7ebe9e30769e6c6ebc7fc7ab1c447388d42e0280b1da5fe07bfd"
            func digest(_ url: URL) throws -> String {
                SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
            }
            if (try? digest(cachedJar)) != expectedSHA {
                guard try digest(jar) == expectedSHA else { throw APIError(message: "The bundled engine checksum does not match this release.") }
                if FileManager.default.fileExists(atPath: cachedJar.path) { try FileManager.default.removeItem(at: cachedJar) }
                try FileManager.default.copyItem(at: jar, to: cachedJar)
            }
            let bootstrap = try Data(contentsOf: root.appendingPathComponent("MihonEngine.class"))
            try bootstrap.write(to: engine.appendingPathComponent("MihonEngine.class"), options: .atomic)
            // Never adopt an unrelated server running on this port.
            let probe = URLRequest(url: api.url("api/v1/category"), timeoutInterval: 1)
            if let (_, response) = try? await URLSession.shared.data(for: probe), response is HTTPURLResponse {
                throw APIError(message: "Port \(port) is already in use. Quit the other Mihon Mac instance and try again.")
            }
            let logURL = dataRoot.appendingPathComponent("engine.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            log = try FileHandle(forWritingTo: logURL)
            let task = Process()
            task.executableURL = java
            task.arguments = ["-Xmx1g", "-Dsuwayomi.tachidesk.config.server.rootDir=\(dataRoot.path)", "-Dsuwayomi.tachidesk.config.server.ip=127.0.0.1", "-Dsuwayomi.tachidesk.config.server.port=\(port)", "-Dsuwayomi.tachidesk.config.server.initialOpenInBrowserEnabled=false", "-Dsuwayomi.tachidesk.config.server.systemTrayEnabled=false", "-Dsuwayomi.tachidesk.config.server.webUIFlavor=WEBUI", "-Dsuwayomi.tachidesk.config.server.webUIInterface=BROWSER", "-Dsuwayomi.tachidesk.config.server.webUIChannel=BUNDLED", "-Dsuwayomi.tachidesk.config.server.webUIUpdateCheckInterval=0", "-Dsuwayomi.tachidesk.config.server.debugLogsEnabled=false", "-cp", "\(cachedJar.path):\(engine.path)", "MihonEngine"]
            task.currentDirectoryURL = engine
            task.standardOutput = log
            task.standardError = log
            try task.run()
            process = task
            for _ in 0..<90 {
                guard task.isRunning else { throw APIError(message: "The reader engine stopped. Open engine.log in Settings for details.") }
                if let _: [Category] = try? await api.get("category") {
                    ready = true
                    status = "Library ready · on this Mac"
                    return
                }
                try await Task.sleep(for: .seconds(1))
            }
            throw APIError(message: "The reader engine took too long to start. Open engine.log in Settings.")
        } catch {
            failure = error.localizedDescription
            status = "Couldn’t start the reader engine"
            stop()
        }
    }

    func stop() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        try? log?.close()
        log = nil
        ready = false
    }
}
