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
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
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

    /// Automatically unpacks all nested split APKs (e.g. assetPackInstallTime-*.apk, base.apk, config.*.apk)
    public func unpackNestedAPKs(in bottleDir: URL, onProgress: ((String, Float) -> Void)? = nil) async -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(at: bottleDir, includingPropertiesForKeys: nil) else {
            return false
        }

        let apks = contents.filter { $0.pathExtension.lowercased() == "apk" }
            .sorted { a, b in
                let an = a.lastPathComponent.lowercased()
                let bn = b.lastPathComponent.lowercased()
                if an.contains("assetpack") { return true }
                if bn.contains("assetpack") { return false }
                if an.contains("base") { return true }
                if bn.contains("base") { return false }
                return an < bn
            }

        guard !apks.isEmpty else { return false }

        for (idx, apk) in apks.enumerated() {
            let name = apk.lastPathComponent
            let baseProg = Float(idx) / Float(apks.count)
            onProgress?("Extracting \(name)...", baseProg)
            print("[KINW-SplitAPK] Extracting: \(name)")
            try? await APKExtractor.shared.extract(apkURL: apk, to: bottleDir) { p in
                let current = baseProg + (p / Float(apks.count))
                onProgress?("Extracting \(name)...", current)
            }
        }

        return true
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
            self.importProgress = 0.15 + (progress * 0.40)
        }

        // Auto-extract any nested Split APK packages
        let hadSplits = await unpackNestedAPKs(in: bottleDir) { status, prog in
            DispatchQueue.main.async {
                self.importProgress = 0.55 + (prog * 0.35)
                self.importStatusText = status
            }
        }

        DispatchQueue.main.async {
            self.importProgress = 0.92
            self.importStatusText = hadSplits ? "Game packs extracted! Detecting engine..." : "Detecting game engine..."
        }

        let detection = EngineDetector.shared.detect(in: bottleDir)

        // Save icon if extracted
        if let iconData = metadata.iconData {
            let iconURL = bottleDir.appendingPathComponent("icon.png")
            try? iconData.write(to: iconURL)
        }

        var config = BottleConfig()
        config.orientation = metadata.screenOrientation.lowercased().contains("portrait") ? "portrait" : "landscape"

        // Generate clean display title if metadata title is just the raw package name or resource ID
        let displayTitle = BottleManager.formatCleanTitle(label: metadata.appLabel, packageName: metadata.packageName)

        let bottle = Bottle(
            id: bottleId,
            title: displayTitle,
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

    public static func formatCleanTitle(label: String, packageName: String) -> String {
        var title = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title == packageName || title.starts(with: "@") {
            let lastPart = packageName.split(separator: ".").last.map(String.init) ?? packageName
            var formatted = lastPart.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            formatted = formatted.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            if formatted.lowercased() == "interdimensionalvendingmachine" {
                return "Interdimensional Vending Machine"
            }
            title = formatted.capitalized
        }
        return title
    }

    public func updateBottle(_ updated: Bottle) {
        if let idx = bottles.firstIndex(where: { $0.id == updated.id }) {
            bottles[idx] = updated
            saveIndex()
        }
    }

    /// Automatically prepares a bottle: unpacks nested split APKs if any, detects engine, updates entryPoint and saves.
    public func prepareBottleIfNeeded(bottleId: String, onProgress: ((String, Float) -> Void)? = nil) async -> Bottle? {
        guard let idx = bottles.firstIndex(where: { $0.id == bottleId }) else { return nil }
        var currentBottle = bottles[idx]
        let dir = bottleDirectory(for: bottleId)

        let contents = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let apks = contents.filter { $0.pathExtension.lowercased() == "apk" }

        if !apks.isEmpty {
            _ = await unpackNestedAPKs(in: dir, onProgress: onProgress)
        }

        let detection = EngineDetector.shared.detect(in: dir)
        if detection.engine != .unknown {
            currentBottle.engine = detection.engine
            if !detection.entryPoint.isEmpty {
                currentBottle.entryPoint = detection.entryPoint
            }
        }

        currentBottle.title = BottleManager.formatCleanTitle(label: currentBottle.title, packageName: currentBottle.packageName)

        await MainActor.run {
            if let latestIdx = self.bottles.firstIndex(where: { $0.id == bottleId }) {
                self.bottles[latestIdx] = currentBottle
                self.saveIndex()
            }
        }
        return currentBottle
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

public extension URL {
    func relativePath(from base: URL) -> String {
        let basePath = base.resolvingSymlinksInPath().standardized.path
        let filePath = self.resolvingSymlinksInPath().standardized.path
        if filePath.hasPrefix(basePath) {
            let sub = filePath.dropFirst(basePath.count)
            return String(sub).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let rawBase = base.standardized.path
        let rawFile = self.standardized.path
        if rawFile.hasPrefix(rawBase) {
            let sub = rawFile.dropFirst(rawBase.count)
            return String(sub).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return self.lastPathComponent
    }
}
