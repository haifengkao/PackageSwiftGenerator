func main() {
    do {
        let tool = PackageSwiftGenerator()
        try tool.run()
    } catch {
        print("Whoops! An error occurred: \(error)")
    }
}

main()
