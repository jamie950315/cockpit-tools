import Foundation

struct CatalogRepository: Sendable {
    let paths: CatalogPaths
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    init(paths: CatalogPaths = .live()) {
        self.paths = paths
    }

    func load() throws -> LoadedCatalog {
        let configData = try readData(paths.config)
        let managedData = try readData(paths.managedCatalog)
        let providerData = try readData(paths.providerCatalog)
        let routeData = try readData(paths.routeStore)
        let configValue = try decoder.decode(JSONValue.self, from: configData)
        let managedValue = try decoder.decode(JSONValue.self, from: managedData)
        guard let configRoot = configValue.objectValue else {
            throw CatalogError.invalidRoot(paths.config.path)
        }
        guard let managedRoot = managedValue.objectValue else {
            throw CatalogError.invalidRoot(paths.managedCatalog.path)
        }
        guard let routeRoot = try decoder.decode(JSONValue.self, from: routeData).objectValue else {
            throw CatalogError.invalidRoot(paths.routeStore.path)
        }
        guard let modelValues = configRoot["models"]?.arrayValue else {
            throw CatalogError.missingModels(paths.config.path)
        }
        let decodedModels = modelValues.compactMap { value -> CatalogModel? in
            guard let fields = value.objectValue else { return nil }
            return CatalogModel(fields: fields)
        }
        guard decodedModels.count == modelValues.count else {
            throw CatalogError.missingModels(paths.config.path)
        }
        let lockedModelIDs = CatalogEditor.builtInModelIDs(
            managedRoot: managedRoot,
            availableModels: decodedModels
        )
        let models = CatalogEditor.placingBuiltInsFirst(
            models: decodedModels,
            lockedModelIDs: lockedModelIDs
        )
        return LoadedCatalog(
            configRoot: configRoot,
            managedRoot: managedRoot,
            models: models,
            routedModelIDs: readManifestModelIDs(),
            providerModelIDs: try readProviderModelIDs(from: providerData),
            routeRoot: routeRoot,
            routeModelIDs: try readRouteModelIDs(from: routeRoot),
            lockedModelIDs: lockedModelIDs,
            orderWasNormalized: models.map { $0.modelID.lowercased() }
                != decodedModels.map { $0.modelID.lowercased() },
            configFingerprint: configData,
            managedFingerprint: managedData,
            providerFingerprint: providerData,
            routeFingerprint: routeData
        )
    }

    func sourcesChanged(since loaded: LoadedCatalog) -> Bool {
        (try? readData(paths.providerCatalog)) != loaded.providerFingerprint
            || (try? readData(paths.routeStore)) != loaded.routeFingerprint
            || readManifestModelIDs() != loaded.routedModelIDs
    }

    func save(_ loaded: LoadedCatalog, models: [CatalogModel]) throws -> URL {
        guard try readData(paths.config) == loaded.configFingerprint,
              try readData(paths.managedCatalog) == loaded.managedFingerprint else {
            throw CatalogError.filesChangedExternally
        }
        let routed = Set(loaded.routeModelIDs.map { $0.lowercased() })
        try CatalogEditor.validate(models: models, routedIDs: routed)
        guard CatalogEditor.preservesLockedOrder(
            models: models,
            lockedModelIDs: loaded.lockedModelIDs
        ) else {
            throw CatalogError.lockedModelOrder
        }

        var configRoot = loaded.configRoot
        configRoot["models"] = .array(models.map { .object($0.fields) })
        let managedRoot = try rebuildManagedCatalog(
            root: loaded.managedRoot,
            models: models,
            lockedModelIDs: loaded.lockedModelIDs
        )
        let configData = try encoded(.object(configRoot))
        let managedData = try encoded(.object(managedRoot))

        let backupDirectory = try createBackupDirectory()
        try backup(paths.config, to: backupDirectory)
        try backup(paths.managedCatalog, to: backupDirectory)

        do {
            try managedData.write(to: paths.managedCatalog, options: .atomic)
            try setPrivatePermissions(paths.managedCatalog)
            try configData.write(to: paths.config, options: .atomic)
            try setPrivatePermissions(paths.config)
        } catch {
            try? restore(paths.managedCatalog, from: backupDirectory)
            try? restore(paths.config, from: backupDirectory)
            throw error
        }
        return backupDirectory
    }

