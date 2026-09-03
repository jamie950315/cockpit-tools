import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class CatalogStore: ObservableObject {
    @Published var models: [CatalogModel] = []
    @Published var routedModelIDs: [String] = []
    @Published var providerModelIDs: [String] = []
    @Published var routeModelIDs: [String] = []
    @Published var isCockpitRunning = false
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var isDirty = false
    @Published var message: String?
    @Published var errorMessage: String?

    private let repository: CatalogRepository
    private var loaded: LoadedCatalog?

    init(repository: CatalogRepository = CatalogRepository()) {
        self.repository = repository
    }

    var visibleModels: [CatalogModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.modelID.lowercased().contains(query) || $0.displayName.lowercased().contains(query)
        }
    }

    var availableAdditions: [String] {
        let current = Set(models.map { $0.modelID.lowercased() })
        return routedModelIDs.filter {
            !current.contains($0.lowercased()) && !Self.intentionallyHiddenModelIDs.contains($0.lowercased())
        }
    }

    var providerOnlyModels: [String] {
        let routed = Set(routeModelIDs.map { $0.lowercased() })
        return providerModelIDs.filter { !routed.contains($0.lowercased()) }
    }

    var routeOnlyCatalogAdditions: [String] {
        let current = Set(models.map { $0.modelID.lowercased() })
        return routeModelIDs.filter { !current.contains($0.lowercased()) }
    }

    var pendingSyncCount: Int {
        Set((providerOnlyModels + routeOnlyCatalogAdditions).map { $0.lowercased() }).count
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try repository.load()
            loaded = result
            models = result.models
            routedModelIDs = result.routedModelIDs
            providerModelIDs = result.providerModelIDs
            routeModelIDs = result.routeModelIDs
            refreshCockpitState()
            isDirty = false
            errorMessage = nil
            message = "已載入 \(models.count) 個模型。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSourcesIfNeeded() {
        refreshCockpitState()
        guard !isDirty, let loaded, repository.sourcesChanged(since: loaded) else { return }
        load()
        message = pendingSyncCount > 0
            ? "偵測到 \(pendingSyncCount) 個模型等待同步。"
            : "來源已自動重新載入。"
    }

    func synchronizeModels() {
        refreshCockpitState()
        guard !isCockpitRunning, let loaded else {
            errorMessage = "Cockpit Tools 正在執行。請先完成使用中的 Codex 工作並關閉 Cockpit，再進行同步。"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try repository.synchronizeProviderAdditions(loaded)
            self.loaded = try repository.load()
            if let refreshed = self.loaded {
                models = refreshed.models
                routedModelIDs = refreshed.routedModelIDs
                providerModelIDs = refreshed.providerModelIDs
                routeModelIDs = refreshed.routeModelIDs
            }
            isDirty = false
            errorMessage = nil
            if result.addedToRoute.isEmpty && result.addedToCatalog.isEmpty {
                message = "供應商、混合路由與 Codex 清單已同步。"
            } else {
                message = "已同步：路由新增 \(result.addedToRoute.count) 個，Codex 清單新增 \(result.addedToCatalog.count) 個。請重新開啟 Cockpit，再從 API Service 啟動 Codex。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func binding(for id: UUID) -> Binding<CatalogModel> {
        Binding(
            get: { [weak self] in
                self?.models.first(where: { $0.id == id }) ?? CatalogModel(fields: [:])
            },
            set: { [weak self] updated in
                guard let self, let index = self.models.firstIndex(where: { $0.id == id }) else { return }
                self.models[index] = updated
                self.markDirty()
            }
        )
    }

    func position(of id: UUID) -> Int {
        (models.firstIndex(where: { $0.id == id }) ?? 0) + 1
    }

    func move(id: UUID, toPosition position: Int) {
        guard let source = models.firstIndex(where: { $0.id == id }) else { return }
        models = CatalogEditor.move(models: models, from: source, toPosition: position)
        markDirty()
    }

    func move(id: UUID, by offset: Int) {
        move(id: id, toPosition: position(of: id) + offset)
    }

    func addRoutedModels(_ ids: Set<String>) {
        let routed = Set(routedModelIDs.map { $0.lowercased() })
        let existing = Set(models.map { $0.modelID.lowercased() })
        for id in routedModelIDs where ids.contains(id) && routed.contains(id.lowercased()) && !existing.contains(id.lowercased()) {
            models.append(.newModel(id: id, displayName: Self.defaultDisplayName(for: id)))
        }
        markDirty()
    }

    func save() {
        guard let loaded else { return }
        do {
            let backup = try repository.save(loaded, models: models)
            self.loaded = try repository.load()
            isDirty = false
            errorMessage = nil
            message = "已儲存，備份為 \(backup.lastPathComponent)。重新啟動 Codex 後載入新清單。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealBackups() {
        NSWorkspace.shared.open(repository.paths.backups)
    }

    func sourceLabel(for model: CatalogModel) -> String {
        if !model.modelID.contains("/") { return "官方" }
        let routed = Set(routedModelIDs.map { $0.lowercased() })
        return routed.contains(model.modelID.lowercased()) ? "已路由" : "不可用"
    }

    private func markDirty() {
        isDirty = true
        message = nil
        errorMessage = nil
    }

    private func refreshCockpitState() {
        isCockpitRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.jlcodes.cockpit-tools"
        ).isEmpty
    }

    private static func defaultDisplayName(for id: String) -> String {
        guard let slash = id.firstIndex(of: "/") else { return id }
        let namespace = id[..<slash]
        let upstream = id[id.index(after: slash)...]
        return "\(namespace) · \(upstream)"
    }

    private static let intentionallyHiddenModelIDs: Set<String> = [
        "gpt-image-2",
    ]
}
