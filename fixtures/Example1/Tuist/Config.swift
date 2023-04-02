import ProjectDescription

let config = Config(
    plugins: [
        .git(url: "https://github.com/haifengkao/SwiftUITemplate", tag: "2.3.0"),
        .git(url: "https://github.com/tuist/ExampleTuistPlugin", tag: "3.1.0"),
        .git(url: "https://github.com/haifengkao/PackageSwiftGenerator", tag: "0.1.0"),
        // .local(path: "../../../../"),
    ]
)
