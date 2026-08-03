import AppKit
import SwiftUI

struct StorageView: View {
    @ObservedObject var poller: StatusPoller

    @State private var root: String = DiskAnalyzer.suggestedRoots.first?.path ?? ""
    @State private var path: String = ""
    @State private var entries: [DiskEntry] = []
    @State private var breadcrumb: [String] = []
    @State private var isAnalyzing = false
    @State private var analyzeError: String?
    @State private var didAutoScan = false
    @State private var pendingTrash: DiskEntry?
    @State private var actionError: String?

    @State private var sort: [KeyPathComparator<DiskEntry>] = [
        KeyPathComparator(\DiskEntry.sortSize, order: .reverse)
    ]

    private var sortedEntries: [DiskEntry] { entries.sorted(using: sort) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            volumes
            Divider()
            browser
        }
        .confirmationDialog(
            pendingTrash.map { "Move “\($0.displayName)” to Trash?" } ?? "Move to Trash?",
            isPresented: Binding(get: { pendingTrash != nil },
                                 set: { if !$0 { pendingTrash = nil } }),
            titleVisibility: .visible
        ) {
            if let target = pendingTrash {
                Button("Move to Trash", role: .destructive) { trash(target) }
                Button("Cancel", role: .cancel) { pendingTrash = nil }
            }
        } message: {
            Text("It goes to the Trash, so you can put it back — nothing is deleted straight away.")
        }
        .alert("Couldn't complete that",
               isPresented: Binding(get: { actionError != nil },
                                    set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: Volumes

    private var volumes: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Volumes").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Free up space with Mole…") {
                    if case .failure(let error) = MoleCLI.runInTerminal("clean") {
                        actionError = error.message
                    }
                }
                .font(.system(size: 11))
                .help("Opens Terminal and runs `mo clean`. Mole's cleanup is an interactive tool, so Vitality hands off rather than driving a UI that deletes files.")
            }