    func synchronizeProviderAdditions(_ loaded: LoadedCatalog) throws -> ModelSyncResult {
        guard try readData(paths.config) == loaded.configFingerprint,
              try readData(paths.managedCatalog) == loaded.managedFingerprint,
              try readData(paths.providerCatalog) == loaded.providerFingerprint,
              try readData(paths.routeStore) == loaded.routeFingerprint else {
            throw CatalogError.filesChangedExternally
        }

        let providerRawIDs = Self.uniqued(
            loaded.providerModelIDs.compactMap(Self.removeCPAPrefix)
        )
        let routeRawSet = Set(loaded.routeModelIDs.compactMap(Self.removeCPAPrefix).map { $0.lowercased() })
        let addedRawIDs = providerRawIDs.filter { !routeRawSet.contains($0.lowercased()) }
        let desiredRouteIDs = loaded.routeModelIDs + addedRawIDs.map { "CPA/\($0)" }

        let currentCatalogSet = Set(loaded.models.map { $0.modelID.lowercased() })
        let catalogAdditions = desiredRouteIDs.filter { !currentCatalogSet.contains($0.lowercased()) }
        let desiredModels = loaded.models + catalogAdditions.map {
            CatalogModel.newModel(id: $0, displayName: Self.defaultDisplayName(for: $0))
        }

        guard !addedRawIDs.isEmpty || !catalogAdditions.isEmpty else {
            return ModelSyncResult(addedToRoute: [], addedToCatalog: [], backupDirectory: nil)
        }

        let updatedRouteRoot = try updatingRoute(
            root: loaded.routeRoot,
            upstreamModels: loaded.routeModelIDs.compactMap(Self.removeCPAPrefix) + addedRawIDs
        )
        try CatalogEditor.validate(
            models: desiredModels,
            routedIDs: Set(desiredRouteIDs.map { $0.lowercased() })
        )
        guard CatalogEditor.preservesLockedOrder(
            models: desiredModels,
            lockedModelIDs: loaded.lockedModelIDs
        ) else {
            throw CatalogError.lockedModelOrder
        }
        var configRoot = loaded.configRoot
        configRoot["models"] = .array(desiredModels.map { .object($0.fields) })
        let managedRoot = try rebuildManagedCatalog(
            root: loaded.managedRoot,
            models: desiredModels,
            lockedModelIDs: loaded.lockedModelIDs
        )
        let routeData = try encoded(.object(updatedRouteRoot))
        let configData = try encoded(.object(configRoot))
        let managedData = try encoded(.object(managedRoot))

        let backupDirectory = try createBackupDirectory()
        try backup(paths.routeStore, to: backupDirectory)
        try backup(paths.config, to: backupDirectory)
        try backup(paths.managedCatalog, to: backupDirectory)

        do {
            try routeData.write(to: paths.routeStore, options: .atomic)
            try setPrivatePermissions(paths.routeStore)
            try managedData.write(to: paths.managedCatalog, options: .atomic)
            try setPrivatePermissions(paths.managedCatalog)
            try configData.write(to: paths.config, options: .atomic)
            try setPrivatePermissions(paths.config)
        } catch {
            try? restore(paths.routeStore, from: backupDirectory)
            try? restore(paths.managedCatalog, from: backupDirectory)
            try? restore(paths.config, from: backupDirectory)
            throw error
        }
        return ModelSyncResult(
            addedToRoute: addedRawIDs.map { "CPA/\($0)" },
            addedToCatalog: catalogAdditions,
            backupDirectory: backupDirectory
        )
    }

