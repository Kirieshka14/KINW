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

        // 1. Check for Ren'Py Visual Novel
        let renpyCandidates = [
            "assets/x-game",
            "assets/game",
            "base/game",
            "assets/x-game/game",
            "assets/game/script.rpyc"
        ]
        for candidate in renpyCandidates {
            let path = rootDirectory.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: path.path) {
                return EngineDetectionResult(
                    engine: .renpy,
                    entryPoint: candidate,
                    details: "Detected Ren'Py visual novel scripts and assets"
                )
            }
        }
        
        // Check for .rpa files anywhere in rootDirectory
        if let enumerator = fileManager.enumerator(at: rootDirectory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "rpa" || fileURL.pathExtension.lowercased() == "rpyc" {
                    return EngineDetectionResult(
                        engine: .renpy,
                        entryPoint: fileURL.lastPathComponent,
                        details: "Detected Ren'Py RPA archive/RPYC scripts"
                    )
                }
            }
        }

        // 2. Check for RPG Maker MV / MZ
        let rpgMakerCandidates = [
            "assets/www/data/System.json",
            "assets/data/System.json"
        ]
        for candidate in rpgMakerCandidates {
            let path = rootDirectory.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: path.path) {
                let htmlPath = rootDirectory.appendingPathComponent("assets/www/index.html")
                return EngineDetectionResult(
                    engine: .rpgMaker,
                    entryPoint: fileManager.fileExists(atPath: htmlPath.path) ? "assets/www/index.html" : "index.html",
                    details: "Detected RPG Maker MV/MZ project with JSON data"
                )
            }
        }

        // 3. Check for Web / Tyranobuilder / HTML5 Novel
        let webCandidates = [
            "assets/www/index.html",
            "assets/index.html",
            "assets/www/data/scenario",
            "assets/scenario"
        ]
        for candidate in webCandidates {
            let path = rootDirectory.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: path.path) {
                let isTyrano = fileManager.fileExists(atPath: rootDirectory.appendingPathComponent("assets/www/data/scenario").path)
                return EngineDetectionResult(
                    engine: .webNovel,
                    entryPoint: candidate.hasSuffix(".html") ? candidate : "assets/www/index.html",
                    details: isTyrano ? "Detected Tyranobuilder visual novel" : "Detected HTML5/WebGL web novel"
                )
            }
        }

        // 4. Check for Godot
        let godotCandidates = [
            "assets/project.pck",
            "assets/main.pck",
            "project.pck"
        ]
        for candidate in godotCandidates {
            let path = rootDirectory.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: path.path) {
                return EngineDetectionResult(
                    engine: .godot,
                    entryPoint: candidate,
                    details: "Detected Godot Engine PCK archive"
                )
            }
        }

        // 5. Check for GameMaker
        let gmCandidates = [
            "assets/game.droid",
            "assets/data.win"
        ]
        for candidate in gmCandidates {
            let path = rootDirectory.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: path.path) {
                return EngineDetectionResult(
                    engine: .gameMaker,
                    entryPoint: candidate,
                    details: "Detected GameMaker Studio byte-data runner"
                )
            }
        }

        // 6. Check for LÖVE2D
        let lovePath = rootDirectory.appendingPathComponent("assets/game.love")
        if fileManager.fileExists(atPath: lovePath.path) {
            return EngineDetectionResult(
                engine: .love2d,
                entryPoint: "assets/game.love",
                details: "Detected LÖVE2D game archive"
            )
        }

        // 7. Check for Unity
        let unityPaths = [
            "lib/arm64-v8a/libunity.so",
            "lib/armeabi-v7a/libunity.so"
        ]
        for candidate in unityPaths {
            let path = rootDirectory.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: path.path) {
                return EngineDetectionResult(
                    engine: .unity,
                    entryPoint: candidate,
                    details: "Detected Unity 2D/3D IL2CPP engine library"
                )
            }
        }

        return EngineDetectionResult(
            engine: .unknown,
            entryPoint: "",
            details: "No recognized 2D engine signature found"
        )
    }
}
