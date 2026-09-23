import SwiftUI
import UIKit

public struct GamePlayerView: View {
    public let bottle: Bottle
    @Environment(\.dismiss) private var dismiss

    @State private var showingMenu = false
    @State private var showingDiagnostics = false
    @State private var showVirtualGamepad = false
    @State private var runner: GameRunnerProtocol?

    public init(bottle: Bottle) {
        self.bottle = bottle
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let r = runner {
                RunnerHostView(runner: r)
                    .ignoresSafeArea()
            }

            // Virtual Gamepad Overlay (when enabled)
            if showVirtualGamepad {
                VirtualGamepadOverlay { code, key, isDown in
                    runner?.sendKey(code: code, key: key, down: isDown)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }

            // Floating Quick-Action Menu Button (Top Right)
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
        .onAppear {
            BottleManager.shared.updateLastPlayed(bottle.id)
            self.runner = RunnerRegistry.shared.createRunner(for: bottle)
        }
        .onDisappear {
            runner?.stop()
        }
        .sheet(isPresented: $showingDiagnostics) {
            GameDiagnosticsSheet(bottle: bottle, logs: runner?.consoleLogs ?? [])
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
}

struct RunnerHostView: UIViewControllerRepresentable {
    let runner: GameRunnerProtocol

    func makeUIViewController(context: Context) -> UIViewController {
        return runner.makeViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
