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
    @State private var trashReceipts: [TrashReceipt] = []
    @State private var trashAttemptedCount = 0
    @State private var scanTask: Task<Void, Never>?

    private var selectedFiles: [DuplicateFile] {
        groups.flatMap(\.files).filter { selectedPaths.contains($0.path) }
    }

    private var selectedBytes: Int64 {
        selectedFiles.reduce(0) { $0 + $1.size }
    }

    private var allOlderCopies: [DuplicateFile] {
        groups.flatMap(\.olderCopies)
    }

    private var pendingTrashRemovesEveryCopy: Bool {
        let paths = Set(pendingTrash.map(\.path))
        return groups.contains { group in
            !group.files.isEmpty && group.files.allSatisfy { paths.contains($0.path) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text("Vitality never moves a duplicate until you ask. Trash older copies keeps the newest file.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkSecondary)

            folderChips

            if !root.isEmpty {
                Text(root)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            content

            if !trashReceipts.isEmpty {
                trashResult(trashReceipts, attempted: trashAttemptedCount)
            }
        }
        .padding(13)
        .background(ThemeCardBackground())
        .onAppear {
            if !didScan && !isScanning { scan() }
        }
        .onDisappear { scanTask?.cancel() }
        .confirmationDialog(
            pendingTrash.count == 1 ? "Move 1 file to Trash?" : "Move \(pendingTrash.count) files to Trash?",
            isPresented: Binding(
                get: { !pendingTrash.isEmpty },
                set: { if !$0 { pendingTrash = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { trashPending() }
            Button("Cancel", role: .cancel) { pendingTrash = [] }
        } message: {
            Text(pendingTrashRemovesEveryCopy
                 ? "You selected every copy in at least one group. The last original will go to Trash too."
                 : "The files will go to the Trash and can be restored from Finder.")
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
                .foregroundStyle(Theme.ink)

            Spacer()

            if isScanning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Scanning")
                Button("Cancel") { cancelScan() }
                    .accessibilityHint("Stops the duplicate scan")
            } else if didScan {
                Button("Scan again") { scan() }
                    .disabled(root.isEmpty)
            }

            if !selectedFiles.isEmpty {
                Button("Move…") { chooseDestination() }
                    .disabled(isScanning)
                    .help("Move selected files to another folder")
                Button("Move \(selectedFiles.count) to Trash") {
                    pendingTrash = selectedFiles
                }
                .buttonStyle(ThemePillButtonStyle(prominent: true))
                .disabled(isScanning)
            }
        }
    }

    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DiskAnalyzer.suggestedRoots.prefix(4), id: \.path) { entry in
                    Button(entry.label) { scan(path: entry.path) }
                        .buttonStyle(ThemePillButtonStyle(prominent: root == entry.path))
                        .disabled(isScanning)
                }
                Button("Choose…") { chooseRoot() }
                    .buttonStyle(ThemePillButtonStyle())
                    .disabled(isScanning)
            }
        }
    }

    private func trashResult(_ receipts: [TrashReceipt], attempted: Int) -> some View {
        let moved = receipts.count
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.statusGood)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(moved == attempted
                     ? "Moved \(moved) file\(moved == 1 ? "" : "s") to Trash"
                     : "Moved \(moved) of \(attempted) files to Trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Recoverable in Finder until Trash is emptied")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkSecondary)
                if let receipt = receipts.first, receipts.count == 1 {
                    Text(receipt.destinationURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(receipt.destinationURL.path)
                }
            }

            Spacer(minLength: 6)

            if let receipt = receipts.first, receipts.count == 1 {
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([receipt.destinationURL])
                }
                .controlSize(.small)
                .accessibilityLabel("Reveal moved item in Finder")
            }

            Button("Open Trash") { DiskAnalyzer.openTrash() }
                .controlSize(.small)

            Button {
                trashReceipts = []
                trashAttemptedCount = 0
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel("Dismiss Trash result")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(ThemeCardBackground(radius: Theme.nestedRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Moved \(moved) of \(attempted) files to Trash")
    }

    @ViewBuilder
    private var content: some View {
        if isScanning {
            VStack(spacing: 7) {
                ProgressView()
                Text("Comparing files by size and content…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                Text("Large folders can take a while. Packages and hidden files are skipped.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if let scanError {
            emptyState(icon: "exclamationmark.triangle.fill", title: scanError)
        } else if !didScan {
            emptyState(icon: "square.stack.3d.up", title: "Looking for duplicates…")
        } else if groups.isEmpty {
            emptyState(icon: "checkmark.circle", title: "No exact duplicates found in this folder.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(groups.count) groups · \(selectedFiles.count) selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if !selectedFiles.isEmpty {
                        Text("\(Fmt.bytes(selectedBytes)) selected")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    if !allOlderCopies.isEmpty {
                        Button("Trash older copies") { pendingTrash = allOlderCopies }
                            .disabled(isScanning)
                            .help("Keeps the newest file in each group")
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
                    .foregroundStyle(Theme.statusWarn)
                Text("\(group.files.count) identical copies")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("· \(Fmt.bytes(group.size)) each")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text("\(Fmt.bytes(group.reclaimable)) reclaimable")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.statusWarn)
                if !group.olderCopies.isEmpty {
                    Button("Trash \(group.olderCopies.count) older") {
                        pendingTrash = group.olderCopies
                    }
                    .controlSize(.small)
                    .help("Keeps the newest copy")
                }
            }

            ForEach(group.files) { file in
                fileRow(file)
            }
        }
        .padding(9)
        .background(ThemeCardBackground(radius: Theme.nestedRadius))
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
            .accessibilityLabel("Select \(file.name)")

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(file.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.inkTertiary)
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
                .foregroundStyle(Theme.inkTertiary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
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
            scan(path: url.path)
        }
    }

    private func scan(path: String? = nil) {
        if let path { root = path }
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

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        didScan = false
        groups = []
        selectedPaths = []
        scanError = nil
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
        trashAttemptedCount = files.count
        trashReceipts = []
        var failures: [String] = []
        var moved: [DuplicateFile] = []
        var receipts: [TrashReceipt] = []
        for file in files {
            switch DuplicateAnalyzer.moveToTrash(file) {
            case .success(let receipt):
                moved.append(file)
                receipts.append(receipt)
            case .failure(let error): failures.append(error.message)
            }
        }
        trashReceipts = receipts
        removeFiles(moved)
        if let first = failures.first {
            actionError = failures.count == 1
                ? first
                : "Couldn't move \(failures.count) files. \(first)"
        }
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
