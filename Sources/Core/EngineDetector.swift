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
                let rel = fileURL.path.replacingOccurrences(of: rootDirectory.path + "/", with: "")
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
        if let htmlFile = allFiles.first(where: { $0.lowercased().hasPrefix("assets/") && $0.lowercased().hasSuffix("index.html") }) {
            return EngineDetectionResult(
                engine: .webNovel,
                entryPoint: htmlFile,
                details: "Detected Web/HTML5 game at \(htmlFile)"
            )
        }

        // 4. Check for Godot
        for file in allFiles {
            let lower = file.lowercased()
            if lower.hasSuffix(".pck") || lower.contains("libgodot_android.so") {
                return EngineDetectionResult(
                    engine: .godot,
                    entryPoint: file,
                    details: "Detected Godot PCK archive (\(file))"
                )
            }
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

        return EngineDetectionResult(
            engine: .unknown,
            entryPoint: allFiles.first ?? "",
            details: "No recognized engine signature found"
        )
    }
}