    func removeProviderRemovals(_ loaded: LoadedCatalog) throws -> ModelRemovalResult {
        guard try readData(paths.config) == loaded.configFingerprint,
              try readData(paths.managedCatalog) == loaded.managedFingerprint,
              try readData(paths.providerCatalog) == loaded.providerFingerprint,
              try readData(paths.routeStore) == loaded.routeFingerprint else {
            throw CatalogError.filesChangedExternally
        }

        let providerSet = Set(loaded.providerModelIDs.map { $0.lowercased() })
        let removedRouteIDs = loaded.routeModelIDs.filter {
            !providerSet.contains($0.lowercased())
        }
        let removedSet = Set(removedRouteIDs.map { $0.lowercased() })
        let desiredRouteIDs = loaded.routeModelIDs.filter {
            !removedSet.contains($0.lowercased())
        }
        let desiredModels = loaded.models.filter {
            !removedSet.contains($0.modelID.lowercased())
        }
        let removedCatalogIDs = loaded.models
            .map(\.modelID)
            .filter { removedSet.contains($0.lowercased()) }

        guard !removedRouteIDs.isEmpty || !removedCatalogIDs.isEmpty else {
            return ModelRemovalResult(
                removedFromRoute: [],
                removedFromCatalog: [],
                backupDirectory: nil
            )
        }

        try CatalogEditor.validate(
            models: desiredModels,
            routedIDs: Set(desiredRouteIDs.map { $0.lowercased() })
        )
        guard CatalogEditor.preservesLockedOrder(
            models: desiredModels,
            lockedModelIDs: loaded.lockedModelIDs
        ) else {
            throw CatalogError.lockedModelOrder
        }

        let updatedRouteRoot = try updatingRoute(
            root: loaded.routeRoot,
            upstreamModels: desiredRouteIDs.compactMap(Self.removeCPAPrefix)
        )
        var configRoot = loaded.configRoot
        configRoot["models"] = .array(desiredModels.map { .object($0.fields) })
        let managedRoot = try rebuildManagedCatalog(
            root: loaded.managedRoot,
            models: desiredModels,
            lockedModelIDs: loaded.lockedModelIDs
        )
        let routeData = try encoded(.object(updatedRouteRoot))
        let configData = try encoded(.object(configRoot))
        let managedData = try encoded(.object(managedRoot))

        let backupDirectory = try createBackupDirectory()
        try backup(paths.routeStore, to: backupDirectory)
        try backup(paths.config, to: backupDirectory)
        try backup(paths.managedCatalog, to: backupDirectory)

        do {
            try routeData.write(to: paths.routeStore, options: .atomic)
            try setPrivatePermissions(paths.routeStore)
            try managedData.write(to: paths.managedCatalog, options: .atomic)
            try setPrivatePermissions(paths.managedCatalog)
            try configData.write(to: paths.config, options: .atomic)
            try setPrivatePermissions(paths.config)
        } catch {
            try? restore(paths.routeStore, from: backupDirectory)
            try? restore(paths.managedCatalog, from: backupDirectory)
            try? restore(paths.config, from: backupDirectory)
            throw error
        }

        return ModelRemovalResult(
            removedFromRoute: removedRouteIDs,
            removedFromCatalog: removedCatalogIDs,
            backupDirectory: backupDirectory
        )
    }

