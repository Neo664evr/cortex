import SwiftUI

struct RootView: View {
    @EnvironmentObject private var models: ModelStore

    var body: some View {
        TabView {
            ChatListView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }

            ModelsView()
                .tabItem { Label("Models", systemImage: "cube.box") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .background(Theme.background)
        .onAppear { models.reload() }
    }
}
