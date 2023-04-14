# PackageSwiftGenerator
Generate `Pacakge.swift` from [Tuist](https://github.com/tuist/tuist) configuration.
## Prerequisite
Please make sure Xcode is installed. PackageSwiftGenerator needs `libPackageDescription.dylib` in XcodeDefault.xctoolchain.

## Install

1. create your first project by `tuist init --platform ios`
2. open `Tuist/Config.swift`, change it to
```swift
import ProjectDescription

let config = Config(
    plugins: [
        .git(url: "https://github.com/haifengkao/PackageSwiftGenerator", tag: "0.7.0")
    ]
)
```
3. run `tuist fetch` in terminal to download `PackageSwiftGenerator`

4. run `tuist generate-package-swift` to generate `Package.swift`

## Contribute

To start working on the project, you can follow the steps below:
1. Clone the project.
2. `cd fixtures/Example1`
3. `tuist fetch` to install the plugin
4. `tuist plugin run tuist-generate-package-swift` to generate `Package.swift`
5. `rm Package.swift` before re-run `tuist plugin run tuist-generate-package-swift` to avoid tuist-generate-package-swift not found error  
