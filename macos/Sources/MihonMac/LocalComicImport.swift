import Foundation

enum LocalComicImport {
    static let images: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "avif"]
    static let archives: Set<String> = ["cbz", "zip"]

    struct Plan {
        let name: String
        let source: URL
        let destination: URL
    }

    static func plan(_ url: URL, root: URL) throws -> Plan {
        let source = url.resolvingSymlinksInPath().standardizedFileURL
        let local = root.resolvingSymlinksInPath().standardizedFileURL
        let isDirectory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        let name = isDirectory ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        let series = local.appendingPathComponent(name, isDirectory: true)
        let destination: URL
        if isDirectory {
            guard local.path != source.path, !local.path.hasPrefix(source.path + "/") else {
                throw APIError(message: "Choose a comic folder outside the library storage folder.")
            }
            let contents = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            if contents.contains(where: { images.contains($0.pathExtension.lowercased()) }) {
                destination = series.appendingPathComponent("Chapter 1", isDirectory: true)
            } else if try contents.contains(where: { item in
                if archives.contains(item.pathExtension.lowercased()) { return true }
                guard try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { return false }
                return try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).contains { images.contains($0.pathExtension.lowercased()) }
            }) {
                destination = series
            } else {
                throw APIError(message: "\(name) contains no page images or CBZ/ZIP chapters.")
            }
        } else {
            guard archives.contains(source.pathExtension.lowercased()) else { throw APIError(message: "Choose a CBZ/ZIP archive or a comic folder.") }
            destination = series.appendingPathComponent(source.lastPathComponent)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw APIError(message: "\(name) already exists. Rename the new file or folder before importing it.")
        }
        return Plan(name: name, source: source, destination: destination)
    }
}
