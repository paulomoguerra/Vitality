import AppKit
import SwiftUI

struct DuplicateFilesView: View {
    @State private var root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads").path
    @State private var groups: [DuplicateGroup] = []
    @State private var selectedPaths: Set<String> = []
    @State private var isScanning = false
    @State private var didScan = false
    @State private var scanError: String?
    @State private var actionError: String?
    @State private var pendingTrash: [DuplicateFile] = []
    @State private var scanTask: Task<Void, Never>?

    private var selectedFiles: [DuplicateFile] {
        groups.flatMap(\.files).filter { selectedPaths.contains($0.path) }
    }

    private var selectedBytes: Int64 {
        selectedFiles.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text("Select files yourself. Vitality never deletes or moves duplicates automatically.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if !root.isEmpty {
                Text(root)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            content
        }
        .onDisappear { scanTask?.cancel() }
        .confirmationDialog(
            pendingTrash.isEmpty ? "Move files to Trash?" : "Move (pendingTrash.count) files to Trash?",
            isPresented: Binding(
                get: { !pendingTrash.isEmpty },
                set: { if !$0 { pendingTrash = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { trashPending() }
            Button("Cancel", role: .cancel) { pendingTrash = [] }
        } message: {
            Text("The files will go to the Trash and can be restored from Finder.")
        }
        .alert("Couldn't complete that", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Duplicate files")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Button("Choose Folder…") { chooseRoot() }
                .disabled(isScanning)
            Button(isScanning ? "Scanning…" : "Scan") { scan() }
                .disabled(isScanning || root.isEmpty)
            Button("Move selected…") { chooseDestination() }
                .disabled(selectedFiles.isEmpty || isScanning)
            Button("Trash selected…", role: .destructive) { pendingTrash = selectedFiles }
                .disabled(selectedFiles.isEmpty || isScanning)
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var content: some View {
        if isScanning {
            VStack(spacing: 7) {
                ProgressView()
                Text("Comparing files by size and content…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Large folders can take a while. Packages and hidden files are skipped.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if let scanError {
            emptyState(icon: "exclamationmark.triangle.fill", title: scanError)
        } else if !didScan {
            emptyState(icon: "square.stack.3d.up", title: "Choose a folder and scan for duplicates.")
        } else if groups.isEmpty {
            emptyState(icon: "checkmark.circle", title: "No exact duplicates found in this folder.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(groups.count) groups · \(selectedFiles.count) selected")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    if !selectedFiles.isEmpty {
                        Text("\(Fmt.bytes(selectedBytes)) selected")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(groups) { group in
                            groupView(group)
                        }
                    }
                }
                .frame(minHeight: 240)
            }
        }
    }

    private func groupView(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.orange)
                Text("\(group.files.count) identical copies")
                    .font(.system(size: 11, weight: .semibold))
                Text("· \(Fmt.bytes(group.size)) each")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Fmt.bytes(group.reclaimable)) reclaimable")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }

            ForEach(group.files) { file in
                fileRow(file)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(Color.primary.opacity(0.04)))
    }

    private func fileRow(_ file: DuplicateFile) -> some View {
        HStack(spacing: 7) {
            Toggle("", isOn: Binding(
                get: { selectedPaths.contains(file.path) },
                set: { selected in
                    if selected { selectedPaths.insert(file.path) }
                    else { selectedPaths.remove(file.path) }
                }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(file.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func emptyState(icon: String, title: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 25))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            root = url.path
            groups = []
            selectedPaths = []
            didScan = false
            scanError = nil
        }
    }

    private func scan() {
        scanTask?.cancel()
        let target = root
        isScanning = true
        didScan = true
        scanError = nil
        groups = []
        selectedPaths = []

        scanTask = Task.detached(priority: .userInitiated) {
            let result = DuplicateAnalyzer.scan(path: target)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isScanning = false
                switch result {
                case .success(let found): groups = found
                case .failure(let error):
                    groups = []
                    scanError = error.message
                }
            }
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Move Here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let files = selectedFiles
        var moved: [DuplicateFile] = []
        var failures: [String] = []
        for file in files {
            switch DuplicateAnalyzer.move(file, to: folder) {
            case .success: moved.append(file)
            case .failure(let error): failures.append(error.message)
            }
        }
        removeFiles(moved)
        if let first = failures.first { actionError = first }
    }

    private func trashPending() {
        let files = pendingTrash
        pendingTrash = []
        var failures: [String] = []
        var moved: [DuplicateFile] = []
        for file in files {
            switch DuplicateAnalyzer.moveToTrash(file) {
            case .success: moved.append(file)
            case .failure(let error): failures.append(error.message)
            }
        }
        removeFiles(moved)
        if let first = failures.first { actionError = first }
    }

    private func removeFiles(_ files: [DuplicateFile]) {
        let paths = Set(files.map(\.path))
        groups = groups.compactMap { group in
            let remaining = group.files.filter { !paths.contains($0.path) }
            return remaining.count > 1 ? DuplicateGroup(digest: group.digest, files: remaining) : nil
        }
        selectedPaths.subtract(paths)
    }
}
