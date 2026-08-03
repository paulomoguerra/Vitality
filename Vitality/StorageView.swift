import AppKit
import SwiftUI

struct StorageView: View {
    @ObservedObject var poller: StatusPoller

    @State private var path: String = DiskAnalyzer.suggestedRoots.first?.path ?? ""
    @State private var entries: [DiskEntry] = []
    @State private var breadcrumb: [String] = []
    @State private var isAnalyzing = false
    @State private var analyzeError: String?
    @State private var pendingTrash: DiskEntry?
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            disks
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

    private var disks: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Volumes").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Free up space with Mole…") { MoleCLI.openInTerminal("clean") }
                    .font(.system(size: 11))
                    .help("Mole's cleanup is an interactive terminal tool, so Vitality hands off to Terminal rather than driving it blindly.")
            }

            ForEach(poller.latest?.userDisks ?? []) { disk in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(disk.mount ?? disk.device ?? "—")
                            .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if disk.external == true {
                            Text("external").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("\(Fmt.bytes(disk.free)) free of \(Fmt.bytes(disk.total))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(Fmt.percent(disk.usedPercent))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Severity.forUsage(disk.usedPercent))
                            .frame(width: 46, alignment: .trailing)
                    }
                    MiniBar(percent: disk.usedPercent, height: 5)
                }
            }
        }
    }

    // MARK: Browser

    private var browser: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Find large files").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Menu("Scan…") {
                    ForEach(DiskAnalyzer.suggestedRoots, id: \.path) { root in
                        Button(root.label) { analyze(root.path, resetBreadcrumb: true) }
                    }
                    Divider()
                    Button("Choose Folder…") { chooseFolder() }
                }
                .frame(width: 110)

                if !breadcrumb.isEmpty {
                    Button {
                        goUp()
                    } label: {
                        Label("Up", systemImage: "chevron.up")
                    }
                    .font(.system(size: 11))
                }

                Spacer()
                if isAnalyzing { ProgressView().controlSize(.small) }
            }

            Text(path.isEmpty ? "Pick a folder to scan" : path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.head)

            if let analyzeError {
                Label(analyzeError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }

            Table(entries) {
                TableColumn("Name") { entry in
                    HStack(spacing: 5) {
                        Image(systemName: entry.isDir == true ? "folder.fill" : "doc")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(entry.displayName).font(.system(size: 12)).lineLimit(1)
                    }
                }
                TableColumn("Size") { entry in
                    Text(Fmt.bytes(entry.size))
                        .font(.system(size: 11, weight: .medium))
                }
                .width(84)
                TableColumn("") { entry in
                    HStack(spacing: 4) {
                        if entry.isDir == true {
                            Button("Open") {
                                if let p = entry.path { drillInto(p) }
                            }
                            .font(.system(size: 11))
                        }
                        Button("Reveal") {
                            if let p = entry.path { DiskAnalyzer.revealInFinder(p) }
                        }
                        .font(.system(size: 11))
                        Button("Trash") { pendingTrash = entry }
                            .font(.system(size: 11))
                    }
                }
                .width(150)
            }

            Text("Sizes come from Mole's analyzer. Deleting moves items to the Trash.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .onAppear { if entries.isEmpty && !path.isEmpty { analyze(path, resetBreadcrumb: true) } }
    }

    // MARK: Actions

    private func analyze(_ target: String, resetBreadcrumb: Bool) {
        if resetBreadcrumb { breadcrumb = [] }
        path = target
        isAnalyzing = true
        analyzeError = nil

        Task.detached(priority: .userInitiated) {
            let result = DiskAnalyzer.analyze(path: target)
            await MainActor.run {
                isAnalyzing = false
                switch result {
                case .success(let analysis):
                    // Mole returns entries largest-first, but sort defensively so
                    // the view doesn't depend on that staying true.
                    entries = (analysis.entries ?? []).sorted { ($0.size ?? 0) > ($1.size ?? 0) }
                    if entries.isEmpty { analyzeError = "Nothing found in this folder." }
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
