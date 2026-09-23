import SwiftUI

public struct BottleDetailSheet: View {
    @Binding var bottle: Bottle
    let onPlay: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEngine: GameEngineType
    @State private var selectedOrientation: String
    @State private var fileNodes: [FileNode] = []
    @State private var isLoadingFiles = true
    @State private var showingExportShare = false
    @State private var exportZipURL: URL? = nil

    public init(bottle: Binding<Bottle>, onPlay: @escaping () -> Void) {
        self._bottle = bottle
        self.onPlay = onPlay
        self._selectedEngine = State(initialValue: bottle.wrappedValue.engine)
        self._selectedOrientation = State(initialValue: bottle.wrappedValue.config.orientation)
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

                                // Entry Point info
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Entry Point")
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                    Text(bottle.entryPoint.isEmpty ? "Automatic" : bottle.entryPoint)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.cyan)
                                        .lineLimit(2)
                                }
                            }
                            .padding(16)
                            .background(Color(red: 0.12, green: 0.13, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        // File Explorer / Assets Tree
                        VStack(alignment: .leading, spacing: 14) {
                            Text("PACKAGE ASSETS & FILES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
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
                                    ForEach(fileNodes.prefix(25)) { node in
                                        FileNodeRow(node: node)
                                    }
                                    if fileNodes.count > 25 {
                                        Text("+ \(fileNodes.count - 25) more items...")
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
        BottleManager.shared.saveIndex()
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
                .font(.system(size: 13))
                .foregroundColor(node.isDirectory ? .yellow : .cyan)

            Text(node.name)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            Text(node.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 2)
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
