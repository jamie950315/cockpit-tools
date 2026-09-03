import Foundation
import Testing
@testable import CodexModelManager

private func model(_ id: String, name: String? = nil) -> CatalogModel {
    CatalogModel(fields: [
        "model_id": .string(id),
        "display_name": .string(name ?? id),
        "context_window": .integer(526_316),
        "auto_compact_token_limit": .integer(450_000),
    ])
}

@Test func movesModelsByOneBasedPosition() {
    let models = [model("a"), model("b"), model("c"), model("d")]
    let moved = CatalogEditor.move(models: models, from: 3, toPosition: 2)
    #expect(moved.map(\.modelID) == ["a", "d", "b", "c"])
}

@Test func clampsPositionsToCatalogBounds() {
    let models = [model("a"), model("b"), model("c")]
    #expect(CatalogEditor.move(models: models, from: 1, toPosition: 0).map(\.modelID) == ["b", "a", "c"])
    #expect(CatalogEditor.move(models: models, from: 0, toPosition: 99).map(\.modelID) == ["b", "c", "a"])
}

@Test func detectsProviderAdditionsAndRemovalsWithoutChangingEitherSet() {
    let difference = CatalogEditor.differences(
        providerIDs: ["CPA/keep", "CPA/new"],
        routeIDs: ["CPA/keep", "CPA/removed", "CPA/catalog-missing"],
        catalogIDs: ["CPA/keep", "CPA/removed"]
    )
    #expect(difference.providerOnly == ["CPA/new"])
    #expect(difference.routeOnly == ["CPA/removed", "CPA/catalog-missing"])
    #expect(difference.routeMissingFromCatalog == ["CPA/catalog-missing"])
}

@Test func rejectsDuplicateAndUnroutedModels() {
    #expect(throws: CatalogError.duplicateModel("CPA/a")) {
        try CatalogEditor.validate(
            models: [model("CPA/a"), model("CPA/a")],
            routedIDs: ["cpa/a"]
        )
    }
    #expect(throws: CatalogError.unroutedModel("CPA/missing")) {
        try CatalogEditor.validate(
            models: [model("CPA/missing")],
            routedIDs: ["cpa/a"]
        )
    }
}