    private func rebuildManagedCatalog(
        root: [String: JSONValue],
        models: [CatalogModel],
        lockedModelIDs: [String]
    ) throws -> [String: JSONValue] {
        guard let currentValues = root["models"]?.arrayValue else {
            throw CatalogError.missingModels(paths.managedCatalog.path)
        }
        let currentObjects = currentValues.compactMap(\.objectValue)
        let bySlug = Dictionary(
            currentObjects.compactMap { object -> (String, [String: JSONValue])? in
                guard let slug = object["slug"]?.stringValue else { return nil }
                return (slug.lowercased(), object)
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard let genericTemplate = currentObjects.first(where: {
            guard let slug = $0["slug"]?.stringValue else { return false }
            let lowered = slug.lowercased()
            return slug.contains("/")
                && $0["visibility"]?.stringValue == "list"
                && !lowered.contains("auto-review")
                && !lowered.contains("image")
                && !lowered.contains("video")
        }) ?? currentObjects.first else {
            throw CatalogError.noTemplate
        }

        let locked = Set(lockedModelIDs.map { $0.lowercased() })
        let rebuilt = models.enumerated().map { index, definition -> JSONValue in
            let id = definition.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = definition.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            var object = bySlug[id.lowercased()] ?? genericTemplate
            object["slug"] = .string(id)
            object["display_name"] = .string(name)
            object["description"] = .string(name)
            if !locked.contains(id.lowercased()) {
                object["priority"] = .integer(Int64(1_000 + index))
                object["visibility"] = .string("list")
                object["supported_in_api"] = .bool(true)
            }
            if let context = definition.fields["context_window"]?.integerValue {
                object["context_window"] = .integer(context)
                object["max_context_window"] = .integer(context)
            }
            if let compact = definition.fields["auto_compact_token_limit"]?.integerValue {
                object["auto_compact_token_limit"] = .integer(compact)
            }
            if let efforts = definition.fields["reasoning_efforts"]?.arrayValue?
                .compactMap(\.stringValue), !efforts.isEmpty,
               let supported = object["supported_reasoning_levels"]?.arrayValue {
                let filtered = supported.filter { level in
                    guard let effort = level.objectValue?["effort"]?.stringValue else { return false }
                    return efforts.contains(effort)
                }
                object["supported_reasoning_levels"] = .array(filtered)
                object["default_reasoning_level"] = .string(efforts[0])
            }
            return .object(object)
        }
        var result = root
        result["models"] = .array(rebuilt)
        return result
    }

    private func readManifestModelIDs() -> [String] {
        struct Manifest: Decodable { let modelIds: [String] }
        guard let data = try? Data(contentsOf: paths.manifest),
              let manifest = try? decoder.decode(Manifest.self, from: data) else { return [] }
        return manifest.modelIds
    }

    private func readProviderModelIDs(from data: Data) throws -> [String] {
        struct Provider: Decodable {
            let name: String
            let modelCatalog: [String]
        }
        guard let providers = try? decoder.decode([Provider].self, from: data),
              let provider = providers.first(where: { $0.name == "CLIProxyAPI" }),
              !provider.modelCatalog.isEmpty else {
            throw CatalogError.invalidProviderCatalog
        }
        return provider.modelCatalog.map { "CPA/\($0)" }
    }

    private func readRouteModelIDs(from root: [String: JSONValue]) throws -> [String] {
        let location = try mixedRouteLocation(in: root)
        return location.upstreamModels.map { "CPA/\($0)" }
    }

    private func updatingRoute(
        root: [String: JSONValue],
        upstreamModels: [String]
    ) throws -> [String: JSONValue] {
        let location = try mixedRouteLocation(in: root)
        var result = root
        guard var apiKeys = result["apiKeys"]?.arrayValue,
              var apiKey = apiKeys[location.apiKeyIndex].objectValue,
              var routing = apiKey["modelRouting"]?.objectValue,
              var routes = routing["routes"]?.arrayValue,
              var route = routes[location.routeIndex].objectValue,
              var gateway = route["providerGateway"]?.objectValue else {
            throw CatalogError.missingMixedRoute
        }
        gateway["upstreamModels"] = .array(upstreamModels.map(JSONValue.string))
        route["providerGateway"] = .object(gateway)
        routes[location.routeIndex] = .object(route)
        routing["routes"] = .array(routes)
        apiKey["modelRouting"] = .object(routing)
        apiKeys[location.apiKeyIndex] = .object(apiKey)
        result["apiKeys"] = .array(apiKeys)
        return result
    }

    private func mixedRouteLocation(
        in root: [String: JSONValue]
    ) throws -> (apiKeyIndex: Int, routeIndex: Int, upstreamModels: [String]) {
        guard let apiKeys = root["apiKeys"]?.arrayValue else {
            throw CatalogError.missingMixedRoute
        }
        for (apiKeyIndex, value) in apiKeys.enumerated() {
            guard let apiKey = value.objectValue,
                  let routing = apiKey["modelRouting"]?.objectValue else { continue }
            guard routing["defaultRoute"]?.stringValue == "oauth",
                  routing["failurePolicy"]?.stringValue == "strict" else {
                throw CatalogError.unsafeMixedRoute
            }
            guard let routes = routing["routes"]?.arrayValue else { continue }
            for (routeIndex, routeValue) in routes.enumerated() {
                guard let route = routeValue.objectValue,
                      route["namespace"]?.stringValue == "CPA",
                      let gateway = route["providerGateway"]?.objectValue,
                      let values = gateway["upstreamModels"]?.arrayValue else { continue }
                let ids = values.compactMap(\.stringValue)
                guard ids.count == values.count else { throw CatalogError.missingMixedRoute }
                return (apiKeyIndex, routeIndex, ids)
            }
        }
        throw CatalogError.missingMixedRoute
    }

    private static func removeCPAPrefix(_ id: String) -> String? {
        guard id.hasPrefix("CPA/"), id.count > 4 else { return nil }
        return String(id.dropFirst(4))
    }

    private static func defaultDisplayName(for id: String) -> String {
        guard let slash = id.firstIndex(of: "/") else { return id }
        return "\(id[..<slash]) · \(id[id.index(after: slash)...])"
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    private func readData(_ url: URL) throws -> Data {
        guard let data = try? Data(contentsOf: url) else {
            throw CatalogError.unreadableFile(url.path)
        }
        return data
    }

    private func encoded(_ value: JSONValue) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    private func createBackupDirectory() throws -> URL {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date()
        )
        let stamp = String(
            format: "%04d%02d%02d-%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
        let uniqueStamp = "\(stamp)-\(UUID().uuidString.prefix(8))"
        let directory = paths.backups.appending(path: uniqueStamp, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func backup(_ source: URL, to directory: URL) throws {
        let destination = directory.appending(path: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        try setPrivatePermissions(destination)
    }

    private func restore(_ destination: URL, from directory: URL) throws {
        let source = directory.appending(path: destination.lastPathComponent)
        let data = try Data(contentsOf: source)
        try data.write(to: destination, options: .atomic)
        try setPrivatePermissions(destination)
    }

    private func setPrivatePermissions(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
