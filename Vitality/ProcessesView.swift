import SwiftUI

struct ProcessesView: View {
    @State private var processes: [RunningProcess] = []
    @State private var query = ""
    @State private var sort: SortField = .cpu
    @State private var pendingQuit: RunningProcess?
    @State private var errorMessage: String?
    @State private var refreshTimer: Timer?

    enum SortField: String, CaseIterable, Identifiable {
        case cpu = "CPU", memory = "Memory", name = "Name"
        var id: String { rawValue }
    }

    private var visible: [RunningProcess] {
        let filtered = query.isEmpty
            ? processes
            : processes.filter { $0.name.localizedCaseInsensitiveContains(query) }

        switch sort {
        case .cpu:    return filtered.sorted { $0.cpu > $1.cpu }
        case .memory: return filtered.sorted { $0.memoryBytes > $1.memoryBytes }
        case .name:   return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Filter processes", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Picker("", selection: $sort) {
                    ForEach(SortField.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)

                Spacer()
                Text("\(visible.count) shown")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Table(visible) {
                TableColumn("Process") { process in
                    Text(process.name).font(.system(size: 12)).lineLimit(1)
                }
                TableColumn("PID") { process in
                    Text("\(process.pid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(58)
                TableColumn("CPU") { process in
                    Text(Fmt.percent(process.cpu, decimals: 1))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Severity.forUsage(process.cpu))
                }
                .width(62)
                TableColumn("Memory") { process in
                    Text(Fmt.bytes(process.memoryBytes)).font(.system(size: 11))
                }
                .width(78)
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

            Text("System processes owned by root can't be quit from here — that's macOS, not Vitality.")
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
