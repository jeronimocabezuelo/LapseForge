//
//  ProjectView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 6/8/25.
//

import SwiftUI

private class ProjectViewModel: ObservableObject {
    @Published var selectedSequence: LapseSequence?
    @Published var scrubber: TimeInterval = .zero
    @Published var showPhotoPicker: Bool = false
    @Published var isPlaying: Bool = false
    
    @Published var catalogSequence: LapseSequence?
    @Published var pickedUrl: URL?
}

struct ProjectView: View {
    @Environment(\.modelContext) private var modelContext
    var project: LapseProject
    
    @StateObject private var viewModel = ProjectViewModel()
    
    @Namespace private var namespace
    
    @ObservedObject var exporter: Exporter
    
    var currentSequence: LapseSequence? {
        let sequence = project.sequence(at: viewModel.scrubber)?.sequence
        return sequence
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Previsualización
            PreviewView(
                project: project,
                scrubber: $viewModel.scrubber,
                isPlaying: $viewModel.isPlaying
            )
            
            // Línea de tiempo avanzada
            TimeLineView(
                project: project,
                scrubber: $viewModel.scrubber,
                selectedSequence: $viewModel.selectedSequence,
                showPhotoPicker: $viewModel.showPhotoPicker,
                isPlaying: $viewModel.isPlaying
            )
            // Vista de configuración
            if let currentSequence {
                ConfigurationSequenceView(
                    currentSequence: currentSequence,
                    catalogSequence: $viewModel.catalogSequence,
                    namespace: namespace
                )
            }
        }
        .navigationTitle(project.title)
        .toolbar(content: {
            ToolbarItem {
                Button {
                    saveProject()
                } label: {
                    Text(.Common.save)
                }
            }
            ToolbarItem {
                ExporterButton(exporter: exporter, project: project)
            }
        })
        .sheet(
            item: $viewModel.selectedSequence,
            content: { sequence in
                CaptureSequenceView(
                    sequence: sequence,
                    onSaveSequence: onSaveSequence
                )
            }
        )
        .sheet(
            item: $viewModel.catalogSequence,
            content: { sequence in
                SequenceCatalogView(
                    sequence: sequence,
                    onSaveSequence: saveProject
                )
                .navigationTransition(
                    .zoom(
                        sourceID: "catalog_transition",
                        in: namespace
                    )
                )
            }
        )
        .sheet(isPresented: $viewModel.showPhotoPicker) {
            PHVideoPicker(
                isPresented: $viewModel.showPhotoPicker,
                onPicked: { [weak viewModel] url in
                    runOnMainThread {
                        viewModel?.pickedUrl = url
                    }
                },
                onProgress: { p in
                    // Si quieres mostrar progreso (0…1)
                    print("Progreso:", p)
                }
            )
        }
        .sheet(
            isPresented: .init(
                get: { viewModel.pickedUrl != nil },
                set: { if !$0 { viewModel.pickedUrl = nil } }
            ),
            content: {
                ImportSequenceView(
                    url: viewModel.pickedUrl,
                    onSaveSequence: onSaveSequence
                )
            }
        )
    }
    
    private func onSaveSequence(sequence: LapseSequence) {
        if !project.sequences.contains(sequence) {
            project.sequences.append(sequence)
        }
        saveProject()
    }
    
    private func saveProject() {
        do {
            try modelContext.save()
        } catch {
            print("No se pudo guardar el context: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        ProjectView(project: .mock, exporter: .init())
    }
}