            if (poller.latest?.userDisks ?? []).isEmpty {
                Text("Waiting for volume data…")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                ForEach(poller.latest?.userDisks ?? []) { disk in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(volumeName(disk))
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                            if disk.external == true {
                                Text("external").font(.system(size: 9)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text("\(Fmt.bytes(disk.free)) free of \(Fmt.bytes(disk.total))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(Fmt.percent(disk.usedPercent))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Severity.forUsage(disk.usedPercent))
                                .frame(width: 48, alignment: .trailing)
                        }
                        MiniBar(percent: disk.usedPercent, height: 5)
                    }
                }
            }
        }
    }

    // MARK: Browser

    private var browser: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Find large files")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)

                Picker("", selection: $root) {
                    ForEach(DiskAnalyzer.suggestedRoots, id: \.path) { entry in
                        Text(entry.label).tag(entry.path)
                    }
                }
                .labelsHidden()
                .frame(width: 170)

                Button("Scan") { analyze(root, resetBreadcrumb: true) }
                    .disabled(isAnalyzing)
                Button("Choose Folder…") { chooseFolder() }
                    .disabled(isAnalyzing)

                if !breadcrumb.isEmpty {
                    Button { goUp() } label: { Label("Up", systemImage: "chevron.up") }
                        .disabled(isAnalyzing)
                }

                Spacer()
                if isAnalyzing { ProgressView().controlSize(.small) }
            }

            if !path.isEmpty {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }

            content
        }
        .onAppear {
            // Scan once on first open. Guarded by a flag rather than
            // `entries.isEmpty`, or every tab switch re-triggers a full scan.
            guard !didAutoScan else { return }
            didAutoScan = true
            analyze(root, resetBreadcrumb: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isAnalyzing && entries.isEmpty {
            centered {
                ProgressView()
                Text("Scanning \((path as NSString).lastPathComponent)…")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Large folders can take a while — Mole walks the whole tree.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        } else if let analyzeError {
            centered {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20)).foregroundStyle(.orange)
                Text(analyzeError)
                    .font(.system(size: 11)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if isProtected(path) {
                    Text("Downloads, Desktop and Documents are protected by macOS. Vitality needs your permission the first time it reads one.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Files")!)
                    }
                    .font(.system(size: 11))
                }
            }
        } else if entries.isEmpty {
            centered {
                Image(systemName: "folder").font(.system(size: 20)).foregroundStyle(.secondary)
                Text("Nothing to show in this folder.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else {
            Table(sortedEntries, sortOrder: $sort) {
                TableColumn("Name", value: \.sortName) { entry in
                    HStack(spacing: 5) {
                        Image(systemName: entry.isDir == true ? "folder.fill" : "doc")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(entry.displayName).font(.system(size: 12)).lineLimit(1)
                    }
                }
                TableColumn("Kind", value: \.sortKind) { entry in
                    Text(entry.isDir == true ? "Folder" : "File")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .width(58)
                TableColumn("Size", value: \.sortSize) { entry in
                    Text(Fmt.bytes(entry.size)).font(.system(size: 11, weight: .medium))
                }
                .width(84)
                // Bordered rather than plain: as borderless text these ran
                // together into an unreadable "Open Reveal Trash" with no
                // indication they were three separate controls.
                TableColumn("Actions") { entry in
                    HStack(spacing: 6) {
                        if entry.isDir == true {
                            Button("Open") { if let p = entry.path { drillInto(p) } }
                                .help("Scan inside this folder")
                        }
                        Button("Reveal") {
                            if let p = entry.path { DiskAnalyzer.revealInFinder(p) }
                        }
                        .help("Show in Finder")
                        Button("Trash") { pendingTrash = entry }
                            .help("Move to Trash — recoverable")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 11))
                }
                .width(190)
            }
            .frame(minHeight: 200)

            Text("Click a column header to sort. Sizes come from Mole's analyzer; deleting moves items to the Trash.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private func centered<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        VStack(spacing: 6) { inner() }
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding(.horizontal, 30)
    }

    /// Friendly volume label. A bare "/" tells the user nothing, and long mount
    /// paths pushed the free-space figures off the row.
    private func volumeName(_ disk: SystemStatus.Disk) -> String {
        guard let mount = disk.mount else { return disk.device ?? "—" }
        if mount == "/" {
            let name = (try? URL(fileURLWithPath: "/")
                .resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? nil
            return name.map { "\($0)  ·  /" } ?? "Startup disk  ·  /"
        }
        return (mount as NSString).lastPathComponent
    }

    private func isProtected(_ candidate: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["Downloads", "Desktop", "Documents"].contains {
            candidate.hasPrefix("\(home)/\($0)")
        }
    }

    // MARK: Actions

    private func analyze(_ target: String, resetBreadcrumb: Bool) {
        guard !target.isEmpty else { return }
        if resetBreadcrumb { breadcrumb = [] }
        path = target
        isAnalyzing = true
        analyzeError = nil
        entries = []

        Task.detached(priority: .userInitiated) {
            let result = DiskAnalyzer.analyze(path: target)
            await MainActor.run {
                isAnalyzing = false
                switch result {
                case .success(let analysis):
                    // Mole returns largest-first, but sort defensively so the
                    // view never depends on that staying true.
                    entries = (analysis.entries ?? [])
                        .sorted { ($0.size ?? 0) > ($1.size ?? 0) }
                case .failure(let error):
                    entries = []
                    analyzeError = error.localizedDescription
                }
            }
        }
    }

    private func drillInto(_ target: String) {
        breadcrumb.append(path)
        analyze(target, resetBreadcrumb: false)
    }

    private func goUp() {
        guard let previous = breadcrumb.popLast() else { return }
        analyze(previous, resetBreadcrumb: false)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            analyze(url.path, resetBreadcrumb: true)
        }
    }

    private func trash(_ entry: DiskEntry) {
        pendingTrash = nil
        guard let target = entry.path else { return }
        switch DiskAnalyzer.moveToTrash(target) {
        case .success:
            entries.removeAll { $0.id == entry.id }
        case .failure(let error):
            actionError = error.message
        }
    }
}
