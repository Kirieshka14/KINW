import SwiftUI

public struct LibraryView: View {
    @ObservedObject var bottleManager = BottleManager.shared

    @State private var searchText = ""
    @State private var selectedFilter: GameEngineType? = nil
    @State private var showingImportSheet = false
    @State private var showingSettingsSheet = false
    @State private var activeBottle: Bottle? = nil

    private var filteredBottles: [Bottle] {
        bottleManager.bottles.filter { bottle in
            let matchesSearch = searchText.isEmpty ||
                bottle.title.localizedCaseInsensitiveContains(searchText) ||
                bottle.packageName.localizedCaseInsensitiveContains(searchText)

            let matchesFilter = selectedFilter == nil || bottle.engine == selectedFilter
            return matchesSearch && matchesFilter
        }
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.11).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.blue, Color.cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                Text("KINW")
                                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                            }

                            Text("Bottles for Android on iOS")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        Button(action: { showingSettingsSheet = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }

                        Button(action: { showingImportSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Import APK")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
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
                            .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                    // Search and Filter Bar
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("Search games & visual novels...", text: $searchText)
                                .foregroundColor(.white)
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.12, green: 0.13, blue: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)

                        // Engine Filter Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterPill(title: "All", isSelected: selectedFilter == nil) {
                                    selectedFilter = nil
                                }

                                ForEach(GameEngineType.allCases.filter { $0 != .unknown }) { engine in
                                    FilterPill(title: engine.rawValue, isSelected: selectedFilter == engine) {
                                        selectedFilter = engine
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 14)

                    // Games List / Empty State
                    if filteredBottles.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach($bottleManager.bottles) { $bottle in
                                    if (selectedFilter == nil || bottle.engine == selectedFilter) &&
                                       (searchText.isEmpty || bottle.title.localizedCaseInsensitiveContains(searchText) || bottle.packageName.localizedCaseInsensitiveContains(searchText)) {
                                        BottleCardView(
                                            bottle: $bottle,
                                            onPlay: { activeBottle = bottle },
                                            onDelete: { bottleManager.deleteBottle(bottle) }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingImportSheet) {
                ImportAPKSheet()
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsView()
            }
            .fullScreenCover(item: $activeBottle) { bottle in
                GamePlayerView(bottle: bottle)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 120, height: 120)

                Image(systemName: "gamecontroller.dashed")
                    .font(.system(size: 52))
                    .foregroundColor(.cyan.opacity(0.8))
            }

            VStack(spacing: 8) {
                Text(bottleManager.bottles.isEmpty ? "No Bottles Yet" : "No Matches Found")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Text(bottleManager.bottles.isEmpty ?
                     "Drop an Android APK file (visual novel, 2D game) to create your first isolated bottle." :
                     "Try changing search query or filter tags.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            if bottleManager.bottles.isEmpty {
                Button(action: { showingImportSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add First Game (.APK)")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .padding(.top, 8)
            }

            Spacer()
        }
    }
}

struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .gray)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isSelected ?
                        LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .leading, endPoint: .trailing) :
                        LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
        }
    }
}
