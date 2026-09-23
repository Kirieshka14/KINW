import Foundation

public enum GameEngineType: String, Codable, CaseIterable, Identifiable {
    case renpy = "Ren'Py"
    case webNovel = "Web / Tyranobuilder"
    case rpgMaker = "RPG Maker (MV/MZ)"
    case godot = "Godot"
    case gameMaker = "GameMaker"
    case love2d = "LÖVE2D"
    case unity = "Unity 2D"
    case genericNative = "Native C++"
    case unknown = "Unknown Engine"

    public var id: String { rawValue }

    public var badgeColor: String {
        switch self {
        case .renpy: return "purple"
        case .webNovel, .rpgMaker: return "blue"
        case .godot: return "cyan"
        case .gameMaker: return "green"
        case .love2d: return "pink"
        case .unity: return "orange"
        case .genericNative: return "indigo"
        case .unknown: return "gray"
        }
    }

    public var iconName: String {
        switch self {
        case .renpy: return "book.closed.fill"
        case .webNovel, .rpgMaker: return "globe"
        case .godot: return "gearshape.2.fill"
        case .gameMaker: return "gamecontroller.fill"
        case .love2d: return "heart.fill"
        case .unity: return "cube.fill"
        case .genericNative: return "cpu.fill"
        case .unknown: return "questionmark.app.dashed"
        }
    }
}

public struct EngineDetectionResult {
    public let engine: GameEngineType
    public let entryPoint: String
    public let details: String
}

public final class EngineDetector {
    public static let shared = EngineDetector()

    private init() {}

    public func detect(in rootDirectory: URL) -> EngineDetectionResult {
        let fileManager = FileManager.default

        // Collect all file relative paths for deep signature analysis
        var allFiles: [String] = []
        if let enumerator = fileManager.enumerator(at: rootDirectory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                let rel = fileURL.relativePath(from: rootDirectory)
                allFiles.append(rel)
            }
        }

        // 1. Check for Ren'Py Visual Novel
        for file in allFiles {
            let lower = file.lowercased()
            if lower.contains("librenpy.so") || lower.contains("libpython3") || lower.hasSuffix(".rpa") || lower.hasSuffix(".rpyc") || lower.contains("x-game") || lower.contains("base/game") {
                return EngineDetectionResult(
                    engine: .renpy,
                    entryPoint: file,
                    details: "Detected Ren'Py scripts/libraries (\(file))"
                )
            }
        }

        // 2. Check for RPG Maker MV / MZ
        for file in allFiles {
            let lower = file.lowercased()
            if lower.contains("data/system.json") || lower.contains("rpg_core.js") || lower.contains("rmmz_core.js") {
                let htmlEntry = allFiles.first(where: { $0.lowercased().hasSuffix("index.html") }) ?? "assets/www/index.html"
                return EngineDetectionResult(
                    engine: .rpgMaker,
                    entryPoint: htmlEntry,
                    details: "Detected RPG Maker MV/MZ project"
                )
            }
        }

        // 3. Check for Web / Tyranobuilder / HTML5 Novel
        for file in allFiles {
            let lower = file.lowercased()
            if lower.contains("data/scenario") || lower.contains("tyrano") {
                let htmlEntry = allFiles.first(where: { $0.lowercased().hasSuffix("index.html") }) ?? "assets/www/index.html"
                return EngineDetectionResult(
                    engine: .webNovel,
                    entryPoint: htmlEntry,
                    details: "Detected Tyranobuilder visual novel"
                )
            }
        }

        // Check if ANY index.html or .html exists in assets
        if let htmlFile = allFiles.first(where: { 
            let l = $0.lowercased()
            return l.hasPrefix("assets/") && (l.hasSuffix(".html") || l.hasSuffix(".htm"))
        }) {
            return EngineDetectionResult(
                engine: .webNovel,
                entryPoint: htmlFile,
                details: "Detected Web/HTML5 game at \(htmlFile)"
            )
        }

