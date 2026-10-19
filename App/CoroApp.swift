import SwiftUI

@main
struct CoroApp: App {
    @StateObject private var engine = LyricsEngine()

    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine, auth: engine.auth)
                .preferredColorScheme(.dark)
        }
    }
}
