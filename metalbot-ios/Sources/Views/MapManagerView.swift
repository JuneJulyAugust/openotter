import SwiftUI

/// Sheet view for managing saved ARWorldMaps.
struct MapManagerView: View {
    @ObservedObject var viewModel: ARKitPoseViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newMapName: String = ""
    @State private var showSaveField: Bool = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationView {
            List {
                // Save New Map Section
                Section {
                    if showSaveField {
                        HStack {
                            TextField("Map name", text: $newMapName)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                let name = newMapName.isEmpty
                                    ? "Map \(viewModel.savedMaps.count + 1)"
                                    : newMapName
                                viewModel.saveWorldMap(name: name)
                                newMapName = ""
                                showSaveField = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isSavingMap || !viewModel.isTracking)
                        }
                    } else {
                        Button {
                            showSaveField = true
                        } label: {
                            Label("Save Current Map", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!viewModel.isTracking)
                    }

                    if viewModel.isSavingMap {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Saving...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Capture")
                } footer: {
                    Text("ARWorldMaps are snapshots. Save after exploring the area for best relocalization.")
                }

                // Saved Maps Section
                Section {
                    if viewModel.savedMaps.isEmpty {
                        Text("No saved maps")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        // "None" option to deselect
                        Button {
                            viewModel.deselectMap()
                        } label: {
                            HStack {
                                Image(systemName: viewModel.selectedMapID == nil ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(viewModel.selectedMapID == nil ? .blue : .secondary)
                                Text("No map (fresh start)")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }

                        ForEach(viewModel.savedMaps) { entry in
                            Button {
                                viewModel.selectMap(id: entry.id)
                            } label: {
                                HStack {
                                    Image(systemName: viewModel.selectedMapID == entry.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(viewModel.selectedMapID == entry.id ? .blue : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text("\(dateFormatter.string(from: entry.date)) · \(entry.anchorCount) anchors")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()

                                    if viewModel.activeMapName == entry.name {
                                        Text("Active")
                                            .font(.caption2.bold())
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deleteMap(id: viewModel.savedMaps[index].id)
                            }
                        }
                    }
                } header: {
                    Text("Saved Maps (\(viewModel.savedMaps.count))")
                } footer: {
                    if !viewModel.savedMaps.isEmpty {
                        Text("Selected map loads on next Start. Swipe to delete.")
                    }
                }

                // Danger Zone
                if !viewModel.savedMaps.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            viewModel.deleteAllMaps()
                        } label: {
                            Label("Delete All Maps", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("World Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.applySelectedMap()
                        dismiss()
                    }
                }
            }
        }
    }
}
