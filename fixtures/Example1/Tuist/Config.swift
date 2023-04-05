import ProjectDescription

let config = Config(
    plugins: [
        .git(url: "https://github.com/haifengkao/SwiftUITemplate", tag: "2.3.0"),
        // .git(url: "https://github.com/haifengkao/PackageSwiftGenerator", tag: "0.3.0"),
        .local(path: "../../../../"),
    ]
)
