import Foundation

/// High-performance native Godot PCK builder.
/// Converts loose game assets (from Google Play Asset Delivery / Sparse PCK exports)
/// into a standard monolithic Godot PCK archive (Format Version 2) compatible with Godot 4.
public final class GodotPCKBuilder {

    private struct PackFileItem {
        let sourceURL: URL
        let godotPath: String
        let paddedPathData: Data
        let fileSize: Int64
    }

    /// Scans the bottle directory and builds a unified `game.pck` archive.
    /// - Parameters:
    ///   - bottleDir: Root directory of the game bottle (containing `assets/` or loose game files).
    ///   - outputPCKURL: Destination URL for the generated `game.pck`.
    ///   - onProgress: Status update callback for progress bars.
    /// - Returns: `true` if package was created successfully, `false` otherwise.
    public static func buildPCK(
        from bottleDir: URL,
        outputPCKURL: URL,
        onProgress: ((String, Float) -> Void)? = nil
    ) throws -> Bool {
        let fileManager = FileManager.default

        onProgress?("Scanning game assets...", 0.02)

        let assetsDir = bottleDir.appendingPathComponent("assets")
        let searchDir = fileManager.fileExists(atPath: assetsDir.path) ? assetsDir : bottleDir

        guard let enumerator = fileManager.enumerator(at: searchDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return false
        }

        var items: [PackFileItem] = []
        var seenGodotPaths = Set<String>()

        for case let fileURL as URL in enumerator {
            guard !fileURL.hasDirectoryPath else { continue }
            let ext = fileURL.pathExtension.lowercased()
            let fileName = fileURL.lastPathComponent.lowercased()
            let lowerPath = fileURL.path.lowercased()

            // Skip archives, system files, and destination PCK
            if ext == "apk" || ext == "pck" || ext == "sparsepck" || ext == "dylib" || ext == "so" || ext == "dex" {
                continue
            }
            if fileName.hasPrefix(".") && fileName != ".godot" {
                // Skip hidden Unix files like .DS_Store, but KEEP .godot directory files!
                if !fileURL.path.contains("/.godot/") {
                    continue
                }
            }
            if fileName == "androidmanifest.xml" || fileName == "resources.arsc" {
                continue
            }

            // Skip Android system folders if searching bottle root
            if searchDir == bottleDir {
                if lowerPath.contains("/lib/") || lowerPath.contains("/meta-inf/") || lowerPath.contains("/res/values") || lowerPath.contains("/res/drawable") || lowerPath.contains("/res/xml") {
                    continue
                }
            }

            var rel = fileURL.relativePath(from: searchDir)
            if searchDir != assetsDir && rel.hasPrefix("assets/") {
                rel = String(rel.dropFirst(7))
            }
            rel = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            let godotPath = "res://" + rel
            guard !seenGodotPaths.contains(godotPath) else { continue }
            seenGodotPaths.insert(godotPath)

            // UTF-8 path padded with null bytes to 4-byte alignment
            var pathBytes = Data(godotPath.utf8)
            let rem = pathBytes.count % 4
            let pad = rem > 0 ? (4 - rem) : 0
            if pad > 0 {
                pathBytes.append(contentsOf: [UInt8](repeating: 0, count: pad))
            }

            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            items.append(PackFileItem(
                sourceURL: fileURL,
                godotPath: godotPath,
                paddedPathData: pathBytes,
                fileSize: Int64(size)
            ))
        }

        // Fallback: If project configuration wasn't in assetsDir, check bottle root
        if !items.contains(where: { $0.godotPath == "res://project.binary" || $0.godotPath == "res://project.godot" }) {
            for name in ["project.binary", "project.godot"] {
                let candidate = bottleDir.appendingPathComponent(name)
                if fileManager.fileExists(atPath: candidate.path) {
                    let godotPath = "res://" + name
                    var pathBytes = Data(godotPath.utf8)
                    let rem = pathBytes.count % 4
                    let pad = rem > 0 ? (4 - rem) : 0
                    if pad > 0 {
                        pathBytes.append(contentsOf: [UInt8](repeating: 0, count: pad))
                    }
                    let size = (try? candidate.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    items.insert(PackFileItem(
                        sourceURL: candidate,
                        godotPath: godotPath,
                        paddedPathData: pathBytes,
                        fileSize: Int64(size)
                    ), at: 0)
                    seenGodotPaths.insert(godotPath)
                    break
                }
            }
        }

        guard !items.isEmpty else {
            print("[GodotPCKBuilder] No game assets found to pack.")
            return false
        }

        // Must have project configuration file to be a valid Godot game
        let hasConfig = items.contains(where: {
            $0.godotPath == "res://project.binary" || $0.godotPath == "res://project.godot"
        })
        guard hasConfig else {
            print("[GodotPCKBuilder] No project.binary or project.godot found among assets.")
            return false
        }

        print("[GodotPCKBuilder] Packing \(items.count) files into \(outputPCKURL.lastPathComponent)...")
        onProgress?("Preparing package index (\(items.count) files)...", 0.05)

        // Calculate PCK Format Version 2 layout:
        // Header: 96 bytes (32 bytes header + 64 bytes reserved)
        // Directory count: 4 bytes (UInt32)
        // Each entry: 4 (string_len) + paddedPath.count + 8 (ofs) + 8 (size) + 16 (md5) + 4 (flags)
        var totalDirSize: Int64 = 4 // file_count
        for item in items {
            totalDirSize += Int64(4 + item.paddedPathData.count + 8 + 8 + 16 + 4)
        }

        let headerSize: Int64 = 96
        var currentOffset: UInt64 = UInt64(headerSize + totalDirSize)

        // Align first data offset to 16 bytes
        let initialAlignmentPad = Int((16 - (currentOffset % 16)) % 16)
        currentOffset += UInt64(initialAlignmentPad)

        // Remove old output file if present
        if fileManager.fileExists(atPath: outputPCKURL.path) {
            try? fileManager.removeItem(at: outputPCKURL)
        }
        fileManager.createFile(atPath: outputPCKURL.path, contents: nil)

        let outHandle = try FileHandle(forWritingTo: outputPCKURL)
        defer { try? outHandle.close() }

        // 1. Write Header (96 bytes)
        var header = Data()
        var magic: UInt32 = 0x43504447 // "GDPC"
        var version: UInt32 = 2        // PCK version 2
        var verMajor: UInt32 = 4
        var verMinor: UInt32 = 7
        var verPatch: UInt32 = 2
        var packFlags: UInt32 = 0      // 0 = clean monolithic pack (NOT sparse)
        var fileBase: UInt64 = 0

        header.append(Data(bytes: &magic, count: 4))
        header.append(Data(bytes: &version, count: 4))
        header.append(Data(bytes: &verMajor, count: 4))
        header.append(Data(bytes: &verMinor, count: 4))
        header.append(Data(bytes: &verPatch, count: 4))
        header.append(Data(bytes: &packFlags, count: 4))
        header.append(Data(bytes: &fileBase, count: 8))
        header.append(Data(repeating: 0, count: 64)) // 16 * 4 reserved

        outHandle.write(header)

        // 2. Write Directory (file count + entries)
        var dirData = Data()
        var countUInt = UInt32(items.count)
        dirData.append(Data(bytes: &countUInt, count: 4))

        var filePayloadOffsets: [UInt64] = []
        for item in items {
            var stringLen = UInt32(item.paddedPathData.count)
            var ofs = currentOffset
            var sz = UInt64(item.fileSize)
            var flags: UInt32 = 0

            dirData.append(Data(bytes: &stringLen, count: 4))
            dirData.append(item.paddedPathData)
            dirData.append(Data(bytes: &ofs, count: 8))
            dirData.append(Data(bytes: &sz, count: 8))
            dirData.append(Data(repeating: 0, count: 16)) // md5 hash zeroes
            dirData.append(Data(bytes: &flags, count: 4))

            filePayloadOffsets.append(currentOffset)

            // Advance offset for payload + 16-byte alignment
            currentOffset += UInt64(item.fileSize)
            let pad = Int((16 - (currentOffset % 16)) % 16)
            currentOffset += UInt64(pad)
        }

        if initialAlignmentPad > 0 {
            dirData.append(Data(repeating: 0, count: initialAlignmentPad))
        }

        outHandle.write(dirData)

        // 3. Write File Payloads in 64 KB streaming chunks
        let totalFiles = Float(items.count)
        let chunkSize = 64 * 1024

        for (idx, item) in items.enumerated() {
            var writtenBytes: Int64 = 0
            if let inHandle = try? FileHandle(forReadingFrom: item.sourceURL) {
                while writtenBytes < item.fileSize {
                    let toRead = min(chunkSize, Int(item.fileSize - writtenBytes))
                    let chunk = inHandle.readData(ofLength: toRead)
                    if chunk.isEmpty { break }
                    outHandle.write(chunk)
                    writtenBytes += Int64(chunk.count)
                }
                try? inHandle.close()
            }

            // Fill missing bytes with 0 if file shrank or failed to read
            if writtenBytes < item.fileSize {
                let missing = Int(item.fileSize - writtenBytes)
                outHandle.write(Data(repeating: 0, count: missing))
            }

            // Align file end to 16 bytes
            let pad = Int((16 - (item.fileSize % 16)) % 16)
            if pad > 0 {
                outHandle.write(Data(repeating: 0, count: pad))
            }

            if idx % 15 == 0 || idx == items.count - 1 {
                let prog = 0.08 + (Float(idx + 1) / totalFiles) * 0.90
                let fileName = item.sourceURL.lastPathComponent
                onProgress?("Packaging: \(fileName) (\(idx + 1)/\(items.count))", prog)
            }
        }

        onProgress?("Game archive ready!", 1.0)
        print("[GodotPCKBuilder] Successfully built \(outputPCKURL.path) with \(items.count) files.")
        return true
    }
}
