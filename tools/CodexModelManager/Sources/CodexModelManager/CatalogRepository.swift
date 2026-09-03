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
        let configValue = try decoder.decode(JSONValue.self, from: configData)
        let managedValue = try decoder.decode(JSONValue.self, from: managedData)
        guard let configRoot = configValue.objectValue else {
            throw CatalogError.invalidRoot(paths.config.path)
        }
        guard let managedRoot = managedValue.objectValue else {
            throw CatalogError.invalidRoot(paths.managedCatalog.path)
        }
        guard let modelValues = configRoot["models"]?.arrayValue else {
            throw CatalogError.missingModels(paths.config.path)
        }
        let models = modelValues.compactMap { value -> CatalogModel? in
            guard let fields = value.objectValue else { return nil }
            return CatalogModel(fields: fields)
        }
        guard models.count == modelValues.count else {
            throw CatalogError.missingModels(paths.config.path)
        }
        return LoadedCatalog(
            configRoot: configRoot,
            managedRoot: managedRoot,
            models: models,
            routedModelIDs: readManifestModelIDs(),
            providerModelIDs: readProviderModelIDs(),
            configFingerprint: configData,
            managedFingerprint: managedData
        )
    }

    func save(_ loaded: LoadedCatalog, models: [CatalogModel]) throws -> URL {
        guard try readData(paths.config) == loaded.configFingerprint,
              try readData(paths.managedCatalog) == loaded.managedFingerprint else {
            throw CatalogError.filesChangedExternally
        }
        let routed = Set(loaded.routedModelIDs.map { $0.lowercased() })
        try CatalogEditor.validate(models: models, routedIDs: routed)

        var configRoot = loaded.configRoot
        configRoot["models"] = .array(models.map { .object($0.fields) })
        let managedRoot = try rebuildManagedCatalog(
            root: loaded.managedRoot,
            models: models
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

    private func rebuildManagedCatalog(
        root: [String: JSONValue],
        models: [CatalogModel]
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

        let rebuilt = models.enumerated().map { index, definition -> JSONValue in
            let id = definition.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = definition.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            var object = bySlug[id.lowercased()] ?? genericTemplate
            object["slug"] = .string(id)
            object["display_name"] = .string(name)
            object["description"] = .string(name)
            if id.contains("/") {
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

    private func readProviderModelIDs() -> [String] {
        struct Provider: Decodable {
            let name: String
            let modelCatalog: [String]
        }
        guard let data = try? Data(contentsOf: paths.providerCatalog),
              let providers = try? decoder.decode([Provider].self, from: data),
              let provider = providers.first(where: { $0.name == "CLIProxyAPI" }) else { return [] }
        return provider.modelCatalog.map { "CPA/\($0)" }
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
        let directory = paths.backups.appending(path: stamp, directoryHint: .isDirectory)
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
