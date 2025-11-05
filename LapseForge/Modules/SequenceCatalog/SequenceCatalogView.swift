//
//  SequenceCatalogView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 12/8/25.
//

import SwiftUI

private struct SequenceCatalogCaptureModel {
    var selected: Bool = false
    let capture: LapseCapture
    
    init(capture: LapseCapture) {
        self.capture = capture
    }
}

struct SequenceCatalogView: View {
    private struct ShareItem: Identifiable {
        let id: UUID = UUID()
        let url: URL
    }
    
    let sequence: LapseSequence
    var onSaveSequence: () -> Void
    
    @State private var captures: [SequenceCatalogCaptureModel] = []
    @State private var shareZipItem: ShareItem?
    
    @Environment(\.dismiss) private var dismiss
    
    let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    private var selectedCaptures: Int {
        captures.count(where: \.selected)
    }
    
    @ViewBuilder
    private func captureView(with model: SequenceCatalogCaptureModel) -> some View {
        GeometryReader { geo in
            ZStack {
                CaptureView(
                    capture: model.capture
                )
            }
            .frame(width: geo.size.width, height: geo.size.width)
            
        }
        .background(.gray)
        .overlay {
            if model.selected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 8)
            }
        }
        .overlay(alignment: .bottomLeading) {
            let systemName = model.selected ? "checkmark.circle.fill" : "circle"
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(model.selected ? .primary : .secondary)
                .background(.ultraThinMaterial)
                .clipShape(.circle)
                .shadow(radius: 3)
                .padding(8)
        }
        .cornerRadius(8)
        .aspectRatio(1, contentMode: .fit)
        .onTapGesture {
            captures[at: model.capture.index]?.selected.toggle()
        }
    }
    
    @ViewBuilder
    var selectionView: some View {
        HStack {
            Text(.SequenceCatalog.selectedCaptures(selectedCaptures) )
            Spacer()
            let isAllSelected = selectedCaptures == captures.count
            Button(isAllSelected ? .SequenceCatalog.unselectAll : .SequenceCatalog.selectAll) {
                captures.indices.forEach {
                    captures[at: $0]?.selected = !isAllSelected
                }
                
            }
            .buttonStyle(.glass)
        }
    }
    
    @ViewBuilder
    var deleteButton: some View {
        Button(.SequenceCatalog.deleteFrames, role: .destructive) {
            withAnimation {
                for capture in captures where capture.selected {
                    sequence.removeCapture(capture.capture)
                }
                captures.removeAll(where: \.selected)
            }
        }
        .buttonStyle(.borderedProminent)
    }
    
    @ViewBuilder
    var exportButton: some View {
        Button(.SequenceCatalog.exportFrames, role: .cancel) {
            exportFrames()
        }
        .buttonStyle(.borderedProminent)
    }
    
    @ViewBuilder
    var buttonsView: some View {
        HStack {
            deleteButton
            Spacer()
            exportButton
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(captures, id: \.capture) { capture in
                            captureView(with: capture)
                        }
                    }
                    
                }
                selectionView
                buttonsView
            }
            .padding()
            .navigationTitle(.Project.frameCatalog)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.Common.close, systemImage: "xmark") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(.Common.save, systemImage: "checkmark") {
                        onSaveSequence()
                        dismiss()
                    }
                }
            }
            .task {
                calculeCaptures()
            }
            .sheet(item: $shareZipItem, content: { item in
                ShareView(url: item.url)
            })
        }
    }
    
    private func calculeCaptures() {
        captures = sequence.captures.map(SequenceCatalogCaptureModel.init)
    }
    
    private func exportFrames() {
        do {
            let selectedCaptures = captures.filter(\.selected).map(\.capture)
            let zipUrl = try CustomFileManager.shared.zip(from: selectedCaptures)
            
            runOnMainThread {
                self.shareZipItem = .init(url: zipUrl)
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
}

struct ShareView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SequenceCatalogView(sequence: .mock, onSaveSequence: {})
}
