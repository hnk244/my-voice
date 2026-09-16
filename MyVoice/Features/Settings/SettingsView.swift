import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("showHeadphonesHint") private var showHeadphonesHint = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio") {
                    Toggle("Noise cancellation", isOn: $appState.noiseCancellationEnabled)
                        .disabled(appState.engineState.isActive)
                    Toggle("Show headphones hint", isOn: $showHeadphonesHint)
                }

                Section {
                    Text("Noise cancellation uses Apple voice processing to reduce room noise and speaker bleed. It can color singing vocals, so leave it off when you want the most natural sound.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Text("Changes apply the next time you activate monitoring.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    if appState.engineState.isActive {
                        Text("Stop monitoring before changing noise cancellation.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
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
