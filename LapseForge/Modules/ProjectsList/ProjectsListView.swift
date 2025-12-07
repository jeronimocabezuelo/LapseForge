//
//  ProjectsListView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 3/8/25.
//

import SwiftUI
import SwiftData

struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [LapseProject]
    
    @ObservedObject var exporter: Exporter = .init()
    
    @ViewBuilder
    var splitView: some View {
        NavigationSplitView {
            List {
                ForEach(projects) { project in
                    NavigationLink {
                        ProjectView(project: project, exporter: exporter)
                    } label: {
                        Text(.ProjectsList.itemTitle(project.title, project.createdDate.formatted(Date.FormatStyle(date: .numeric, time: .standard))))
                    }
                }
                .onDelete(perform: deleteProjects)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addProject) {
                        Label(.ProjectsList.new, systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text(.ProjectsList.select)
        }
        .onAppear(perform: {
            deleteLostSequences()
        })
    }
    
    var body: some View {
        ZStack {
            splitView
            
            if let status = exporter.status {
                Spacer()
                    .background(.background.opacity(0.5))
                VStack {
                    VStack(alignment: .leading) {
                        Text(status.currentTitle)
                        ProgressView(value: status.currentValue, total: 1)
                        Text(.ProjectsList.totalProgress)
                        ProgressView(value: status.totalValue, total: 1)
                    }
                    if case .success = status {
                        Text(.ProjectsList.videoSaved)
                        Button(.Common.ok) {
                            self.exporter.status = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(60)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(30)
                .shadow(radius: 16)
            }
        }
    }
    
    private func addProject() {
        withAnimation {
            let newProject = LapseProject(
                createdDate: Date(),
                title: projects.nextAvailableTitle()
            )
            modelContext.insert(newProject)
            
            do {
                try modelContext.save()
            } catch {
                print(error)
            }
        }
    }
    
    private func deleteProjects(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                guard let project = projects[at: index] else { continue }
                modelContext.delete(project)
            }
            
            do {
                try modelContext.save()
            } catch {
                print(error)
            }
        }
    }
    
    private func deleteLostSequences() {
        do {
            try CustomFileManager.shared.removeUnusedPhotos(keeping: projects)
        } catch {
            print("Error borranod secuencias perdidas: \(error)")
        }
    }
}
