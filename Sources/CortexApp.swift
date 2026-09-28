import SwiftUI

@main
struct CortexApp: App {
    @StateObject private var models = ModelStore()
    @StateObject private var chats = ChatStore()
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(models)
                .environmentObject(chats)
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
