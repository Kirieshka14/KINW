import Foundation
import Combine

public struct BottleConfig: Codable {
    public var targetFPS: Int = 60
    public var scaleMode: String = "fit" // fit, stretch, integer
    public var orientation: String = "landscape" // landscape, portrait, auto
    public var enableHaptics: Bool = true
    public var enableAudio: Bool = true

    public init() {}
}

public struct Bottle: Identifiable, Codable {
    public let id: String
    public var title: String
    public let packageName: String
    public var version: String
    public var engine: GameEngineType
    public var entryPoint: String
    public var createdDate: Date
    public var lastPlayedDate: Date?
    public var config: BottleConfig

    public init(
        id: String = UUID().uuidString,
        title: String,
        packageName: String,
        version: String,
        engine: GameEngineType,
        entryPoint: String,
        createdDate: Date = Date(),
        lastPlayedDate: Date? = nil,
        config: BottleConfig = BottleConfig()
    ) {
        self.id = id
        self.title = title
        self.packageName = packageName
        self.version = version
        self.engine = engine
        self.entryPoint = entryPoint
        self.createdDate = createdDate
        self.lastPlayedDate = lastPlayedDate
        self.config = config
    }
}

public final class BottleManager: ObservableObject {
    public static let shared = BottleManager()

    @Published public var bottles: [Bottle] = []
    @Published public var isImporting: Bool = false
    @Published public var importProgress: Float = 0.0
    @Published public var importStatusText: String = ""

    private let fileManager = FileManager.default
    private let indexFileName = "bottles.json"

    public var baseDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let bottlesDir = documents.appendingPathComponent("Bottles", isDirectory: true)
        if !fileManager.fileExists(atPath: bottlesDir.path) {
            try? fileManager.createDirectory(at: bottlesDir, withIntermediateDirectories: true)
        }
        return bottlesDir
    }

    private init() {
        loadBottles()
    }

    public func bottleDirectory(for bottleId: String) -> URL {
        return baseDirectory.appendingPathComponent(bottleId, isDirectory: true)
    }

    public func savesDirectory(for bottleId: String) -> URL {
        let saves = bottleDirectory(for: bottleId).appendingPathComponent("saves", isDirectory: true)
        if !fileManager.fileExists(atPath: saves.path) {
            try? fileManager.createDirectory(at: saves, withIntermediateDirectories: true)
        }
        return saves
    }

    public func iconURL(for bottleId: String) -> URL? {
        let iconPath = bottleDirectory(for: bottleId).appendingPathComponent("icon.png")
        return fileManager.fileExists(atPath: iconPath.path) ? iconPath : nil
    }

    public func loadBottles() {
        let indexFile = baseDirectory.appendingPathComponent(indexFileName)
        guard fileManager.fileExists(atPath: indexFile.path),
              let data = try? Data(contentsOf: indexFile),
              let decoded = try? JSONDecoder().decode([Bottle].self, from: data) else {
            bottles = []
            return
        }
        bottles = decoded
    }

    public func saveIndex() {
        let indexFile = baseDirectory.appendingPathComponent(indexFileName)
        if let data = try? JSONEncoder().encode(bottles) {
            try? data.write(to: indexFile, options: .atomic)
        }
    }

    public func createBottle(from apkURL: URL) async throws -> Bottle {
        DispatchQueue.main.async {
            self.isImporting = true
            self.importProgress = 0.05
            self.importStatusText = "Analyzing Android APK manifest..."
        }

        let metadata = try APKExtractor.shared.inspect(apkURL: apkURL)

        let bottleId = UUID().uuidString
        let bottleDir = self.bottleDirectory(for: bottleId)
        try fileManager.createDirectory(at: bottleDir, withIntermediateDirectories: true)

        DispatchQueue.main.async {
            self.importProgress = 0.15
            self.importStatusText = "Unpacking assets & classes..."
        }

        try await APKExtractor.shared.extract(apkURL: apkURL, to: bottleDir) { progress in
            self.importProgress = 0.15 + (progress * 0.70)
        }

        DispatchQueue.main.async {
            self.importProgress = 0.90
            self.importStatusText = "Detecting game engine..."
        }

        let detection = EngineDetector.shared.detect(in: bottleDir)

        // Save icon if extracted
        if let iconData = metadata.iconData {
            let iconURL = bottleDir.appendingPathComponent("icon.png")
            try? iconData.write(to: iconURL)
        }

        var config = BottleConfig()
        config.orientation = metadata.screenOrientation.lowercased().contains("portrait") ? "portrait" : "landscape"

        let bottle = Bottle(
            id: bottleId,
            title: metadata.appLabel,
            packageName: metadata.packageName,
            version: metadata.versionName.isEmpty ? "1.0" : metadata.versionName,
            engine: detection.engine,
            entryPoint: detection.entryPoint,
            createdDate: Date(),
            config: config
        )

        _ = savesDirectory(for: bottleId)

        DispatchQueue.main.async {
            self.bottles.insert(bottle, at: 0)
            self.saveIndex()
            self.importProgress = 1.0
            self.importStatusText = "Ready to play!"
            self.isImporting = false
        }

        return bottle
    }

    public func deleteBottle(_ bottle: Bottle) {
        let dir = bottleDirectory(for: bottle.id)
        try? fileManager.removeItem(at: dir)
        bottles.removeAll { $0.id == bottle.id }
        saveIndex()
    }

    public func updateLastPlayed(_ bottleId: String) {
        if let idx = bottles.firstIndex(where: { $0.id == bottleId }) {
            bottles[idx].lastPlayedDate = Date()
            saveIndex()
        }
    }
}
