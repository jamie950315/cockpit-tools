import Foundation

struct CatalogModel: Identifiable, Equatable, Sendable {
    let id: UUID
    var fields: [String: JSONValue]

    init(id: UUID = UUID(), fields: [String: JSONValue]) {
        self.id = id
        self.fields = fields
    }

    var modelID: String {
        get { fields["model_id"]?.stringValue ?? "" }
        set { fields["model_id"] = .string(newValue) }
    }

    var displayName: String {
        get { fields["display_name"]?.stringValue ?? modelID }
        set { fields["display_name"] = .string(newValue) }
    }

    var contextSummary: String {
        let context = fields["context_window"]?.integerValue
        let compact = fields["auto_compact_token_limit"]?.integerValue
        guard let context, let compact else { return "Default" }
        return "\(Self.compactNumber(context)) / \(Self.compactNumber(compact))"
    }

    static func newModel(id: String, displayName: String) -> CatalogModel {
        CatalogModel(fields: [
            "model_id": .string(id),
            "display_name": .string(displayName),
            "context_window": .integer(526_316),
            "auto_compact_token_limit": .integer(450_000),
        ])
    }

    private static func compactNumber(_ value: Int64) -> String {
        if value >= 1_000_000, value % 1_000_000 == 0 {
            return "\(value / 1_000_000)M"
        }
        if value >= 1_000 {
            return "\(value / 1_000)K"
        }
        return String(value)
    }
}

struct CatalogPaths: Sendable {
    let config: URL
    let managedCatalog: URL
    let manifest: URL
    let providerCatalog: URL
    let routeStore: URL
    let backups: URL

    static func live(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> CatalogPaths {
        CatalogPaths(
            config: homeDirectory.appending(path: ".codex/.cockpit-experimental-model-catalog-config.json"),
            managedCatalog: homeDirectory.appending(path: ".codex/cockpit-model-catalog.json"),
            manifest: homeDirectory.appending(path: ".antigravity_cockpit/codex_local_access_sidecar/manifest.json"),
            providerCatalog: homeDirectory.appending(path: ".antigravity_cockpit/codex_model_providers.json"),
            routeStore: homeDirectory.appending(path: ".antigravity_cockpit/codex_local_access.json"),
            backups: homeDirectory.appending(path: ".codex/model-manager-backups", directoryHint: .isDirectory)
        )
    }
}

struct LoadedCatalog: Sendable {
    var configRoot: [String: JSONValue]
    var managedRoot: [String: JSONValue]
    var models: [CatalogModel]
    var routedModelIDs: [String]
    var providerModelIDs: [String]
    var routeRoot: [String: JSONValue]
    var routeModelIDs: [String]
    var lockedModelIDs: [String]
    var orderWasNormalized: Bool
    var configFingerprint: Data
    var managedFingerprint: Data
    var providerFingerprint: Data
    var routeFingerprint: Data
}

struct ModelSyncResult: Sendable {
    let addedToRoute: [String]
    let addedToCatalog: [String]
    let backupDirectory: URL?
}

struct ModelRemovalResult: Sendable {
    let removedFromRoute: [String]
    let removedFromCatalog: [String]
    let backupDirectory: URL?
}

struct ModelCatalogDifference: Equatable, Sendable {
    let providerOnly: [String]
    let routeOnly: [String]
    let routeMissingFromCatalog: [String]
}

enum CatalogError: LocalizedError, Equatable {
    case unreadableFile(String)
    case invalidRoot(String)
    case missingModels(String)
    case invalidModel(String)
    case duplicateModel(String)
    case unroutedModel(String)
    case filesChangedExternally
    case noTemplate
    case missingMixedRoute
    case unsafeMixedRoute
    case invalidProviderCatalog
    case lockedModelOrder

