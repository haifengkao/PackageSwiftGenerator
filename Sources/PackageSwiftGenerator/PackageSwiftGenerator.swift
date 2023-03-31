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
                if otherPathComponents.count > index,
                   otherPathComponents[index] == path
                {
                    result.append(path)
                }
            }

        let relativePath: [String] = Array(pathComponents
            .dropFirst(commonPath.count))

        return relativePath.joined(separator: "/")
    }
}

public struct PackageSwiftGenerator {
    private let arguments: [String]

    public init(arguments: [String] = CommandLine.arguments) {
        self.arguments = arguments
    }

    private func libraryTargets(_ project: Project) -> [DTarget] {
        let projectRoot = URL(filePath: project.path)
        let targets: [ATarget] = project.targets
        let libraryTargets: [DTarget] = targets
            .filter { target in
                // exclude swift packages from github
                !target.isSwiftPackage
            }
            .filter { target in
                target.product == "staticFramework"
            }.map { (target: ATarget) -> DTarget in

                let dependencies: [DTarget.Dependency] = target.dependencies.map(\.dtDependency)
                guard let path = target.sources.commonFolder(relativeTo: URL(fileURLWithPath: project.path)) else {
                    fatalError("no source folder for \(target.name) file:\(target.sources.first)")
                }

                return DTarget.target(name: target.name,
                                      dependencies: dependencies,
                                      path: path,
                                      resources: target.resources.map { path -> Resource in
                                          let url: URL = .init(filePath: path)
                                          let relativePath: String = url.relative(to: projectRoot)
                                          return Resource.process(relativePath)
                                      })
            }
        return libraryTargets
    }

    private func swiftPackages(_ project: Project) -> [DPackage.Dependency] {
        let targets = project.targets
        let swiftPackages: [DPackage.Dependency] = targets.filter { target in
            target.isSwiftPackage
        }
        .compactMap { target in
            target.sources.first?.swiftPackageRootFolder
        }.map {
            .package(path: $0.path)
        }
        return swiftPackages
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

        if let dep = fields.filter { $0.0 == "dependencies" }.first {
            rest.insert(dep, at: 1)
        }

        if let dep = fields.filter { $0.0 == "path" }.first {
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

        if let dep = fields.filter { $0.0 == "products" }.first {
            rest.insert(dep, at: 2)
        }
        if let dep = fields.filter { $0.0 == "dependencies" }.first {
            rest.insert(dep, at: 3)
        }

        return rest
            .filter { $0.1 != "nil" } // remove nil values
    }

    public func run() throws {
        guard arguments.count > 1 else {
            throw Error.missingFileName
        }
        // The first argument is the execution path
        let tuistRoot = arguments[1]

        var projectName: String?

        if arguments.count > 2 {
            projectName = arguments[2]
        } else {
            projectName = URL(fileURLWithPath: tuistRoot).projectName
        }

        guard let projectName else {
            print("no .xcodeproj file in \(URL(fileURLWithPath: tuistRoot))")
            throw Error.missingProjectName
        }

        print("found project: \(projectName)")

        // .macOS("15.0"),
        let supportedPlatform = """
        .iOS("13.0"),
        """

        // do {
        // try Folder.current.createFile(at: fileName)
        print("project root", tuistRoot)

        let graph = try Tuist.graph(at: tuistRoot)

        let targets = graph.projects.values.flatMap(\.targets)
        guard let project = graph.projects.values.filter({ $0.name == projectName }).first else {
            print("no project found, available projects: \(graph.projects.values.map(\.name))")
            return
        }

        let package = projectToPackage(project)
        var logger = UnicodeLogger()

        SimpleDescriber.customEnumFilter = { target, _, originalString in

            if let dep = target as? DTarget.Dependency {
                switch dep {
                case let .targetItem(name, _):
                    return "\"\(name)\""
                case let .byNameItem(name, _):
                    return "\"\(name)\""
                default:
                    fatalError("not implemented \(target)")
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

            if let platform = target as? SupportedPlatform {
                return supportedPlatform
            }

            let fields: Fields = fields
            if let resource = target as? Resource {
                if let path = fields.compactMap { tuple in
                    if tuple.0 == "path" {
                        return tuple.1
                    }
                    return nil
                }.first {
                    return """
                     .process(\(path))
                    """
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
//        print(logger.logged)
    }
}

@available(macOS 13.0, *)
public extension PackageSwiftGenerator {
    enum Error: Swift.Error {
        case missingFileName
        case failedToCreateFile
        case missingProjectName
    }
}

@main
enum Main {
    static func main() {
        do {
            let tool = PackageSwiftGenerator()
            try tool.run()
        } catch {
            print("Whoops! An error occurred: \(error)")
        }
    }
}
