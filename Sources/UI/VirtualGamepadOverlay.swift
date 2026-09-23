import SwiftUI
import UIKit

public struct VirtualGamepadOverlay: View {
    let onKeyEvent: (_ code: String, _ key: String, _ isDown: Bool) -> Void
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    public init(onKeyEvent: @escaping (_ code: String, _ key: String, _ isDown: Bool) -> Void) {
        self.onKeyEvent = onKeyEvent
    }

    public var body: some View {
        HStack(alignment: .bottom) {
            // Left: D-Pad
            DPadView(onKeyEvent: onKeyEvent)
                .padding(.leading, 24)
                .padding(.bottom, 24)

            Spacer()

            // Right: Action Buttons (A, B, X, Y)
            ActionButtonsCluster(onKeyEvent: onKeyEvent)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
        }
        .allowsHitTesting(true)
    }
}

struct DPadView: View {
    let onKeyEvent: (_ code: String, _ key: String, _ isDown: Bool) -> Void
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            // Background disc
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 150, height: 150)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                )

            // Up
            DPadButton(icon: "arrowtriangle.up.fill", code: "ArrowUp", key: "ArrowUp", onKeyEvent: onKeyEvent)
                .offset(y: -44)

            // Down
            DPadButton(icon: "arrowtriangle.down.fill", code: "ArrowDown", key: "ArrowDown", onKeyEvent: onKeyEvent)
                .offset(y: 44)

            // Left
            DPadButton(icon: "arrowtriangle.left.fill", code: "ArrowLeft", key: "ArrowLeft", onKeyEvent: onKeyEvent)
                .offset(x: -44)

            // Right
            DPadButton(icon: "arrowtriangle.right.fill", code: "ArrowRight", key: "ArrowRight", onKeyEvent: onKeyEvent)
                .offset(x: 44)

            // Center pivot
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 32, height: 32)
        }
        .frame(width: 150, height: 150)
    }
}

struct DPadButton: View {
    let icon: String
    let code: String
    let key: String
    let onKeyEvent: (_ code: String, _ key: String, _ isDown: Bool) -> Void
    @State private var isPressed = false
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(isPressed ? .cyan : .white.opacity(0.8))
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(isPressed ? Color.cyan.opacity(0.4) : Color.white.opacity(0.08))
            )
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            haptic.impactOccurred()
                            onKeyEvent(code, key, true)
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onKeyEvent(code, key, false)
                    }
            )
    }
}

struct ActionButtonsCluster: View {
    let onKeyEvent: (_ code: String, _ key: String, _ isDown: Bool) -> Void

    var body: some View {
        ZStack {
            // Background disc
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 150, height: 150)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                )

            // Top: X (Space)
            ActionButton(label: "X", code: "Space", key: " ", color: .blue, onKeyEvent: onKeyEvent)
                .offset(y: -44)

            // Bottom: A (Enter / OK)
            ActionButton(label: "A", code: "Enter", key: "Enter", color: .green, onKeyEvent: onKeyEvent)
                .offset(y: 44)

            // Left: Y (Shift / Run)
            ActionButton(label: "Y", code: "ShiftLeft", key: "Shift", color: .yellow, onKeyEvent: onKeyEvent)
                .offset(x: -44)

            // Right: B (Escape / Cancel)
            ActionButton(label: "B", code: "Escape", key: "Escape", color: .red, onKeyEvent: onKeyEvent)
                .offset(x: 44)
        }
        .frame(width: 150, height: 150)
    }
}

struct ActionButton: View {
    let label: String
    let code: String
    let key: String
    let color: Color
    let onKeyEvent: (_ code: String, _ key: String, _ isDown: Bool) -> Void
    @State private var isPressed = false
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        Text(label)
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(isPressed ? color : color.opacity(0.4))
            )
            .overlay(
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            haptic.impactOccurred()
                            onKeyEvent(code, key, true)
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onKeyEvent(code, key, false)
                    }
            )
    }
}
