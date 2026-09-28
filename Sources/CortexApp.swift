import SwiftUI

@main
struct CortexApp: App {
    @StateObject private var models = ModelStore()
    @StateObject private var chats = ChatStore()
    @StateObject private var session = Session()
    @StateObject private var prompts = PromptStore()
    @StateObject private var downloader = Downloader()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(models)
                .environmentObject(chats)
                .environmentObject(session)
                .environmentObject(prompts)
                .environmentObject(downloader)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in models.importFile(url) }
                .onAppear { models.reload() }
        }
    }
}
