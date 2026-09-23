import SwiftUI

public struct BottleDetailSheet: View {
    @Binding var bottle: Bottle
    let onPlay: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEngine: GameEngineType
    @State private var selectedOrientation: String
    @State private var selectedEntryPoint: String
    @State private var fileNodes: [FileNode] = []
    @State private var isLoadingFiles = true
    @State private var isExtractingSplit = false
    @State private var extractProgressText = ""
    @State private var showingDeleteAlert = false

    private var hasNestedAPKs: Bool {
        fileNodes.contains(where: { $0.name.hasSuffix(".apk") })
    }

    public init(bottle: Binding<Bottle>, onPlay: @escaping () -> Void) {
        self._bottle = bottle
        self.onPlay = onPlay
        self._selectedEngine = State(initialValue: bottle.wrappedValue.engine)
        self._selectedOrientation = State(initialValue: bottle.wrappedValue.config.orientation)
        self._selectedEntryPoint = State(initialValue: bottle.wrappedValue.entryPoint)
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.11).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Game Header Card
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(LinearGradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 72, height: 72)

                                Image(systemName: selectedEngine.iconName)
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundColor(.white)
                            }

                            Text(bottle.title)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text(bottle.packageName)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 16)

                        // Runner Configuration
                        VStack(alignment: .leading, spacing: 14) {
                            Text("RUNNER SETTINGS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)

                            VStack(spacing: 14) {
                                // Engine Switcher
                                HStack {
                                    Text("Engine Runner")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Engine", selection: $selectedEngine) {
                                        ForEach(GameEngineType.allCases) { eng in
                                            Text(eng.rawValue).tag(eng)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.cyan)
                                    .onChange(of: selectedEngine) { newEngine in
                                        autoSelectEntryPoint(for: newEngine)
                                    }
                                }

                                Divider().background(Color.white.opacity(0.1))

                                // Orientation
                                HStack {
                                    Text("Orientation")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Orientation", selection: $selectedOrientation) {
                                        Text("Landscape").tag("landscape")
                                        Text("Portrait").tag("portrait")
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 180)
                                }

                                Divider().background(Color.white.opacity(0.1))

                                // Entry Point
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Entry Point")
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                        Spacer()
                                        Button("Auto-Detect") {
                                            autoSelectEntryPoint(for: selectedEngine)
                                        }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.cyan)
                                    }

                                    TextField("Entry Path", text: $selectedEntryPoint)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                            .padding(16)
                            .background(Color(red: 0.12, green: 0.13, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        // Multi-Part Split APK Banner
                        if hasNestedAPKs {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: "shippingbox.fill")
                                        .font(.system(size: 26))
                                        .foregroundColor(.cyan)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Multi-Part Game Pack Detected")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                        Text(extractProgressText.isEmpty ? "Split APKs detected (Play Asset Delivery). Extract to unpack game data & engine." : extractProgressText)
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                }

                                Button(action: triggerSplitExtraction) {
                                    HStack {
                                        if isExtractingSplit {
                                            ProgressView().tint(.white).padding(.trailing, 6)
                                            Text("Extracting Game Data...")
                                        } else {
                                            Image(systemName: "arrow.down.circle.fill")
                                            Text("Extract Game Data Now")
                                        }
                                    }
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .disabled(isExtractingSplit)
                            }
                            .padding(16)
                            .background(Color.cyan.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.cyan.opacity(0.35), lineWidth: 1.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        // File Explorer / Assets Tree
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("PACKAGE ASSETS & FILES")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("Tap file to set entry point")
                                    .font(.system(size: 11))
                                    .foregroundColor(.cyan.opacity(0.8))
                            }
                            .padding(.horizontal, 4)

                            VStack(spacing: 8) {
                                if isLoadingFiles {
                                    ProgressView("Scanning package files...")
                                        .tint(.cyan)
                                        .foregroundColor(.gray)
                                        .padding(20)
                                } else if fileNodes.isEmpty {
                                    Text("No files found")
                                        .foregroundColor(.gray)
                                        .padding(20)
                                } else {
                                    ForEach(fileNodes.prefix(35)) { node in
                                        FileNodeRow(
                                            node: node,
                                            isEntryPoint: node.relativePath == selectedEntryPoint,
                                            onSelect: {
                                                if !node.isDirectory {
                                                    selectedEntryPoint = node.relativePath
                                                }
                                            }
                                        )
                                    }
                                    if fileNodes.count > 35 {
                                        Text("+ \(fileNodes.count - 35) more items...")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.gray)
                                            .padding(.top, 4)
                                    }
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 0.12, green: 0.13, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        // Actions: Launch Game
                        Button(action: {
                            saveChanges()
                            dismiss()
                            onPlay()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("Launch Game")
                            }
                            .font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .leading, endPoint: .trailing))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Color.blue.opacity(0.4), radius: 10, x: 0, y: 5)
                        }
                        .padding(.top, 8)

                        // Delete Bottle & Free Storage
                        Button(role: .destructive, action: { showingDeleteAlert = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash.fill")
                                Text("Delete Bottle & Free Storage")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .padding(.top, 4)
                        .alert("Delete Bottle?", isPresented: $showingDeleteAlert) {
                            Button("Cancel", role: .cancel) {}
                            Button("Delete", role: .destructive) {
                                BottleManager.shared.deleteBottle(bottle)
                                dismiss()
                            }
                        } message: {
                            Text("This will permanently delete '\(bottle.title)', its saves, and free up storage on your device.")
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Bottle Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .foregroundColor(.cyan)
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                loadPackageFiles()
            }
        }
    }

    private func saveChanges() {
        bottle.engine = selectedEngine
        bottle.config.orientation = selectedOrientation
        bottle.entryPoint = selectedEntryPoint
        BottleManager.shared.saveIndex()
    }

    private func triggerSplitExtraction() {
        guard !isExtractingSplit else { return }
        isExtractingSplit = true
        extractProgressText = "Starting game pack extraction..."

        Task {
            if let updated = await BottleManager.shared.prepareBottleIfNeeded(bottleId: bottle.id, onProgress: { status, prog in
                DispatchQueue.main.async {
                    self.extractProgressText = "\(status) (\(Int(prog * 100))%)"
                }
            }) {
                await MainActor.run {
                    self.bottle = updated
                    self.selectedEngine = updated.engine
                    self.selectedEntryPoint = updated.entryPoint
                    self.isExtractingSplit = false
                    self.loadPackageFiles()
                }
            } else {
                await MainActor.run {
                    self.isExtractingSplit = false
                    self.loadPackageFiles()
                }
            }
        }
    }

    private func autoSelectEntryPoint(for engine: GameEngineType) {
        let dir = BottleManager.shared.bottleDirectory(for: bottle.id)
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: nil) else { return }

        var allRelative: [String] = []
        for case let fileURL as URL in enumerator {
            let rel = fileURL.relativePath(from: dir)
            allRelative.append(rel)
        }

        switch engine {
        case .webNovel, .rpgMaker:
            if let html = allRelative.first(where: { $0.hasSuffix("index.html") }) ?? allRelative.first(where: { $0.hasSuffix(".html") }) {
                selectedEntryPoint = html
            }
        case .renpy:
            if let rpa = allRelative.first(where: { $0.hasSuffix(".rpa") }) ?? allRelative.first(where: { $0.hasSuffix(".rpyc") }) {
                selectedEntryPoint = rpa
            }
        case .godot:
            if let pck = allRelative.first(where: { $0.hasSuffix(".pck") }) {
                selectedEntryPoint = pck
            }
        case .love2d:
            if let love = allRelative.first(where: { $0.hasSuffix(".love") }) ?? allRelative.first(where: { $0.hasSuffix("main.lua") }) {
                selectedEntryPoint = love
            }
        case .gameMaker:
            if let gm = allRelative.first(where: { $0.hasSuffix("game.droid") || $0.hasSuffix("data.win") }) {
                selectedEntryPoint = gm
            }
        case .genericNative, .unity:
            if let so = allRelative.first(where: { $0.hasSuffix(".so") }) {
                selectedEntryPoint = so
            }
        case .unknown:
            break
        }
    }

    private func loadPackageFiles() {
        DispatchQueue.global(qos: .userInitiated).async {
            let dir = BottleManager.shared.bottleDirectory(for: bottle.id)
            let nodes = FileInspector.shared.inspect(directory: dir)
            DispatchQueue.main.async {
                self.fileNodes = nodes
                self.isLoadingFiles = false
            }
        }
    }
}

struct FileNodeRow: View {
    let node: FileNode
    let isEntryPoint: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
                    .font(.system(size: 13))
                    .foregroundColor(node.isDirectory ? .yellow : .cyan)

                Text(node.name)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(isEntryPoint ? .cyan : .white)
                    .fontWeight(isEntryPoint ? .bold : .regular)
                    .lineLimit(1)

                if isEntryPoint {
                    Text("ENTRY")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan)
                        .clipShape(Capsule())
                }

                Spacer()

                Text(node.formattedSize)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "doc.richtext"
        case "rpa", "rpyc", "py": return "book.fill"
        case "pck": return "gearshape.2.fill"
        case "so": return "cpu.fill"
        case "png", "jpg", "jpeg", "webp": return "photo"
        case "mp3", "ogg", "wav": return "music.note"
        default: return "doc"
        }
    }
}
