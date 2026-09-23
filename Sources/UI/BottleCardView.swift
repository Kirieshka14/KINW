import SwiftUI

public struct BottleCardView: View {
    @Binding public var bottle: Bottle
    public let onPlay: () -> Void
    public let onDelete: () -> Void

    @State private var showingDetails: Bool = false
    @State private var showingDeleteConfirmation: Bool = false

    private var iconImage: UIImage? {
        if let iconURL = BottleManager.shared.iconURL(for: bottle.id),
           let data = try? Data(contentsOf: iconURL) {
            return UIImage(data: data)
        }
        return nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Icon + Badges
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    if let img = iconImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Image(systemName: bottle.engine.iconName)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bottle.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(bottle.packageName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        BadgeView(text: bottle.engine.rawValue, color: engineColor)
                        BadgeView(text: "v\(bottle.version)", color: .gray)
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Action footer
            HStack {
                if let lastPlayed = bottle.lastPlayedDate {
                    Text("Played \(lastPlayed, style: .relative) ago")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                } else {
                    Text("Never played")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }

                Spacer()

                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                        .padding(8)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Circle())
                }
                .alert("Delete Bottle?", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive, action: onDelete)
                } message: {
                    Text("Permanently delete '\(bottle.title)' and free up storage?")
                }

                Button(action: { showingDetails = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }

                Button(action: onPlay) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Play")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.blue.opacity(0.4), radius: 6, x: 0, y: 3)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.18).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .sheet(isPresented: $showingDetails) {
            BottleDetailSheet(bottle: $bottle, onPlay: onPlay)
        }
        .contextMenu {
            Button(action: onPlay) {
                Label("Launch Game", systemImage: "play.fill")
            }
            Button(action: { showingDetails = true }) {
                Label("Bottle Settings & Files", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete Bottle", systemImage: "trash.fill")
            }
        }
    }

    private var engineColor: Color {
        switch bottle.engine {
        case .renpy: return .purple
        case .webNovel, .rpgMaker: return .blue
        case .godot: return .cyan
        case .gameMaker: return .green
        case .love2d: return .pink
        case .unity: return .orange
        case .genericNative: return .indigo
        case .unknown: return .gray
        }
    }
}

public struct BadgeView: View {
    public let text: String
    public let color: Color

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
