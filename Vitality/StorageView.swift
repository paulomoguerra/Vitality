import AppKit
import SwiftUI

private enum StorageMode: String, CaseIterable, Identifiable {
    case volumes = "Volumes"
    case duplicates = "Duplicates"
    case cleanup = "Free up"

    var id: String { rawValue }
}

struct StorageView: View {
    @ObservedObject var poller: StatusPoller

    @State private var mode: StorageMode = .volumes
    @State private var root: String = DiskAnalyzer.suggestedRoots.first?.path ?? ""
    @State private var path: String = ""
    @State private var entries: [DiskEntry] = []
    @State private var breadcrumb: [String] = []
    @State private var isAnalyzing = false
    @State private var analyzeError: String?
    @State private var pendingTrash: DiskEntry?
    @State private var actionError: String?

    @State private var sort: [KeyPathComparator<DiskEntry>] = [
        KeyPathComparator(\DiskEntry.size, order: .reverse)
    ]

    private var sortedEntries: [DiskEntry] { entries.sorted(using: sort) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Storage", selection: $mode) {
                ForEach(StorageMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            switch mode {
            case .volumes:
                volumes
                Divider()
                browser
            case .duplicates:
                DuplicateFilesView()
            case .cleanup:
                CleanupView()
            }
        }
        .confirmationDialog(
            pendingTrash.map { "Move “\($0.name)” to Trash?" } ?? "Move to Trash?",
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
                Button("Open Trash") { DiskAnalyzer.openTrash() }
                    .font(.system(size: 11))
                    .help("Emptying the Trash is irreversible, so Vitality hands that to Finder rather than doing it for you.")
            }

            if (poller.latest?.userDisks ?? []).isEmpty {
                Text("Reading volumes…")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                ForEach(poller.latest?.userDisks ?? []) { disk in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(disk.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                            if disk.isInternal == false {
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
    }

    @ViewBuilder
    private var content: some View {
        if isAnalyzing && entries.isEmpty {
            centered {
                ProgressView()
                Text("Measuring \((path as NSString).lastPathComponent)…")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Folder sizes mean walking every file inside them, so large folders take a moment.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
                TableColumn("Name", value: \.name) { entry in
                    HStack(spacing: 5) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(entry.name).font(.system(size: 12)).lineLimit(1)
                    }
                }
                TableColumn("Kind", value: \.sortKind) { entry in
                    Text(entry.isDirectory ? "Folder" : "File")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .width(58)
                TableColumn("Size", value: \.size) { entry in
                    Text(Fmt.bytes(entry.size)).font(.system(size: 11, weight: .medium))
                }
                .width(84)
                TableColumn("Actions") { entry in
                    HStack(spacing: 6) {
                        if entry.isDirectory {
                            Button("Open") { drillInto(entry.path) }
                                .help("Measure inside this folder")
                        }
                        Button("Reveal") { DiskAnalyzer.revealInFinder(entry.path) }
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

            Text("Click a column header to sort. Deleting moves items to the Trash, never straight to `rm`.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private func centered<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        VStack(spacing: 6) { inner() }
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding(.horizontal, 30)
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
                case .success(let found):
                    entries = found
                case .failure(let error):
                    entries = []
                    analyzeError = error.message
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
        switch DiskAnalyzer.moveToTrash(entry.path) {
        case .success:
            entries.removeAll { $0.id == entry.id }
        case .failure(let error):
            actionError = error.message
        }
    }
}

// MARK: - Cleanup

/// The "free up space" flow: scan four known reclaimable categories, let the
/// user pick, move to Trash. Nothing is deleted outright, and the Trash itself
/// is only ever opened — emptying it stays Finder's job.
struct CleanupView: View {
    @State private var categories: [CleanupCategory] = []
    @State private var selected: Set<String> = []
    @State private var isScanning = false
    @State private var didScan = false
    @State private var confirmClean = false
    @State private var resultMessage: String?
    @State private var actionError: String?

    private var selectedCategories: [CleanupCategory] {
        categories.filter { $0.kind == .trashable && selected.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedCategories.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Free up space")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(isScanning ? "Scanning…" : "Scan") { scan() }
                    .disabled(isScanning)
            }

            Text("Everything goes to the Trash first, so it can be put back.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if isScanning {
                VStack(spacing: 7) {
                    ProgressView()
                    Text("Measuring caches, DerivedData and old downloads…")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if !didScan {
                VStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24)).foregroundStyle(.tertiary)
                    Text("Scan to see what can be reclaimed.")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if categories.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24)).foregroundStyle(.tertiary)
                    Text("Nothing worth reclaiming — this Mac is already tidy.")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                list
                footer
            }

            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
        }
        .confirmationDialog(
            "Move \(Fmt.bytes(selectedBytes)) to the Trash?",
            isPresented: $confirmClean,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { clean() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apps rebuild their caches as needed. Nothing is deleted permanently — restore anything from the Trash.")
        }
        .alert("Couldn't complete that",
               isPresented: Binding(get: { actionError != nil },
                                    set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(categories) { category in
                HStack(spacing: 10) {
                    if category.kind == .trashable {
                        Toggle("", isOn: Binding(
                            get: { selected.contains(category.id) },
                            set: { isOn in
                                if isOn { selected.insert(category.id) }
                                else { selected.remove(category.id) }
                            }
                        ))
                        .labelsHidden()
                    } else {
                        Spacer().frame(width: 16)
                    }

                    Image(systemName: category.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(category.label).font(.system(size: 12, weight: .medium))
                        Text("\(category.itemCount) item\(category.itemCount == 1 ? "" : "s")")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(Fmt.bytes(category.bytes))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)

                    if category.kind == .trashBin {
                        Button("Open") { DiskAnalyzer.openTrash() }
                            .controlSize(.small)
                            .help("Emptying the Trash is irreversible, so Vitality hands that to Finder.")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                if category.id != categories.last?.id {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private var footer: some View {
        HStack {
            Text(selectedCategories.isEmpty
                 ? "Select categories to reclaim."
                 : "\(Fmt.bytes(selectedBytes)) selected")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Move to Trash…") { confirmClean = true }
                .disabled(selectedCategories.isEmpty)
        }
    }

    private func scan() {
        isScanning = true
        didScan = true
        resultMessage = nil
        Task.detached(priority: .userInitiated) {
            let found = CleanupScanner.scan()
            await MainActor.run {
                isScanning = false
                categories = found
                selected = []
            }
        }
    }

    private func clean() {
        let targets = selectedCategories
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let result = CleanupScanner.clean(targets)
            let rescanned = CleanupScanner.scan()
            await MainActor.run {
                isScanning = false
                categories = rescanned
                selected = []
                switch result {
                case .success(let bytes):
                    resultMessage = "Freed \(Fmt.bytes(bytes)) — it's in the Trash if you need it back."
                case .failure(let error):
                    actionError = error.message
                }
            }
        }
    }
}
