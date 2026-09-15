import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("showHeadphonesHint") private var showHeadphonesHint = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio") {
                    Toggle("Show headphones hint", isOn: $showHeadphonesHint)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersionString)
                    LabeledContent("Build", value: Bundle.main.buildNumber)
                }

                Section {
                    Text("⚠️ Headphones recommended for low-latency vocal monitoring. Using the built-in speaker while the microphone is active may cause echo feedback.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private extension Bundle {
    var appVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
