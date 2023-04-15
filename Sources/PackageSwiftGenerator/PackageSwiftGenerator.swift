import ArgumentParser
import Files
import Foundation
import PackageDescription
import ProjectAutomation
import SwiftPrettyPrint

typealias DTarget = PackageDescription.Target
typealias DPackage = PackageDescription.Package
typealias ATarget = ProjectAutomation.Target
typealias APackage = ProjectAutomation.Package

let fileManager = FileManager.default
let spmCheckOutFolder = ".build/checkouts"
let spmBuildFolder = ".build"

extension DPackage {
    func filterTargets(byNames targetNames: [String]) -> DPackage {
        let dict = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })
        let filteredTargetNames = dict.dependencyNames(of: targetNames)

        return DPackage(
            name: name,
            platforms: platforms,
            products: products,
            dependencies: dependencies.filter {
                guard let name = $0.name else {
                    if case let .fileSystem(_, path) = $0.kind {
                        return filteredTargetNames.contains(URL(filePath: path).lastPathComponent)
                    }
                    return true
                }
                return filteredTargetNames.contains(name)
            },
            targets: targets.filter { filteredTargetNames.contains($0.name) }
        )
    }
}

extension Dictionary where Key == String, Value == DTarget {
    func dependencyNames(of targetNames: [String]) -> Set<String> {
        var visited = Set<String>()
        for name in targetNames {
            DFS(name, &visited)
        }

        return visited
    }

    func DFS(_ name: String, _ visited: inout Set<String>) {
        if visited.contains(name) {
            return
        }
        visited.insert(name)
        guard let target = self[name] else {
            return
        }
        for dependency in target.dependencies {
            switch dependency {
            case let .productItem(name, packageName, _, _):
                DFS(name, &visited)
                if let packageName = packageName {
                    DFS(packageName, &visited)
                }
            case let .targetItem(name, _):
                DFS(name, &visited)
            case let .byNameItem(name, _):
                DFS(name, &visited)
            }
        }
    }
}

