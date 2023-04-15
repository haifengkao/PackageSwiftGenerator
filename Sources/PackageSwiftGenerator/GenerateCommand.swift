//
// Created by Hai Feng Kao on 2023/4/15.
//

import ArgumentParser
import Foundation

struct GenerateCommand: ParsableCommand {
    @Option(help: "tuist project path", completion: .directory) var projectPath: String?
    @Option(help: "project name") var projectName: String?
    @Argument(help: "the target names, if not provided, all targets will be included") var targetNames: [String]

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

            if !targetNames.isEmpty {
                print("target names: \(targetNames)")
            }

            let generator = PackageSwiftGenerator()
            try generator.run(tuistRoot: projectPath!, projectName: projectName, targetNames: targetNames)

        } catch {
            print("Whoops! An error occurred: \(error)")
        }
    }
}
