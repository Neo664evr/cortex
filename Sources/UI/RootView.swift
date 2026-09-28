import SwiftUI

struct RootView: View {
    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var chats: ChatStore
    @EnvironmentObject private var session: Session
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            ChatListView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)

            ModelsView()
                .tabItem { Label("Models", systemImage: "cube.box") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(2)
        }
        .background(Theme.background)
    }
}