        // 4. Check for Godot
        var godotCandidates: [(file: String, version: String, size: Int64)] = []
        for file in allFiles {
            let fullURL = rootDirectory.appendingPathComponent(file)
            let info = godotPCKInfo(at: fullURL)
            if info.isPCK {
                godotCandidates.append((file: file, version: info.versionText, size: info.size))
            }
        }
        if !godotCandidates.isEmpty {
            godotCandidates.sort { $0.size > $1.size }
            let best = godotCandidates[0]
            let sizeMB = String(format: "%.1f MB", Double(best.size) / (1024 * 1024))
            return EngineDetectionResult(
                engine: .godot,
                entryPoint: best.file,
                details: "Detected \(best.version) archive (\(best.file), \(sizeMB))"
            )
        }
        if let godotSo = allFiles.first(where: { $0.lowercased().contains("libgodot_android.so") }) {
            return EngineDetectionResult(
                engine: .godot,
                entryPoint: godotSo,
                details: "Detected Godot Engine binary (\(godotSo))"
            )
        }

        // 5. Check for GameMaker
        for file in allFiles {
            let lower = file.lowercased()
            if lower.hasSuffix("game.droid") || lower.hasSuffix("data.win") || lower.contains("libyoyo.so") {
                return EngineDetectionResult(
                    engine: .gameMaker,
                    entryPoint: file,
                    details: "Detected GameMaker Studio runner (\(file))"
                )
            }
        }

        // 6. Check for LÖVE2D
        for file in allFiles {
            let lower = file.lowercased()
            if lower.hasSuffix("game.love") || lower.contains("liblove.so") {
                return EngineDetectionResult(
                    engine: .love2d,
                    entryPoint: file,
                    details: "Detected LÖVE2D game archive"
                )
            }
        }

        // 7. Check for Unity
        for file in allFiles {
            let lower = file.lowercased()
            if lower.contains("libunity.so") || lower.contains("libil2cpp.so") {
                return EngineDetectionResult(
                    engine: .unity,
                    entryPoint: file,
                    details: "Detected Unity 2D/3D IL2CPP engine"
                )
            }
        }

        // 8. General fallback for any HTML file in the entire package
        if let anyHtml = allFiles.first(where: { $0.lowercased().hasSuffix(".html") }) {
            return EngineDetectionResult(
                engine: .webNovel,
                entryPoint: anyHtml,
                details: "Detected generic HTML5 entry point at \(anyHtml)"
            )
        }

        // 9. Native C++ with discovered .so library
        if let firstSo = allFiles.first(where: { $0.hasSuffix(".so") }) {
            return EngineDetectionResult(
                engine: .genericNative,
                entryPoint: firstSo,
                details: "Native Android shared object library: \(firstSo)"
            )
        }

        let nonApkFiles = allFiles.filter { !$0.lowercased().hasSuffix(".apk") }
        return EngineDetectionResult(
            engine: .unknown,
            entryPoint: nonApkFiles.first ?? "",
            details: "No recognized engine signature found"
        )
    }

    private func godotPCKInfo(at url: URL) -> (isPCK: Bool, versionText: String, size: Int64) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (false, "", 0) }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 20)
        guard header.count >= 4 else { return (false, "", 0) }
        let isPCK = header.prefix(4) == Data([0x47, 0x44, 0x50, 0x43]) // "GDPC"
        guard isPCK else { return (false, "", 0) }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0

        if header.count >= 16 {
            let major = Int(header[8]) | (Int(header[9]) << 8) | (Int(header[10]) << 16) | (Int(header[11]) << 24)
            let minor = Int(header[12]) | (Int(header[13]) << 8) | (Int(header[14]) << 16) | (Int(header[15]) << 24)
            if major > 0 {
                return (true, "Godot \(major).\(minor)", fileSize)
            }
        }
        return (true, "Godot PCK", fileSize)
    }
}
