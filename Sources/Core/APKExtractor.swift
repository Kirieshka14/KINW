import Foundation

public struct APKMetadata {
    public let packageName: String
    public let appLabel: String
    public let versionName: String
    public let versionCode: Int
    public let mainActivity: String
    public let screenOrientation: String
    public let iconData: Data?
}

public enum APKExtractionError: Error, LocalizedError {
    case fileNotFound(String)
    case manifestReadFailed
    case manifestParseFailed
    case extractionFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "APK file not found at path: \(path)"
        case .manifestReadFailed:
            return "Failed to read AndroidManifest.xml from APK"
        case .manifestParseFailed:
            return "Failed to parse binary AndroidManifest.xml"
        case .extractionFailed(let code):
            return "Failed to extract APK archive (error code: \(code))"
        }
    }
}

public final class APKExtractor {
    public static let shared = APKExtractor()

    private init() {}

    /// Inspects the APK and extracts metadata without unpacking the entire file.
    public func inspect(apkURL: URL) throws -> APKMetadata {
        guard FileManager.default.fileExists(atPath: apkURL.path) else {
            throw APKExtractionError.fileNotFound(apkURL.path)
        }

        var manifestDataPtr: UnsafeMutablePointer<UInt8>? = nil
        var manifestSize: Int = 0

        let readRes = kinw_zip_read_file(apkURL.path, "AndroidManifest.xml", &manifestDataPtr, &manifestSize)
        var packageName = apkURL.deletingPathExtension().lastPathComponent
        var appLabel = packageName
        var versionName = "1.0"
        var versionCode = 1
        var mainActivity = ""
        var screenOrientation = "sensorLandscape"

        if readRes == 0, let dataPtr = manifestDataPtr, manifestSize > 0 {
            defer { free(manifestDataPtr) }
            var info = kinw_parse_manifest(dataPtr, manifestSize)
            if info.isSuccess != 0 {
                let parsedPackage = String(cString: getTuplePointer(&info.packageName))
                if !parsedPackage.isEmpty { packageName = parsedPackage }

                let parsedLabel = String(cString: getTuplePointer(&info.appLabel))
                if !parsedLabel.isEmpty && !parsedLabel.starts(with: "@") {
                    appLabel = parsedLabel
                }

                let parsedVersion = String(cString: getTuplePointer(&info.versionName))
                if !parsedVersion.isEmpty { versionName = parsedVersion }

                versionCode = Int(info.versionCode)
                mainActivity = String(cString: getTuplePointer(&info.mainActivity))

                let parsedOrientation = String(cString: getTuplePointer(&info.screenOrientation))
                if !parsedOrientation.isEmpty { screenOrientation = parsedOrientation }
            }
        }

        // Attempt to extract icon
        var iconData: Data? = nil
        let candidateIcons = [
            "res/mipmap-xxxhdpi/ic_launcher.png",
            "res/mipmap-xxhdpi/ic_launcher.png",
            "res/mipmap-xhdpi/ic_launcher.png",
            "res/mipmap-hdpi/ic_launcher.png",
            "res/drawable-xxhdpi/ic_launcher.png",
            "res/drawable/ic_launcher.png"
        ]

        for iconPath in candidateIcons {
            var iconPtr: UnsafeMutablePointer<UInt8>? = nil
            var iconSize: Int = 0
            if kinw_zip_read_file(apkURL.path, iconPath, &iconPtr, &iconSize) == 0,
               let ptr = iconPtr, iconSize > 0 {
                iconData = Data(bytes: ptr, count: iconSize)
                free(iconPtr)
                break
            }
        }

        return APKMetadata(
            packageName: packageName,
            appLabel: appLabel.isEmpty ? packageName : appLabel,
            versionName: versionName,
            versionCode: versionCode,
            mainActivity: mainActivity,
            screenOrientation: screenOrientation.isEmpty ? "sensorLandscape" : screenOrientation,
            iconData: iconData
        )
    }

    /// Unpacks the entire APK into the target directory with async progress updates.
    public func extract(apkURL: URL, to destinationURL: URL, progress: @escaping (Float) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                class CallbackBox {
                    let progress: (Float) -> Void
                    init(progress: @escaping (Float) -> Void) { self.progress = progress }
                }
                let box = CallbackBox(progress: progress)
                let userPtr = Unmanaged.passRetained(box).toOpaque()

                let res = kinw_zip_extract(apkURL.path, destinationURL.path, { _, p, ptr in
                    guard let ptr = ptr else { return }
                    let b = Unmanaged<CallbackBox>.fromOpaque(ptr).takeUnretainedValue()
                    DispatchQueue.main.async {
                        b.progress(p)
                    }
                }, userPtr)

                _ = Unmanaged<CallbackBox>.fromOpaque(userPtr).takeRetainedValue()

                if res == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: APKExtractionError.extractionFailed(Int(res)))
                }
            }
        }
    }
}

// Helper to convert C fixed-size char arrays to pointers
private func getTuplePointer<T>(_ tuple: inout T) -> UnsafePointer<CChar> {
    return withUnsafePointer(to: &tuple) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { $0 }
    }
}
