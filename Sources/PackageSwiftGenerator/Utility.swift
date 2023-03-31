//
// Created by Lono on 2023/3/28.
//

import Foundation
import PackageDescription
import ProjectAutomation
extension URL {
    func fileURL(endsWith suffix: String) -> URL? {
        let directory = isFileURL ? deletingLastPathComponent() : self
        let fileURLs = try! fileManager.contentsOfDirectory(at: self, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        let fileURL = fileURLs.filter {
            $0.lastPathComponent.contains(suffix)
        }
        .filter { url in

            if url.lastPathComponent.contains("Manifests.") {
                return false
            }

            if url.lastPathComponent.contains("Plugin.") {
                return false
            }

            return true

        }.first
        return fileURL
    }

    var xcodeprojURL: URL? {
        fileURL(endsWith: ".xcodeproj")
    }

    var projectName: String? {
        xcodeprojURL?.deletingPathExtension().lastPathComponent
    }
}

extension URL {
    var hasPackageDotSwift: Bool {
        let packageDotSwift = appendingPathComponent("Package.swift")
        return fileManager.fileExists(atPath: packageDotSwift.path)
    }

    var swiftPackageRootFolder: URL? {
        if hasPackageDotSwift {
            return self
        } else if lastPathComponent.contains(spmBuildFolder) {
            // no package.swift found
            return nil
        } else {
            return deletingLastPathComponent().swiftPackageRootFolder
        }
    }
}

extension String {
    var swiftPackageRootFolder: URL? {
        let url = URL(fileURLWithPath: self)
        return url.swiftPackageRootFolder
    }
}

extension ATarget {
    var isSwiftPackage: Bool {
        sources.first?.contains(spmCheckOutFolder) ?? false
    }
}

extension TargetDependency {
    var dtDependency: DTarget.Dependency {
        switch self {
        case let .target(name):
            return .target(name: name)
        case let .project(name, path: _):
            return .target(name: name)
        default:
            fatalError("not implemented: \(self)")
        }
    }
}