extension FileManager {
    func directoryExistsAtPath(_ path: String) -> Bool {
        var isDirectory: ObjCBool = true
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

extension Array where Element == URL {
    func commonFolder() -> URL? {
        guard let first = first else {
            return nil
        }

        let commonPath = first.pathComponents
            .enumerated()
            .reduce(into: [String]()) { result, element in
                let (index, path) = element
                if self.allSatisfy({ $0.pathComponents.count > index && $0.pathComponents[index] == path }) {
                    result.append(path)
                }
            }

        return commonPath.asFolderPath
    }
}

extension Array where Element == String {
    func commonFolder(relativeTo url: URL) -> String? {
        let urls = compactMap { URL(fileURLWithPath: $0).deletingLastPathComponent() } // remove the filename to get the folder path
        guard let common = urls.commonFolder() else { return nil }
        return common.relative(to: url)
    }

    var asFolderPath: URL? {
        guard let first = first else { return nil }

        let url = URL(fileURLWithPath: first)
        return dropFirst().reduce(url) { result, path in
            result.appendingPathComponent(path)
        }
    }
}

/// we need to use sources property if the sources files are separated in different folders
struct PathSourcesItem {
    let path: String
    let sources: [String]
}

extension URL {
    func relative(to url: URL) -> String {
        let pathComponents = self.pathComponents
        let otherPathComponents = url.pathComponents

        let commonPath = pathComponents
            .enumerated()
            .reduce(into: [String]()) { result, element in
                let (index, path) = element
                if otherPathComponents.count > index {
                    if otherPathComponents[index] == path {
                        result.append(path)
                    }
                }
            }

        let relativePath: [String] =
            otherPathComponents
                .dropFirst(commonPath.count)
                .map { _ in ".." }
                +
                Array(pathComponents
                    .dropFirst(commonPath.count))

        return relativePath.joined(separator: "/")
    }
}

public struct PackageSwiftGenerator {
    private func libraryTargets(_ project: Project) -> [DTarget] {
        let targets: [ATarget] = project.targets
        let libraryTargets: [DTarget] = targets
            .compactMap { (target: ATarget) -> DTarget? in

                let dependencies: [DTarget.Dependency] = target.dependencies.compactMap(\.dtDependency)
                guard let path = target.sources.commonFolder(relativeTo: URL(fileURLWithPath: project.path)) else {
                    fatalError("no source folder for \(target.name) file:\(target.sources.first)")
                }

                let sourcePath = URL(fileURLWithPath: path)
                func resource(path: String) -> Resource {
                    let url: URL = .init(filePath: path)
                    let relativePath: String = url.relative(to: sourcePath)

                    if FileManager.default.directoryExistsAtPath(path)
                        || url.pathExtension == "xcassets"
                    {
                        // just copy the whole folder
                        return Resource.copy(relativePath)
                    } else {
                        return Resource.process(relativePath)
                    }
                }

                switch target.product {
                case "staticFramework":
                    return DTarget.target(name: target.name,
                                          dependencies: dependencies,
                                          path: path,
                                          resources: target.resources.map(resource(path:)))
                case "app":
                    return DTarget.target(name: target.name,
                                          dependencies: dependencies,
                                          path: path,
                                          resources: target.resources.map(resource(path:)))
                case "unit_tests":
                    return DTarget.testTarget(name: target.name,
                                              dependencies: dependencies,
                                              path: path,
                                              resources: target.resources.map(resource(path:)))
                default:
                    print("unsupported: \(target.name) with product type:\(target.product)")
                    return nil
                }
            }
        return libraryTargets
    }

    private func swiftPackages(_ project: Project) -> [DPackage.Dependency] {
        let targets = project.targets
        // avoid duplicated paths
        let packagePaths: Set<String> = Set(Set(targets.map { target in
            target.dependencies
        }.joined())
            .compactMap { dependency in
                switch dependency {
                case let .project(target: _, path: path):

                    if path.contains(spmCheckOutFolder) {
                        return path
                    }
                case .target:
                    // ignore other non swift package targets
                    break
                default:
                    print("unknown dependency: \(dependency)")
                }

                return nil
            })

        let dep: [DPackage.Dependency] = packagePaths.map { path in
            .package(path: path)
        }

        return dep
    }

    private func projectToPackage(_ project: Project) -> DPackage {
        let targets: [DTarget] = libraryTargets(project)

        let swiftPackages: [DPackage.Dependency] = swiftPackages(project)
        return DPackage(
            name: project.name,
            platforms: [
                .iOS(.v11),
            ],
            dependencies: swiftPackages,
            targets: targets
        )
    }

    private func targetFieldsFilter(target _: DTarget, fields: Fields) -> Fields {
        // reorder "dependencies" and "path" properties
        var rest: Fields = fields.filter {
            $0.0 != "dependencies"
                &&
                $0.0 != "path"
        }

        if let dep = fields.filter({ $0.0 == "dependencies" }).first {
            rest.insert(dep, at: 1)
        }

        if let dep = fields.filter({ $0.0 == "path" }).first {
            rest.insert(dep, at: 2)
        }

        return rest
            .filter { $0.1 != "[\n\n]" } // remove empty arrays
            .filter { $0.1 != "nil" } // remove nil values
            .filter { $0.1 != ".regular" } // remove "type: .regular"
            .filter { $0.1 != ".test" } // remove "type: .test"
            .filter { $0.1 != ".package" } // remove "group: .package"
    }

    private func packageFieldsFilter(package _: DPackage, fields: Fields) -> Fields {
        // reorder "products" and "dependencies" properties
        var rest: Fields = fields.filter {
            $0.0 != "products"
                &&
                $0.0 != "dependencies"
        }

        if let dep = fields.filter({ $0.0 == "products" }).first {
            rest.insert(dep, at: 2)
        }
        if let dep = fields.filter({ $0.0 == "dependencies" }).first {
            rest.insert(dep, at: 3)
        }

        return rest
            .filter { $0.1 != "nil" } // remove nil values
    }

    public func run(tuistRoot: String, projectName: String, targetNames: [String]) throws {
        // .macOS("15.0"),
        let supportedPlatform = """
        .iOS("13.0"), .macOS("15.0")
        """

        let graph = try Tuist.graph(at: tuistRoot)

        guard let project = graph.projects.values.filter({ $0.name == projectName }).first else {
            print("no project found, available projects: \(graph.projects.values.map(\.name))")
            return
        }

        var package = projectToPackage(project)
        if !targetNames.isEmpty {
            package = package.filterTargets(byNames: targetNames)
        }

        var logger = UnicodeLogger()

        SimpleDescriber.customEnumFilter = { target, _, originalString -> String in

            if let dep = target as? DTarget.Dependency {
                switch dep {
                case let .targetItem(name, _):
                    return "\"\(name)\""
                case let .byNameItem(name, _):
                    return "\"\(name)\""
                case let .productItem(name: name, package: package, _, _):
                    if let package = package {
                        return ".product(name: \"\(name)\", package: \"\(package)\")"
                    }
                @unknown default:
                    fatalError("unknown dependency: \(dep)")
                }
            }

            return originalString
        }

        SimpleDescriber.customFieldsReorder = { target, fields in

            var fields = fields
            if let target = target as? DTarget {
                fields = self.targetFieldsFilter(target: target, fields: fields)
            }

            if let package = target as? DPackage {
                fields = self.packageFieldsFilter(package: package, fields: fields)
            }

            return fields
        }

        SimpleDescriber.customObjectFilter = { target, _, original, fields in

            if target is SupportedPlatform {
                return supportedPlatform
            }

            if case let dep = target as? DPackage.Dependency,
               case let .fileSystem(_, path) = dep?.kind
            {
                return """
                .package(path: "\(path)")
                """
            }

            let fields: Fields = fields
            if target is Resource {
                // workaround internal Resource var

                let rule: String = fields.compactMap { tuple in
                    if tuple.0 == "rule" {
                        return tuple.1
                    }
                    return nil
                }.first!

                if let path = fields.compactMap({ tuple in
                    if tuple.0 == "path" {
                        return tuple.1
                    }
                    return nil
                }).first {
                    if rule == "\"copy\"" {
                        return """
                         .copy(\(path))
                        """
                    } else {
                        return """
                         .process(\(path))
                        """
                    }
                }
            }

            var original = original
            if original.contains("_platforms:") {
                // if we compile this plugin into binary file
                // `_platforms:` will show up instead of `platforms:`
                // I don't know why
                original = original.replacing("_platforms:", with: "platforms:")
            }
            if original.contains("_resources:") {
                // same as above
                original = original.replacing("_resources:", with: "resources:")
            }

            var lines = original.split(separator: "\n")

            // monkey patch
            if lines.first == "Target(" {
                if let target = target as? DTarget {
                    if target.isTest {
                        lines[0] = ".testTarget("
                    } else {
                        lines[0] = ".target("
                    }
                }
            }

            return lines.joined(separator: "\n")
        }

        SimpleDescriber.customValueFilter = { _, _, original in
            original
        }

        Pretty.customizablePrettyPrint(package, to: &logger)

        let data = logger.logged.data(using: .utf8)!
        let url = URL(fileURLWithPath: tuistRoot).appendingPathComponent("Package.swift")
        try! data.write(to: url)

        print("Package.swift generated at \(url)")
//        Pretty.prettyPrint(project)
    }
}

@available(macOS 13.0, *)
enum Error: Swift.Error {
    case missingFileName
    case failedToCreateFile
    case missingProjectName
}
