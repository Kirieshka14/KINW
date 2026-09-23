import SwiftUI
import UniformTypeIdentifiers

public struct ImportAPKSheet: View {
    @ObservedObject var bottleManager = BottleManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var errorMessage: String? = nil

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.11).ignoresSafeArea()

                VStack(spacing: 28) {
                    // Header Illustration
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.blue.opacity(0.3), Color.clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 90
                                )
                            )
                            .frame(width: 180, height: 180)

                        Image(systemName: "shippingbox.and.arrow.backward.fill")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(.top, 20)

                    VStack(spacing: 8) {
                        Text("Import Android APK")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        Text("Select a 2D game or visual novel .apk from your Files, iCloud, or Downloads.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    if bottleManager.isImporting {
                        VStack(spacing: 14) {
                            ProgressView(value: Double(bottleManager.importProgress), total: 1.0)
                                .tint(.cyan)
                                .scaleEffect(x: 1, y: 1.8, anchor: .center)
                                .padding(.horizontal, 40)

                            Text(bottleManager.importStatusText)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.cyan)

                            Text("\(Int(bottleManager.importProgress * 100))%")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 10)
                    }

                    if let err = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 24)
                    }

                    Spacer()

                    // Pick File Button
                    Button(action: { showingFilePicker = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Choose .APK File")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.blue.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .disabled(bottleManager.isImporting)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                    .disabled(bottleManager.isImporting)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.init(filenameExtension: "apk") ?? .data, .zip, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Permission denied to read selected file."
                return
            }

            Task {
                do {
                    errorMessage = nil
                    _ = try await bottleManager.createBottle(from: url)
                    url.stopAccessingSecurityScopedResource()
                    dismiss()
                } catch {
                    url.stopAccessingSecurityScopedResource()
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
