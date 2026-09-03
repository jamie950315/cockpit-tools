import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CatalogStore
    @State private var additionsOpen = false
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            catalogList
            Divider()
            footer
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if store.models.isEmpty { store.load() }
        }
        .onReceive(refreshTimer) { _ in store.refreshSourcesIfNeeded() }
        .sheet(isPresented: $additionsOpen) {
            AddModelsSheet(isPresented: $additionsOpen)
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex 模型管理器")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("調整真正的寫入順序、顯示名稱，並加入已路由的新模型。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            MetricPill(value: store.providerModelIDs.count, label: "供應商")
            MetricPill(value: store.routeModelIDs.count, label: "混合路由")
            MetricPill(value: store.models.count, label: "Codex")
            Button {
                store.load()
            } label: {
                Label("重新載入", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(store.isLoading || store.isDirty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var catalogList: some View {
        VStack(spacing: 0) {
            if store.pendingSyncCount > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("有 \(store.pendingSyncCount) 個新模型等待同步")
                            .font(.callout.weight(.semibold))
                        Text(store.isCockpitRunning
                            ? "安全起見，請先完成使用中的 Codex 工作並關閉 Cockpit Tools。"
                            : "同步只會加入即時路由已宣告的模型，不會修改路由或移除項目。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.synchronizeModels()
                    } label: {
                        Label("同步模型", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isCockpitRunning || store.isDirty || store.isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.orange.opacity(0.09))
                Divider()
            }
            if !store.providerOnlyModels.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("有 \(store.providerOnlyModels.count) 個供應商模型尚未進入即時路由")
                            .font(.callout.weight(.semibold))
                        Text("請先在 Cockpit Tools 完成路由更新；此工具不會修改路由設定。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.orange.opacity(0.09))
                Divider()
            }
            if !store.removedProviderModels.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("偵測到 \(store.removedProviderModels.count) 個模型已從供應商移除")
                            .font(.callout.weight(.semibold))
                        Text(store.removedProviderModels.joined(separator: "、"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text("僅偵測，不自動刪除")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.red.opacity(0.08))
                Divider()
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("依模型 ID 或顯示名稱篩選", text: $store.searchText)
                    .textFieldStyle(.plain)
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .padding(14)

            HStack(spacing: 12) {
                Text("位置").frame(width: 72, alignment: .leading)
                Text("模型 ID").frame(minWidth: 270, maxWidth: .infinity, alignment: .leading)
                Text("顯示名稱").frame(minWidth: 250, maxWidth: .infinity, alignment: .leading)
                Text("來源").frame(width: 84, alignment: .leading)
                Text("上下文").frame(width: 116, alignment: .leading)
                Spacer().frame(width: 64, height: 1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 7)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.visibleModels) { model in
                        CatalogRow(
                            model: store.binding(for: model.id),
                            position: store.position(of: model.id),
                            total: store.models.count,
                            source: store.sourceLabel(for: model),
                            onMove: { store.move(id: model.id, toPosition: $0) },
                            onNudge: { store.move(id: model.id, by: $0) }
                        )
                        Divider()
                    }
                }
                .padding(.horizontal, 12)
            }
            .overlay {
                if store.visibleModels.isEmpty {
                    ContentUnavailableView.search(text: store.searchText)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let message = store.message {
                Label(message, systemImage: store.isDirty ? "pencil" : "checkmark.circle.fill")
                    .foregroundStyle(store.isDirty ? Color.secondary : Color.green)
                    .lineLimit(2)
            } else if store.isDirty {
                Label("有尚未儲存的變更", systemImage: "pencil")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("備份") { store.revealBackups() }
                .buttonStyle(.bordered)
            Button {
                additionsOpen = true
            } label: {
                Label("加入模型", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            Button {
                store.synchronizeModels()
            } label: {
                Label("同步模型", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .disabled(store.isCockpitRunning || store.isDirty || store.isLoading || store.pendingSyncCount == 0)
            .help(store.isCockpitRunning ? "請先關閉 Cockpit Tools" : "將即時路由的新模型加入 Codex 清單")
            Button {
                store.save()
            } label: {
                Label("儲存清單", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled((!store.isDirty && !store.needsPriorityRepair) || store.isLoading)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct CatalogRow: View {
    @Binding var model: CatalogModel
    let position: Int
    let total: Int
    let source: String
    let onMove: (Int) -> Void
    let onNudge: (Int) -> Void
    @State private var positionText: String
    @FocusState private var positionFocused: Bool

    init(
        model: Binding<CatalogModel>,
        position: Int,
        total: Int,
        source: String,
        onMove: @escaping (Int) -> Void,
        onNudge: @escaping (Int) -> Void
    ) {
        _model = model
        self.position = position
        self.total = total
        self.source = source
        self.onMove = onMove
        self.onNudge = onNudge
        _positionText = State(initialValue: String(position))
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                TextField("", text: $positionText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 43)
                    .multilineTextAlignment(.center)
                    .focused($positionFocused)
                    .onSubmit(commitPosition)
                    .onChange(of: position) { _, newValue in
                        if !positionFocused { positionText = String(newValue) }
                    }
                    .onChange(of: positionFocused) { wasFocused, isFocused in
                        if wasFocused && !isFocused { commitPosition() }
                    }
            }
            .frame(width: 72, alignment: .leading)

            Text(model.modelID)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.modelID)
                .frame(minWidth: 270, maxWidth: .infinity, alignment: .leading)

            TextField("顯示名稱", text: $model.displayName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 250, maxWidth: .infinity)

            Text(source)
                .font(.caption.weight(.medium))
                .foregroundStyle(source == "已路由" || source == "官方" ? .green : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.55), in: Capsule())
                .frame(width: 84, alignment: .leading)

            Text(model.contextSummary)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .leading)

            HStack(spacing: 2) {
                Button { onNudge(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(position <= 1)
                Button { onNudge(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(position >= total)
            }
            .buttonStyle(.borderless)
            .frame(width: 64)
        }
        .padding(.vertical, 2)
    }

    private func commitPosition() {
        guard let requested = Int(positionText) else {
            positionText = String(position)
            return
        }
        onMove(requested)
        positionFocused = false
    }
}

private struct MetricPill: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value, format: .number)
                .font(.system(.headline, design: .rounded).weight(.semibold))
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct AddModelsSheet: View {
    @EnvironmentObject private var store: CatalogStore
    @Binding var isPresented: Bool
    @State private var selection = Set<String>()
    @State private var query = ""

    private var additions: [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return store.availableAdditions }
        return store.availableAdditions.filter { $0.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("加入已路由模型").font(.title2.weight(.semibold))
                    Text("只會列出 Cockpit 即時 manifest 已宣告的模型。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新載入來源") { store.load() }
            }
            .padding(20)
            Divider()
            TextField("篩選可加入的模型", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(16)
            List(additions, id: \.self, selection: $selection) { id in
                Text(id).font(.system(.body, design: .monospaced))
            }
            .overlay {
                if store.availableAdditions.isEmpty {
                    ContentUnavailableView(
                        "清單已是最新",
                        systemImage: "checkmark.circle",
                        description: Text("目前沒有已路由但尚未加入的模型。")
                    )
                }
            }
            if !store.providerOnlyModels.isEmpty {
                Label(
                    "另有 \(store.providerOnlyModels.count) 個 provider 模型尚未進入路由，因此不會加入。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }
            Divider()
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                Button("加入 \(selection.count) 個") {
                    store.addRoutedModels(selection)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 720, height: 560)
    }
}