@Test func repositoryPreservesUnknownFieldsAndWritesOrder() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let paths = CatalogPaths(
        config: root.appending(path: "config.json"),
        managedCatalog: root.appending(path: "catalog.json"),
        manifest: root.appending(path: "manifest.json"),
        providerCatalog: root.appending(path: "providers.json"),
        routeStore: root.appending(path: "routes.json"),
        backups: root.appending(path: "backups", directoryHint: .isDirectory)
    )
    try Data(#"{"version":4,"future":{"keep":true},"models":[{"model_id":"CPA/a","display_name":"A","context_window":526316,"auto_compact_token_limit":450000},{"model_id":"CPA/b","display_name":"B","context_window":526316,"auto_compact_token_limit":450000}]}"#.utf8)
        .write(to: paths.config)
    try Data(#"{"models":[{"slug":"CPA/a","display_name":"A","description":"A","visibility":"list","priority":1000,"future":"keep"},{"slug":"CPA/b","display_name":"B","description":"B","visibility":"list","priority":1001}]}"#.utf8)
        .write(to: paths.managedCatalog)
    try Data(#"{"modelIds":["CPA/a","CPA/b","CPA/c"]}"#.utf8).write(to: paths.manifest)
    try Data(#"[{"name":"CLIProxyAPI","modelCatalog":["a","b","c"],"apiKeys":["never-decoded"]}]"#.utf8)
        .write(to: paths.providerCatalog)
    try Data(#"{"future":"keep","apiKeys":[{"label":"not-first-assumption","secret":"preserve","modelRouting":{"defaultRoute":"oauth","failurePolicy":"strict","routes":[{"namespace":"CPA","providerGateway":{"apiKey":"preserve","upstreamModels":["a","b","c"]}}]}}]}"#.utf8)
        .write(to: paths.routeStore)

    let repository = CatalogRepository(paths: paths)
    var loaded = try repository.load()
    loaded.models = CatalogEditor.move(models: loaded.models, from: 1, toPosition: 1)
    loaded.models[0].displayName = "First"
    loaded.models.append(.newModel(id: "CPA/c", displayName: "Third"))
    _ = try repository.save(loaded, models: loaded.models)

    let reloaded = try repository.load()
    #expect(reloaded.models.map(\.modelID) == ["CPA/b", "CPA/a", "CPA/c"])
    #expect(reloaded.models[0].displayName == "First")
    #expect(reloaded.configRoot["future"] == .object(["keep": .bool(true)]))
    let managedB = reloaded.managedRoot["models"]?.arrayValue?.first?.objectValue
    #expect(managedB?["priority"] == .integer(1000))
    let managedA = reloaded.managedRoot["models"]?.arrayValue?[1].objectValue
    #expect(managedA?["future"] == .string("keep"))
    let managedC = reloaded.managedRoot["models"]?.arrayValue?.last?.objectValue
    #expect(managedC?["slug"] == .string("CPA/c"))
    #expect(managedC?["display_name"] == .string("Third"))
    #expect(managedC?["priority"] == .integer(1002))
    #expect(managedC?["context_window"] == .integer(526_316))
}

@Test func refusesToOverwriteExternalChanges() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = CatalogPaths(
        config: root.appending(path: "config.json"),
        managedCatalog: root.appending(path: "catalog.json"),
        manifest: root.appending(path: "manifest.json"),
        providerCatalog: root.appending(path: "providers.json"),
        routeStore: root.appending(path: "routes.json"),
        backups: root.appending(path: "backups", directoryHint: .isDirectory)
    )
    try Data(#"{"version":4,"models":[{"model_id":"CPA/a","display_name":"A"}]}"#.utf8)
        .write(to: paths.config)
    try Data(#"{"models":[{"slug":"CPA/a","display_name":"A","visibility":"list"}]}"#.utf8)
        .write(to: paths.managedCatalog)
    try Data(#"{"modelIds":["CPA/a"]}"#.utf8).write(to: paths.manifest)
    try Data(#"[{"name":"CLIProxyAPI","modelCatalog":["a"]}]"#.utf8).write(to: paths.providerCatalog)
    try Data(#"{"apiKeys":[{"modelRouting":{"defaultRoute":"oauth","failurePolicy":"strict","routes":[{"namespace":"CPA","providerGateway":{"upstreamModels":["a"]}}]}}]}"#.utf8)
        .write(to: paths.routeStore)
    let repository = CatalogRepository(paths: paths)
    let loaded = try repository.load()
    try Data(#"{"version":4,"changed":true,"models":[{"model_id":"CPA/a","display_name":"A"}]}"#.utf8)
        .write(to: paths.config)

    #expect(throws: CatalogError.filesChangedExternally) {
        _ = try repository.save(loaded, models: loaded.models)
    }
}

@Test func synchronizesProviderOnlyModelsWithoutRemovingOrExposingUnknownFields() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = CatalogPaths(
        config: root.appending(path: "config.json"),
        managedCatalog: root.appending(path: "catalog.json"),
        manifest: root.appending(path: "manifest.json"),
        providerCatalog: root.appending(path: "providers.json"),
        routeStore: root.appending(path: "routes.json"),
        backups: root.appending(path: "backups", directoryHint: .isDirectory)
    )
    try Data(#"{"models":[{"model_id":"CPA/old","display_name":"Old","context_window":526316,"auto_compact_token_limit":450000}]}"#.utf8).write(to: paths.config)
    try Data(#"{"models":[{"slug":"CPA/old","display_name":"Old","visibility":"list","future":"keep"}]}"#.utf8).write(to: paths.managedCatalog)
    try Data(#"{"modelIds":["CPA/old"]}"#.utf8).write(to: paths.manifest)
    try Data(#"[{"name":"Other","modelCatalog":["wrong"]},{"name":"CLIProxyAPI","modelCatalog":["old","new","new","newer"],"apiKeys":["provider-secret"]}]"#.utf8).write(to: paths.providerCatalog)
    try Data(#"{"topFuture":"keep","apiKeys":[{"label":"plain","key":"first-secret","modelRouting":null},{"label":"routed","key":"second-secret","unknown":"keep","modelRouting":{"defaultRoute":"oauth","failurePolicy":"strict","routes":[{"id":"route","namespace":"CPA","providerGateway":{"apiKey":"gateway-secret","wireApi":"responses","upstreamModels":["old"]}}]}}]}"#.utf8).write(to: paths.routeStore)

    let repository = CatalogRepository(paths: paths)
    let loaded = try repository.load()
    #expect(loaded.routeModelIDs == ["CPA/old"])
    let result = try repository.synchronizeProviderAdditions(loaded)
    #expect(result.addedToRoute == ["CPA/new", "CPA/newer"])
    #expect(result.addedToCatalog == ["CPA/new", "CPA/newer"])

    let reloaded = try repository.load()
    #expect(reloaded.routeModelIDs == ["CPA/old", "CPA/new", "CPA/newer"])
    #expect(reloaded.models.map(\.modelID) == ["CPA/old", "CPA/new", "CPA/newer"])
    #expect(reloaded.routeRoot["topFuture"] == .string("keep"))
    let routedAccount = reloaded.routeRoot["apiKeys"]?.arrayValue?[1].objectValue
    #expect(routedAccount?["key"] == .string("second-secret"))
    #expect(routedAccount?["unknown"] == .string("keep"))
    let routing = routedAccount?["modelRouting"]?.objectValue
    #expect(routing?["defaultRoute"] == .string("oauth"))
    #expect(routing?["failurePolicy"] == .string("strict"))
    let route = routing?["routes"]?.arrayValue?.first?.objectValue
    #expect(route?["namespace"] == .string("CPA"))
    #expect(route?["providerGateway"]?.objectValue?["apiKey"] == .string("gateway-secret"))
}

@Test func refusesUnsafeOrExternallyChangedRouteSynchronization() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = CatalogPaths(
        config: root.appending(path: "config.json"),
        managedCatalog: root.appending(path: "catalog.json"),
        manifest: root.appending(path: "manifest.json"),
        providerCatalog: root.appending(path: "providers.json"),
        routeStore: root.appending(path: "routes.json"),
        backups: root.appending(path: "backups", directoryHint: .isDirectory)
    )
    try Data(#"{"models":[{"model_id":"CPA/a","display_name":"A"}]}"#.utf8).write(to: paths.config)
    try Data(#"{"models":[{"slug":"CPA/a","display_name":"A","visibility":"list"}]}"#.utf8).write(to: paths.managedCatalog)
    try Data(#"{"modelIds":["CPA/a"]}"#.utf8).write(to: paths.manifest)
    try Data(#"[{"name":"CLIProxyAPI","modelCatalog":["a","b"]}]"#.utf8).write(to: paths.providerCatalog)
    try Data(#"{"apiKeys":[{"modelRouting":{"defaultRoute":"oauth","failurePolicy":"strict","routes":[{"namespace":"CPA","providerGateway":{"upstreamModels":["a"]}}]}}]}"#.utf8).write(to: paths.routeStore)
    let repository = CatalogRepository(paths: paths)
    let loaded = try repository.load()
    try Data(#"{"changed":true,"apiKeys":[{"modelRouting":{"defaultRoute":"oauth","failurePolicy":"strict","routes":[{"namespace":"CPA","providerGateway":{"upstreamModels":["a"]}}]}}]}"#.utf8).write(to: paths.routeStore)
    #expect(throws: CatalogError.filesChangedExternally) {
        _ = try repository.synchronizeProviderAdditions(loaded)
    }

    try Data(#"{"apiKeys":[{"modelRouting":{"defaultRoute":"provider","failurePolicy":"fallback","routes":[{"namespace":"CPA","providerGateway":{"upstreamModels":["a"]}}]}}]}"#.utf8).write(to: paths.routeStore)
    #expect(throws: CatalogError.unsafeMixedRoute) {
        _ = try repository.load()
    }
}
