import Foundation

public struct FileNode: Identifiable {
    public let id: String
    public let name: String
    public let relativePath: String
    public let isDirectory: Bool
    public let size: Int64
    public var children: [FileNode]?

    public var formattedSize: String {
        if isDirectory {
            return "\(children?.count ?? 0) items"
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: size)
    }
}

public final class FileInspector {
    public static let shared = FileInspector()

    private init() {}

    public func inspect(directory: URL, maxDepth: Int = 3) -> [FileNode] {
        return scanDirectory(directory, root: directory, currentDepth: 0, maxDepth: maxDepth)
    }

    private func scanDirectory(_ dir: URL, root: URL, currentDepth: Int, maxDepth: Int) -> [FileNode] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var nodes: [FileNode] = []

        for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let relative = item.relativePath(from: root)

            if isDir {
                let children = currentDepth < maxDepth ? scanDirectory(item, root: root, currentDepth: currentDepth + 1, maxDepth: maxDepth) : []
                nodes.append(FileNode(
                    id: relative,
                    name: item.lastPathComponent,
                    relativePath: relative,
                    isDirectory: true,
                    size: 0,
                    children: children
                ))
            } else {
                nodes.append(FileNode(
                    id: relative,
                    name: item.lastPathComponent,
                    relativePath: relative,
                    isDirectory: false,
                    size: size,
                    children: nil
                ))
            }
        }

        return nodes
    }
}
