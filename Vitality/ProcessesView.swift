import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Filter processes", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer()
                Text("\(visible.count) of \(processes.count)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Table(visible, sortOrder: $sortOrder) {
                TableColumn("Process", value: \.name) { process in
                    Text(process.name).font(.system(size: 12)).lineLimit(1)
                }
                TableColumn("PID", value: \.pid) { process in
                    Text(verbatim: "\(process.pid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(60)
                TableColumn("CPU", value: \.cpu) { process in
                    Text(Fmt.percent(process.cpu, decimals: 1))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Severity.forUsage(process.cpu))
                }
                .width(64)
                TableColumn("Memory", value: \.memoryBytes) { process in
                    Text(Fmt.bytes(process.memoryBytes)).font(.system(size: 11))
                }
                .width(80)
                TableColumn("") { process in
                    Button("Quit") { pendingQuit = process }
                        .font(.system(size: 11))
                        .disabled(!process.isOwnedByCurrentUser)
                        .help(process.isOwnedByCurrentUser
                              ? "Ask \(process.name) to quit"
                              : "Owned by another user — Vitality can't quit it")
                }
                .width(52)
            }
            .frame(minHeight: 240)

            Text("Click a column header to sort. System processes owned by root can't be quit from here — that's macOS, not Vitality.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .onAppear(perform: start)
        .onDisappear { refreshTimer?.invalidate(); refreshTimer = nil }
        .confirmationDialog(
            pendingQuit.map { "Quit \($0.name)?" } ?? "Quit process?",
            isPresented: Binding(get: { pendingQuit != nil },
                                 set: { if !$0 { pendingQuit = nil } }),
            titleVisibility: .visible
        ) {
            if let target = pendingQuit {
                Button("Quit") { quit(target, force: false) }
                Button("Force Quit", role: .destructive) { quit(target, force: true) }
                Button("Cancel", role: .cancel) { pendingQuit = nil }
            }
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
            let list = ProcessManager.list()
            await MainActor.run { processes = list }
        }
    }

    private func quit(_ process: RunningProcess, force: Bool) {
        pendingQuit = nil
        if case .failure(let error) = ProcessManager.terminate(pid: process.pid, force: force) {
            errorMessage = error.message
        }
        // Give the process a moment to actually exit before redrawing the table.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { reload() }
    }
}
