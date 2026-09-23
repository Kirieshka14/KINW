import SwiftUI

public struct SettingsView: View {
    @ObservedObject var bottleManager = BottleManager.shared
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.11).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // KINW Hero banner
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)

                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: Color.purple.opacity(0.4), radius: 12, x: 0, y: 6)

                            Text("KINW")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)

                            Text("KINW Is Not WINE")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cyan)

                            Text("A modular Android APK runner & visual novel sandbox for iOS without jailbreak.")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                        .padding(.top, 20)

                        // Engine Status Section
                        VStack(alignment: .leading, spacing: 14) {
                            Text("ENGINE COMPATIBILITY")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 16)

                            VStack(spacing: 1) {
                                EngineStatusRow(title: "HTML5 / Web Novels", status: "Active (Hardware Metal)", color: .green)
                                EngineStatusRow(title: "Tyranobuilder", status: "Active", color: .green)
                                EngineStatusRow(title: "RPG Maker MV/MZ", status: "Active", color: .green)
                                EngineStatusRow(title: "Ren'Py Visual Novels", status: "Active (Pyodide Web)", color: .green)
                                EngineStatusRow(title: "Godot Engine", status: "Active (.pck mounting)", color: .green)
                                EngineStatusRow(title: "GameMaker Studio", status: "In Development", color: .orange)
                                EngineStatusRow(title: "LÖVE2D", status: "Planned", color: .gray)
                                EngineStatusRow(title: "Unity 2D (C++)", status: "Planned (FalsoJNI)", color: .gray)
                            }
                            .background(Color(red: 0.12, green: 0.13, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .padding(.horizontal, 16)

                        // Information & Links
                        VStack(alignment: .leading, spacing: 14) {
                            Text("ABOUT")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 16)

                            VStack(spacing: 1) {
                                HStack {
                                    Text("Installed Bottles")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(bottleManager.bottles.count)")
                                        .foregroundColor(.cyan)
                                        .fontWeight(.bold)
                                }
                                .padding(16)
                                .background(Color(red: 0.12, green: 0.13, blue: 0.18))

                                HStack {
                                    Text("Architecture")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("ARM64 (No JIT Required)")
                                        .foregroundColor(.gray)
                                }
                                .padding(16)
                                .background(Color(red: 0.12, green: 0.13, blue: 0.18))

                                HStack {
                                    Text("Build Platform")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("GitHub Actions CI/CD")
                                        .foregroundColor(.gray)
                                }
                                .padding(16)
                                .background(Color(red: 0.12, green: 0.13, blue: 0.18))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct EngineStatusRow: View {
    let title: String
    let status: String
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.white)
            Spacer()
            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.12, green: 0.13, blue: 0.18))
    }
}
