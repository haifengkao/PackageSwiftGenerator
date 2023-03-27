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

        // don't print nil properties
        if line.contains(": nil") {
            return
        }

        if line.contains("type: .regular,") {
            return
        }

        logged += line + "\n"
    }
}

public struct PackageSwiftGenerator {
    private let arguments: [String]

    public init(arguments: [String] = CommandLine.arguments) {
        self.arguments = arguments
    }

    private func libraryTargets(_ project: Project) -> [DTarget] {
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

                return DTarget.target(name: target.name,
                                      dependencies: dependencies,
                                      sources: target.sources,
                                      resources: target.resources.map(\.processResource))
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

        print(logger.logged)
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