    var errorDescription: String? {
        switch self {
        case let .unreadableFile(path): "無法讀取 \(path)。"
        case let .invalidRoot(path): "\(path) 不是有效的 JSON 物件。"
        case let .missingModels(path): "\(path) 沒有模型清單。"
        case let .invalidModel(id): "模型 \(id.isEmpty ? "（空白）" : id) 的 ID 或顯示名稱無效。"
        case let .duplicateModel(id): "模型 ID \(id) 重複出現。"
        case let .unroutedModel(id): "模型 \(id) 尚未由 Cockpit 的即時路由宣告。"
        case .filesChangedExternally: "Cockpit 已在背景更新模型檔案。請重新載入後再編輯，以免覆寫較新的資料。"
        case .noTemplate: "受管 catalog 中沒有可安全沿用的模型範本。"
        case .missingMixedRoute: "找不到使用 modelRouting 的 API key，或找不到大寫 CPA 路由。"
        case .unsafeMixedRoute: "混合路由不是 OAuth 預設加 strict 失敗策略，已停止同步以保護現有路由。"
        case .invalidProviderCatalog: "找不到有效的 CLIProxyAPI 模型清單。請先在 Cockpit Tools 刷新並儲存供應商清單。"
        case .lockedModelOrder: "內建模型的位置不可變更，自訂模型只能排列在內建模型之後。"
        }
    }
}

enum CatalogEditor {
    static func builtInModelIDs(
        managedRoot: [String: JSONValue],
        availableModels: [CatalogModel]
    ) -> [String] {
        let available = Set(availableModels.map { $0.modelID.lowercased() })
        return (managedRoot["models"]?.arrayValue ?? [])
            .enumerated()
            .compactMap { index, value -> (priority: Int64, index: Int, id: String)? in
                guard let object = value.objectValue,
                      let id = object["slug"]?.stringValue,
                      !id.contains("/"),
                      available.contains(id.lowercased()),
                      object["visibility"]?.stringValue != "hide",
                      let priority = object["priority"]?.integerValue,
                      priority >= 0,
                      priority < 1_000 else { return nil }
                return (priority, index, id)
            }
            .sorted {
                $0.priority == $1.priority ? $0.index < $1.index : $0.priority < $1.priority
            }
            .map(\.id)
    }

    static func placingBuiltInsFirst(
        models: [CatalogModel],
        lockedModelIDs: [String]
    ) -> [CatalogModel] {
        let lockedKeys = lockedModelIDs.map { $0.lowercased() }
        let lockedSet = Set(lockedKeys)
        let byID = Dictionary(
            models.map { ($0.modelID.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return lockedKeys.compactMap { byID[$0] }
            + models.filter { !lockedSet.contains($0.modelID.lowercased()) }
    }

    static func preservesLockedOrder(
        models: [CatalogModel],
        lockedModelIDs: [String]
    ) -> Bool {
        let expected = lockedModelIDs.map { $0.lowercased() }
        guard models.count >= expected.count else { return false }
        return Array(models.prefix(expected.count).map { $0.modelID.lowercased() }) == expected
    }

    static func differences(
        providerIDs: [String],
        routeIDs: [String],
        catalogIDs: [String]
    ) -> ModelCatalogDifference {
        let provider = Set(providerIDs.map { $0.lowercased() })
        let route = Set(routeIDs.map { $0.lowercased() })
        let catalog = Set(catalogIDs.map { $0.lowercased() })
        return ModelCatalogDifference(
            providerOnly: providerIDs.filter { !route.contains($0.lowercased()) },
            routeOnly: routeIDs.filter { !provider.contains($0.lowercased()) },
            routeMissingFromCatalog: routeIDs.filter { !catalog.contains($0.lowercased()) }
        )
    }

    static func move(
        models: [CatalogModel],
        from source: Int,
        toPosition position: Int,
        lockedModelIDs: [String] = []
    ) -> [CatalogModel] {
        guard models.indices.contains(source), !models.isEmpty else { return models }
        let locked = Set(lockedModelIDs.map { $0.lowercased() })
        guard !locked.contains(models[source].modelID.lowercased()) else { return models }
        let minimumPosition = min(lockedModelIDs.count + 1, models.count)
        let destination = min(max(position, minimumPosition), models.count) - 1
        guard source != destination else { return models }
        var result = models
        let model = result.remove(at: source)
        result.insert(model, at: destination)
        return result
    }

    static func validate(models: [CatalogModel], routedIDs: Set<String>) throws {
        var seen = Set<String>()
        for model in models {
            let id = model.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let allowed = id.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || ".-_:/".unicodeScalars.contains($0)
            }
            guard !id.isEmpty, id.count <= 128, allowed, !name.isEmpty, name.count <= 100 else {
                throw CatalogError.invalidModel(id)
            }
            let key = id.lowercased()
            guard seen.insert(key).inserted else { throw CatalogError.duplicateModel(id) }
            if id.contains("/"), !routedIDs.contains(key) {
                throw CatalogError.unroutedModel(id)
            }
        }
    }
}
