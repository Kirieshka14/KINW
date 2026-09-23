import SwiftUI

public struct GameDiagnosticsSheet: View {
    public let bottle: Bottle
    public let logs: [String]
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.11).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Bottle Summary Card
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ACTIVE SESSION")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)

                            HStack {
                                Text("Game:")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(bottle.title)
                                    .foregroundColor(.white)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 14))

                            HStack {
                                Text("Engine:")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(bottle.engine.rawValue)
                                    .foregroundColor(.cyan)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 14))

                            HStack {
                                Text("Entry Point:")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(bottle.entryPoint.isEmpty ? "assets/www/index.html" : bottle.entryPoint)
                                    .foregroundColor(.white)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                        .padding(16)
                        .background(Color(red: 0.12, green: 0.13, blue: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // Console & Network Logs
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("LIVE LOGS & ERRORS")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(logs.count) entries")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.gray)
                            }

                            if logs.isEmpty {
                                Text("No log events captured yet.")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 20)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(logs.enumerated()), id: \.offset) { _, entry in
                                        Text(entry)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(entryColor(for: entry))
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        .padding(16)
                        .background(Color(red: 0.12, green: 0.13, blue: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Game Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                        .fontWeight(.bold)
                }
            }
        }
    }

    private func entryColor(for line: String) -> Color {
        if line.contains("[JS-ERR]") || line.contains("[CONSOLE-ERR]") || line.contains("[NAV-ERR]") {
            return .red
        } else if line.contains("[VFS-404]") || line.contains("⚠️") {
            return .orange
        } else if line.contains("[NAV]") || line.contains("[KINW]") {
            return .green
        } else {
            return .white.opacity(0.85)
        }
    }
}
