import SwiftUI

/// Root navigation view.
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "mic.fill")
                }

            RecordingView()
                .tabItem {
                    Label("Recordings", systemImage: "waveform")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .accentColor(Theme.accent)
    }
}
