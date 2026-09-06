import AppKit
import SwiftUI

enum StorageMode: String, CaseIterable, Identifiable {
    case cleanup = "Free up"
    case largeFiles = "Large files"
    case duplicates = "Duplicates"

    var id: String { rawValue }
}

struct StorageView: View {
    @ObservedObject var poller: StatusPoller
    @Binding var mode: StorageMode

    @State private var path: String = ""
    @State private var entries: [DiskEntry] = []
    @State private var selectedPaths: Set<String> = []
    @State private var breadcrumb: [String] = []
    @State private var isAnalyzing = false
    @State private var analyzeTask: Task<Void, Never>?
    @State private var analyzeError: String?
    @State private var pendingTrashItems: [DiskEntry] = []
    @State private var trashReceipt: TrashReceipt?
    @State private var trashCount = 0
    @State private var actionError: String?

    private var sortedEntries: [DiskEntry] {
        entries.sorted { lhs, rhs in
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var pendingTrashBytes: Int64 {
        pendingTrashItems.reduce(0) { $0 + $1.size }
    }

    private var selectedEntries: [DiskEntry] {
        sortedEntries.filter { selectedPaths.contains($0.path) }
    }

    private var activeSuggestedRoot: String? {
        DiskAnalyzer.suggestedRoots
            .map(\.path)
            .filter { path == $0 || path.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            volumeStrip

            Picker("Storage", selection: $mode) {
                ForEach(StorageMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .accessibilityLabel("Storage mode")

            switch mode {
            case .cleanup:
                CleanupView()
            case .largeFiles:
                browser
            case .duplicates:
                DuplicateFilesView()
            }

            if let trashReceipt {
                trashResult(trashReceipt, count: trashCount)
            }
        }
        .onDisappear { analyzeTask?.cancel() }
        .confirmationDialog(
            pendingTrashItems.count == 1
                ? "Move “\(pendingTrashItems[0].name)” to Trash?"
                : "Move \(pendingTrashItems.count) items (\(Fmt.bytes(pendingTrashBytes))) to Trash?",
            isPresented: Binding(get: { !pendingTrashItems.isEmpty },
                                 set: { if !$0 { pendingTrashItems = [] } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                trash(pendingTrashItems)
            }
            Button("Cancel", role: .cancel) { pendingTrashItems = [] }
        } message: {
            Text(pendingTrashItems.contains(where: \.isDirectory)
                 ? "Folders go to the Trash with everything inside them. You can put them back from Finder."
                 : "They go to the Trash, so you can put them back — nothing is deleted straight away.")
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

    private var volumeStrip: some View {
        let disks = poller.latest?.userDisks ?? []
        let primary = disks.first(where: { $0.isInternal == true }) ?? disks.first
        let others = disks.filter { $0.id != primary?.id }
        return HStack(spacing: 10) {
            if poller.latest == nil {
                Text("Reading volumes…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkTertiary)
            } else if let primary {
                Text(primary.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                MiniBar(percent: primary.usedPercent, height: 5)
                    .frame(width: 72)
                Text("\(Fmt.bytes(primary.free)) free of \(Fmt.bytes(primary.total))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                if !others.isEmpty {
                    Text("+\(others.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkTertiary)
                        .help(others.map(\.displayName).joined(separator: ", "))
                }
            } else {
                Text("No volumes to show.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkTertiary)
            }

            Spacer(minLength: 8)

            Button("Open Trash") { DiskAnalyzer.openTrash() }
                .font(.system(size: 11))
                .help("Emptying the Trash is irreversible, so Vitality hands that to Finder rather than doing it for you.")
        }
    }

    private func trashResult(_ receipt: TrashReceipt, count: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.statusGood)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(count > 1 ? "Moved \(count) items to Trash" : "Moved to Trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Recoverable in Finder until Trash is emptied")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkSecondary)
                if count == 1 {
                    Text(receipt.destinationURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(receipt.destinationURL.path)
                }
            }

            Spacer(minLength: 6)

            if count == 1 {
                Button("Reveal") {
                    DiskAnalyzer.revealInFinder(receipt.destinationURL.path)
                }
                .controlSize(.small)
                .accessibilityLabel("Reveal moved item in Finder")
            }

            Button("Open Trash") { DiskAnalyzer.openTrash() }
                .controlSize(.small)

            Button {
                trashReceipt = nil
                trashCount = 0
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
        .accessibilityLabel(count > 1
                            ? "Moved \(count) items to Trash"
                            : "Moved to Trash. Destination \(receipt.destinationURL.path)")
    }

    // MARK: Browser

    private var browser: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find large files")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text("Pick a folder. Click a folder name to look inside it.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DiskAnalyzer.suggestedRoots, id: \.path) { entry in
                        Button(entry.label) {
                            analyze(entry.path, resetBreadcrumb: true)
                        }
                        .buttonStyle(ThemePillButtonStyle(prominent: activeSuggestedRoot == entry.path))
                        .disabled(isAnalyzing)
                    }
                    Button("Choose…") { chooseFolder() }
                        .buttonStyle(ThemePillButtonStyle())
                        .disabled(isAnalyzing)
                }
            }

            HStack(spacing: 8) {
                if !breadcrumb.isEmpty {
                    Button("Back") { goUp() }
                        .disabled(isAnalyzing)
                        .accessibilityHint("Return to the previous folder")
                }
                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scanning")
                    Button("Cancel") { cancelAnalyze() }
                }
                Spacer(minLength: 8)
                if !selectedEntries.isEmpty {
                    Text("\(selectedEntries.count) selected · \(Fmt.bytes(selectedEntries.reduce(0) { $0 + $1.size }))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                    Button("Move \(selectedEntries.count) to Trash") {
                        pendingTrashItems = selectedEntries
                    }
                    .buttonStyle(ThemePillButtonStyle(prominent: true))
                    .disabled(isAnalyzing)
                }
            }

            if !path.isEmpty {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(path)
            }

            browserContent
        }
        .padding(13)
        .background(ThemeCardBackground())
    }

    @ViewBuilder
    private var browserContent: some View {
        if isAnalyzing && entries.isEmpty {
            centered {
                ProgressView()
                Text("Measuring \((path as NSString).lastPathComponent)…")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSecondary)
                Text("Folder sizes mean walking every file inside them, so large folders take a moment.")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let analyzeError {
            centered {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.statusWarn)
                Text(analyzeError)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if isProtected(path) {
                    Text("Downloads, Desktop and Documents are protected by macOS. Vitality needs your permission the first time it reads one.")
                        .font(.system(size: 10)).foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Files")!)
                    }
                    .font(.system(size: 11))
                }
            }
        } else if path.isEmpty {
            centered {
                Image(systemName: "folder").font(.system(size: 20)).foregroundStyle(Theme.inkSecondary)
                Text("Choose a folder above to see what's using space.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSecondary)
            }
        } else if entries.isEmpty {
            centered {
                Image(systemName: "folder").font(.system(size: 20)).foregroundStyle(Theme.inkSecondary)
                Text("Nothing to show in this folder.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSecondary)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedEntries) { entry in
                        browserRow(entry)
                        if entry.id != sortedEntries.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
            .frame(minHeight: 220)
        }
    }

    private func browserRow(_ entry: DiskEntry) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selectedPaths.contains(entry.path) },
                set: { isOn in
                    if isOn { selectedPaths.insert(entry.path) }
                    else { selectedPaths.remove(entry.path) }
                }
            ))
            .labelsHidden()
            .accessibilityLabel("Select \(entry.name)")

            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 14)

            if entry.isDirectory {
                Button(entry.name) { drillInto(entry.path) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .help("Measure inside this folder")
                    .accessibilityHint("Opens this folder")
            } else {
                Text(entry.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(Fmt.bytes(entry.size))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.ink)

            Button("Reveal") { DiskAnalyzer.revealInFinder(entry.path) }
                .controlSize(.small)
                .help("Show in Finder")

            Button("Trash", role: .destructive) { pendingTrashItems = [entry] }
                .controlSize(.small)
                .help("Move to Trash — recoverable")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
        selectedPaths = []

        analyzeTask?.cancel()
        analyzeTask = Task.detached(priority: .userInitiated) {
            let result = DiskAnalyzer.analyze(path: target)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isAnalyzing = false
                analyzeTask = nil
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

    private func cancelAnalyze() {
        analyzeTask?.cancel()
        analyzeTask = nil
        isAnalyzing = false
        analyzeError = nil
        entries = []
        selectedPaths = []
        path = ""
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

    private func trash(_ items: [DiskEntry]) {
        pendingTrashItems = []
        var lastReceipt: TrashReceipt?
        var moved = 0
        var firstError: String?
        for item in items {
            switch DiskAnalyzer.moveToTrash(item.path) {
            case .success(let receipt):
                entries.removeAll { $0.id == item.id }
                selectedPaths.remove(item.path)
                lastReceipt = receipt
                moved += 1
            case .failure(let error):
                if firstError == nil { firstError = error.message }
            }
        }
        trashCount = moved
        trashReceipt = lastReceipt
        if let firstError {
            actionError = items.count == 1
                ? firstError
                : "Moved \(moved) of \(items.count) items. \(firstError)"
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
    @State private var isCleaning = false
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
                    .foregroundStyle(Theme.ink)
                Spacer()
                if didScan && !isScanning {
                    Button("Scan again") { scan() }
                        .disabled(isCleaning)
                }
            }

            Text("Rebuildable caches are selected. Old downloads stay off until you choose them.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkSecondary)

            if isScanning {
                VStack(spacing: 7) {
                    ProgressView()
                    Text("Measuring caches, DerivedData and old downloads…")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if !didScan {
                VStack(spacing: 7) {
                    ProgressView()
                    Text("Looking for reclaimable space…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if categories.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24)).foregroundStyle(Theme.inkTertiary)
                    Text("Nothing worth reclaiming — this Mac is already tidy.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                if isCleaning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Moving items to the Trash…")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Moving items to the Trash")
                }
                list
                footer
            }

            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.statusGood)
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
            Text(selectedCategories.contains(where: { $0.id == "old-downloads" })
                 ? "Old downloads are original files, not rebuildable caches. Restore anything from the Trash."
                 : "Apps rebuild their caches as needed. Nothing is deleted permanently — restore anything from the Trash.")
        }
        .alert("Couldn't complete that",
               isPresented: Binding(get: { actionError != nil },
                                    set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .onAppear {
            if !didScan && !isScanning { scan() }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(categories) { category in
                categoryRow(category)
                if category.id != categories.last?.id {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .background(ThemeCardBackground(radius: Theme.nestedRadius))
    }

    @ViewBuilder
    private func categoryRow(_ category: CleanupCategory) -> some View {
        if category.kind == .trashable {
            let on = selected.contains(category.id)
            Button {
                if on { selected.remove(category.id) }
                else { selected.insert(category.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .foregroundStyle(on ? Theme.accent : Theme.inkDim)
                        .frame(width: 16)
                    categoryLabel(category)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(category.label)
            .accessibilityValue(on ? "Selected" : "Not selected")
        } else {
            HStack(spacing: 10) {
                Spacer().frame(width: 16)
                categoryLabel(category)
                Button("Open") { DiskAnalyzer.openTrash() }
                    .controlSize(.small)
                    .help("Emptying the Trash is irreversible, so Vitality hands that to Finder.")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func categoryLabel(_ category: CleanupCategory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(subtitle(for: category))
                    .font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
            Text(Fmt.bytes(category.bytes))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.inkSecondary)
        }
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack {
            Text(selectedCategories.isEmpty
                 ? "Click a category to include it."
                 : "\(Fmt.bytes(selectedBytes)) ready")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Button(selectedBytes > 0
                   ? "Move \(Fmt.bytes(selectedBytes)) to Trash"
                   : "Move to Trash") {
                confirmClean = true
            }
            .buttonStyle(ThemePillButtonStyle(prominent: true))
            .disabled(selectedCategories.isEmpty || isCleaning)
        }
    }

    private func subtitle(for category: CleanupCategory) -> String {
        let count = "\(category.itemCount) item\(category.itemCount == 1 ? "" : "s")"
        if category.isRebuildable { return "\(count) · apps rebuild these" }
        if category.id == "old-downloads" { return "\(count) · original files" }
        return "\(count) · empty in Finder"
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
                selected = Set(found.filter(\.isRebuildable).map(\.id))
            }
        }
    }

    private func clean() {
        let targets = selectedCategories
        isCleaning = true
        Task.detached(priority: .userInitiated) {
            let result = CleanupScanner.clean(targets)
            let rescanned = CleanupScanner.scan()
            await MainActor.run {
                isCleaning = false
                categories = rescanned
                selected = Set(rescanned.filter(\.isRebuildable).map(\.id))
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
