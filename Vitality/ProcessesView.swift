import SwiftUI

/// Initial table context used when Activity is opened from an alert. The
/// process list remains a native, dense table; only its starting query/order
/// changes so the alert's evidence is immediately visible.
enum ProcessSort: Hashable {
    case cpu
    case memory
    case name
}

struct ProcessesView: View {
    @State private var processes: [RunningProcess] = []
    @State private var query = ""
    @State private var pendingQuit: RunningProcess?
    @State private var errorMessage: String?
    @State private var refreshTimer: Timer?

    /// Bound to the Table so clicking a column header re-sorts. Binding this
    /// alone does nothing — `visible` must also apply it via `sorted(using:)`.
    @State private var sortOrder: [KeyPathComparator<RunningProcess>] = [
        KeyPathComparator(\RunningProcess.cpu, order: .reverse)
    ]

    private var visible: [RunningProcess] {
        let filtered = query.isEmpty
            ? processes
            : processes.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return filtered.sorted(using: sortOrder)
    }

    init(initialQuery: String = "", initialSort: ProcessSort = .cpu) {
        _query = State(initialValue: initialQuery)
        let comparator: KeyPathComparator<RunningProcess>
        switch initialSort {
        case .cpu:
            comparator = KeyPathComparator(\RunningProcess.cpu, order: .reverse)
        case .memory:
            comparator = KeyPathComparator(\RunningProcess.memoryBytes, order: .reverse)
        case .name:
            comparator = KeyPathComparator(\RunningProcess.name, order: .forward)
        }
        _sortOrder = State(initialValue: [comparator])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Processes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Live process activity")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Spacer()

                TextField("Filter processes", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .accessibilityLabel("Filter processes")
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Refresh processes")
                .help("Refresh process list")
            }

            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.statusGood)
                    .accessibilityHidden(true)
                Text("Live")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.statusGood)
                Text("\(visible.count) visible of \(processes.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                if let busiest = visible.max(by: { $0.cpu < $1.cpu }) {
                    Text("Highest CPU: \(busiest.name) · \(Fmt.percent(busiest.cpu, decimals: 1))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if visible.isEmpty && !query.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.inkTertiary)
                    Text("No processes match \"\(query)\"")
                        .font(Theme.body(13, .medium))
                        .foregroundStyle(Theme.ink)
                    Button("Clear filter") { query = "" }
                }
                .frame(maxWidth: .infinity, minHeight: 240)
                .background(ThemeCardBackground(radius: Theme.nestedRadius))
            } else {
                Table(visible, sortOrder: $sortOrder) {
                    TableColumn("Process", value: \.name) { process in
                        Text(process.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    TableColumn("PID", value: \.pid) { process in
                        Text(verbatim: "\(process.pid)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .width(60)
                    TableColumn("CPU", value: \.cpu) { process in
                        Text(Fmt.percent(process.cpu, decimals: 1))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Severity.forUsage(process.cpu))
                    }
                    .width(64)
                    TableColumn("Memory", value: \.memoryBytes) { process in
                        Text(Fmt.bytes(process.memoryBytes))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.ink)
                    }
                    .width(80)
                    TableColumn("") { process in
                        TableAction(title: "Quit",
                                    enabled: process.isOwnedByCurrentUser) {
                            pendingQuit = process
                        }
                        .accessibilityLabel("Quit \(process.name)")
                        .help(process.isOwnedByCurrentUser
                              ? "Ask \(process.name) to quit"
                              : "Owned by another user — Vitality can't quit it")
                    }
                    .width(52)
                }
                .frame(minHeight: 240)
            }

            Text("Click a column header to sort. System processes owned by another user cannot be quit from Vitality.")
                .font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
        }
        .padding(13)
        .background(ThemeCardBackground())
        .onAppear(perform: start)
        .onDisappear { refreshTimer?.invalidate(); refreshTimer = nil }
        .confirmationDialog(
            pendingQuit.map { "Quit \($0.name)?" } ?? "Quit process?",
            isPresented: Binding(get: { pendingQuit != nil },
                                 set: { if !$0 { pendingQuit = nil } }),
            titleVisibility: .visible
        ) {
            Button("Quit") {
                if let target = pendingQuit { quit(target, force: false) }
            }
            Button("Force Quit", role: .destructive) {
                if let target = pendingQuit { quit(target, force: true) }
            }
            Button("Cancel", role: .cancel) { pendingQuit = nil }
        } message: {
            Text("Quit asks the app to close and save. Force Quit ends it immediately — unsaved work is lost.")
        }
        .alert("Couldn't quit process",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func start() {
        reload()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in reload() }
        }
    }

    private func reload() {
        Task.detached(priority: .utility) {
            // The dashboard intentionally shows the complete process table.
            // Compact top-N consumers must pass an explicit limit instead.
            let list = ProcessManager.listAll()
            await MainActor.run { processes = list }
        }
    }

    private func quit(_ process: RunningProcess, force: Bool) {
        pendingQuit = nil
        if case .failure(let error) = ProcessManager.terminate(process, force: force) {
            errorMessage = error.message
        }
        // Give the process a moment to actually exit before redrawing the table.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { reload() }
    }
}
