import SwiftUI

@main
public struct KINWApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            LibraryView()
                .preferredColorScheme(.dark)
        }
    }
}
