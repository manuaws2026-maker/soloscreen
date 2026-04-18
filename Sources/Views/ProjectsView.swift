import SwiftUI
import UniformTypeIdentifiers

/// Project management view for RAG file uploads.
///
/// Shows all projects, allows creating/deleting them, and adding/removing files.
/// Files are extracted to text and indexed in the local vector store for RAG retrieval.
struct ProjectsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var newProjectName: String = ""
    @State private var showFilePicker: Bool = false
    @State private var activeProjectId: UUID?

    private let accentTeal = Color(hex: "22C55E")
    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(borderColor)
            content
        }
        .background(bgColor)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.text, .plainText, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Projects")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                createProjectSection
                projectList
            }
            .padding(20)
        }
    }

    // MARK: - Create Project

    private var createProjectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEW PROJECT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(0.5)

            HStack(spacing: 8) {
                TextField("Project name", text: $newProjectName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(surfaceColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(borderColor, lineWidth: 1)
                            )
                    )

                Button {
                    createProject()
                } label: {
                    Text("Create")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(newProjectName.isEmpty ? accentTeal.opacity(0.3) : accentTeal)
                        )
                }
                .buttonStyle(.plain)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Project List

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.projects.isEmpty {
                emptyState
            } else {
                ForEach(appState.projects) { project in
                    projectCard(project)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(.white.opacity(0.2))

            Text("No projects yet")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))

            Text("Create a project and add reference files for context-aware AI responses.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Project Card

    private func projectCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(accentTeal)

                Text(project.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Text("\(project.files.count)/\(Project.maxFiles) files")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))

                Button {
                    appState.deleteProject(project.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Delete project")
            }

            if !project.files.isEmpty {
                VStack(spacing: 4) {
                    ForEach(project.files) { file in
                        fileRow(file)
                    }
                }
            }

            if project.canAddFile {
                Button {
                    activeProjectId = project.id
                    showFilePicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                        Text("Add File")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(accentTeal.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(accentTeal.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }

    private func fileRow(_ file: ProjectFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))

            Text(file.fileName)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Spacer()

            Text(formatFileSize(file.sizeBytes))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        appState.createProject(name: name)
        newProjectName = ""
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard let projectId = activeProjectId else { return }

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            appState.addFileToProject(url, projectId: projectId)

        case .failure:
            break
        }

        activeProjectId = nil
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

#Preview {
    ProjectsView()
        .environmentObject(AppState())
        .frame(width: 520, height: 440)
}
