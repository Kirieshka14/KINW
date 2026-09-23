import SwiftUI
import UIKit

public struct GamePlayerView: View {
    public let bottle: Bottle
    @Environment(\.dismiss) private var dismiss

    @State private var showingMenu = false
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

            // Floating Quick-Action Menu Button (Top Right)
            VStack {
                HStack {
                    Spacer()

                    Button(action: { showingMenu.toggle() }) {
                        Image(systemName: "line.3.horizontal.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.white.opacity(0.6), Color.black.opacity(0.4))
                            .shadow(radius: 4)
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
        .confirmationDialog("KINW Quick Menu", isPresented: $showingMenu, titleVisibility: .visible) {
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
