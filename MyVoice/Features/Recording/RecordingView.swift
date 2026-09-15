import SwiftUI

/// Recording list / management screen.
struct RecordingView: View {
    @State private var recordings: [URL] = []

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "waveform",
                        description: Text("Recordings you make will appear here.")
                    )
                } else {
                    List {
                        ForEach(recordings, id: \.self) { url in
                            RecordingRow(url: url)
                        }
                        .onDelete(perform: deleteRecordings)
                    }
                }
            }
            .navigationTitle("Recordings")
            .onAppear(perform: loadRecordings)
        }
    }

    private func loadRecordings() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordings = (try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ))?.filter { ["m4a", "wav"].contains($0.pathExtension) }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) } ?? []
    }

    private func deleteRecordings(at offsets: IndexSet) {
        offsets.forEach { try? FileManager.default.removeItem(at: recordings[$0]) }
        recordings.remove(atOffsets: offsets)
    }
}

private struct RecordingRow: View {
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.subheadline.weight(.medium))
            if let date = url.creationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private extension URL {
    var creationDate: Date? {
        (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }
}
