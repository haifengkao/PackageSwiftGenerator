import Files
import Foundation
import PackageDescription
import ProjectAutomation
import SwiftPrettyPrint
import ArgumentParser

typealias DTarget = PackageDescription.Target
typealias DPackage = PackageDescription.Package
typealias ATarget = ProjectAutomation.Target
typealias APackage = ProjectAutomation.Package

let fileManager = FileManager.default
let spmCheckOutFolder = ".build/checkouts"
let spmBuildFolder = ".build"

struct UnicodeLogger: TextOutputStream {
    static let header = """
    // swift-tools-version: 5.7
    // The swift-tools-version declares the minimum version of Swift required to build this package.

    import PackageDescription

    let package = 
    """
    var logged: String = Self.header
    mutating func write(_ string: String) {
        let lines = string.split(separator: "\n")
        for line in lines {
            handleLine(String(line))
        }
    }

    mutating func handleLine(_ line: String) {
        guard !line.isEmpty, line != "\n" else {
            return
        }

        logged += line + "\n"
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
struct GenerateCommand: ParsableCommand {
    @Option(help: "tuist project path",  completion: .directory) var projectPath: String?
    @Option(help: "project name") var projectName: String?


    func run() {

        do {
            var projectPath = projectPath
            var projectName = projectName
            if projectPath == nil {
                projectPath = fileManager.currentDirectoryPath
            } else if projectPath!.hasPrefix("/") {
                // absolute path
            } else {
                projectPath = fileManager.currentDirectoryPath + "/" + projectPath!
            }

            print("project root", projectPath)

            if projectName == nil {
                projectName = URL(fileURLWithPath: projectPath!).projectName
            }

            guard let projectName else {
                print("no .xcodeproj file in \(projectPath)")
                throw Error.missingProjectName
            }

            print("found project: \(projectName)")

            let generator = PackageSwiftGenerator()
            try generator.run(tuistRoot: projectPath!, projectName: projectName)

        } catch {

            print("Whoops! An error occurred: \(error)")
        }

    }
}

public struct PackageSwiftGenerator {

    private func libraryTargets(_ project: Project) -> [DTarget] {
        let targets: [ATarget] = project.targets
        let libraryTargets: [DTarget] = targets
            .filter { target in
                target.product == "staticFramework"
            }.map { (target: ATarget) -> DTarget in

                let dependencies: [DTarget.Dependency] = target.dependencies.compactMap(\.dtDependency)
                guard let path = target.sources.commonFolder(relativeTo: URL(fileURLWithPath: project.path)) else {
                    fatalError("no source folder for \(target.name) file:\(target.sources.first)")
                }

                let sourcePath = URL(fileURLWithPath: path)
                return DTarget.target(name: target.name,
                                      dependencies: dependencies,
                                      path: path,
                                      resources: target.resources.map { path -> Resource in
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
                                      })
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
    }

    private func packageFieldsFilter(package _: DPackage, fields: Fields) -> Fields {
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

    public func run(tuistRoot: String, projectName: String) throws {
        // .macOS("15.0"),
        let supportedPlatform = """
        .iOS("13.0"), .macOS("15.0")
        """


        let graph = try Tuist.graph(at: tuistRoot)

        guard let project = graph.projects.values.filter({ $0.name == projectName }).first else {
            print("no project found, available projects: \(graph.projects.values.map(\.name))")
            return
        }

        let package = projectToPackage(project)
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

            if original.contains("_platforms:") {
                // if we compile this plugin into binary file
                // `_platforms:` will show up instead of `platforms:`
                // I don't know why
                return original.replacing("_platforms:", with: "platforms:")
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

            var lines = original.split(separator: "\n")
            // monkey patch
            if lines.first == "Target(" {
                lines[0] = ".target("
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
