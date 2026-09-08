import Foundation

@main
struct SelfTestRunner {
    @MainActor
    static func main() {
        let suites: [any TestSuite.Type] = [
            PokedexTests.self,
            SpawnServiceTests.self,
            BattleEngineTests.self,
            EvolutionServiceTests.self,
            BoxGroupTests.self,
            BoxFilterTests.self,
            TypeChartTests.self,
            GameStoreTests.self,
            IngestTests.self,
        ]

        var executed = 0
        for suite in suites {
            print("\n▸ \(suite.suiteName)")
            for (name, body) in suite.tests {
                let before = Report.failures.count
                do {
                    try body()
                } catch {
                    Report.failures.append("\(suite.suiteName)/\(name) lanzó \(error)")
                }
                executed += 1
                let failed = Report.failures.count - before
                print("  \(failed == 0 ? "✓" : "✗") \(name)")
            }
        }

        TemporaryFiles.cleanUp()
        print("\n\(executed) tests · \(Report.checks) comprobaciones · \(Report.failures.count) fallos")
        if !Report.failures.isEmpty {
            print("\nFallos:")
            for failure in Report.failures { print("  • \(failure)") }
            exit(1)
        }
    }
}
