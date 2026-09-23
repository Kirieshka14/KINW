import SwiftUI
import UIKit

public struct GamePlayerView: View {
    public let bottle: Bottle
    @Environment(\.dismiss) private var dismiss

    @State private var currentBottle: Bottle
    @State private var showingMenu = false
    @State private var showingDiagnostics = false
    @State private var showVirtualGamepad = false
    @State private var runner: GameRunnerProtocol?
    @State private var isPreparing = false
    @State private var prepStatus = ""
    @State private var prepProgress: Float = 0.0

    public init(bottle: Bottle) {
        self.bottle = bottle
        self._currentBottle = State(initialValue: bottle)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isPreparing {
                // Sleek All-in-One Auto-Prep HUD
                VStack(spacing: 24) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 110, height: 110)

                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.cyan)
                    }

                    VStack(spacing: 8) {
                        Text(currentBottle.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Text(prepStatus.isEmpty ? "Optimizing package for playback..." : prepStatus)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    VStack(spacing: 10) {
                        ProgressView(value: Double(prepProgress), total: 1.0)
                            .tint(.cyan)
                            .scaleEffect(x: 1, y: 1.5, anchor: .center)
                            .frame(width: 260)

                        Text("\(Int(prepProgress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }

                    Spacer()
                }
                .transition(.opacity)
            } else if let r = runner {
                RunnerHostView(runner: r)
                    .ignoresSafeArea()
            }

            // Virtual Gamepad Overlay (when enabled)
            if showVirtualGamepad && !isPreparing {
                VirtualGamepadOverlay { code, key, isDown in
                    runner?.sendKey(code: code, key: key, down: isDown)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }

            // Floating Quick-Action Menu Button (Top Right)
            if !isPreparing {
                VStack {
                    HStack {
                        Spacer()

                        Button(action: { showingMenu = true }) {
                            Image(systemName: "line.3.horizontal.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(Color.white.opacity(0.8), Color.black.opacity(0.6))
                                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 2)
                        }
                        .padding(.top, 16)
                        .padding(.trailing, 20)
                    }

                    Spacer()
                }
            }
        }
        .onAppear {
            BottleManager.shared.updateLastPlayed(bottle.id)
            prepareAndLaunch()
        }
        .onDisappear {
            runner?.stop()
        }
        .sheet(isPresented: $showingDiagnostics) {
            GameDiagnosticsSheet(bottle: currentBottle, logs: runner?.consoleLogs ?? [])
        }
        .confirmationDialog("KINW Game Menu", isPresented: $showingMenu, titleVisibility: .visible) {
            Button(showVirtualGamepad ? "Hide Virtual Gamepad" : "Show Virtual Gamepad (D-Pad)") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVirtualGamepad.toggle()
                }
            }

            Button("View Live Logs & Diagnostics") {
                showingDiagnostics = true
            }

            Button("Reload Game") {
                runner?.reload()
            }

            Button("Exit to Library", role: .destructive) {
                runner?.stop()
                dismiss()
            }

            Button("Cancel", role: .cancel) {}
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
    }

    private func prepareAndLaunch() {
        let dir = BottleManager.shared.bottleDirectory(for: bottle.id)
        let contents = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let hasAPKs = contents.contains { $0.pathExtension.lowercased() == "apk" }

        if hasAPKs || currentBottle.engine == .unknown {
            isPreparing = true
            prepStatus = "Unpacking split APKs (Play Asset Delivery)..."
            prepProgress = 0.05

            Task {
                let updated = await BottleManager.shared.prepareBottleIfNeeded(bottleId: bottle.id) { status, prog in
                    DispatchQueue.main.async {
                        self.prepStatus = status
                        self.prepProgress = prog
                    }
                }

                await MainActor.run {
                    if let fresh = updated {
                        self.currentBottle = fresh
                    }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.isPreparing = false
                    }
                    self.runner = RunnerRegistry.shared.createRunner(for: self.currentBottle)
                }
            }
        } else {
            self.runner = RunnerRegistry.shared.createRunner(for: currentBottle)
        }
    }
}

struct RunnerHostView: UIViewControllerRepresentable {
    let runner: GameRunnerProtocol

    func makeUIViewController(context: Context) -> UIViewController {
        return runner.makeViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
