import Foundation
import PokeTokenBarCore

/// Arnés de test mínimo. Existe porque la máquina objetivo puede tener solo las
/// Command Line Tools, donde no hay XCTest ni swift-testing: así
/// `swift run PokeTokenBarSelfTest` verifica el motor sin Xcode instalado.
@MainActor
protocol TestSuite {
    static var suiteName: String { get }
    static var tests: [(String, () throws -> Void)] { get }
}

@MainActor
enum Report {
    static var checks = 0
    static var failures: [String] = []

    static func fail(_ message: String, _ file: StaticString, _ line: UInt) {
        let name = URL(fileURLWithPath: "\(file)").lastPathComponent
        failures.append("\(name):\(line) — \(message)")
    }
}

struct UnwrapError: Error, CustomStringConvertible {
    let description = "se esperaba un valor no nulo"
}

@MainActor
func unwrap<T>(_ value: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws -> T {
    Report.checks += 1
    guard let value else {
        Report.fail("unwrap nil \(message)", file, line)
        throw UnwrapError()
    }
    return value
}

@MainActor
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    Report.checks += 1
    if actual != expected {
        Report.fail("se esperaba \(expected), llegó \(actual). \(message)", file, line)
    }
}

@MainActor
func expectEqual(_ actual: Double, _ expected: Double, accuracy: Double, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    Report.checks += 1
    if abs(actual - expected) > accuracy {
        Report.fail("se esperaba \(expected) ±\(accuracy), llegó \(actual). \(message)", file, line)
    }
}

@MainActor
func expectTrue(_ value: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    Report.checks += 1
    if !value { Report.fail("se esperaba true. \(message)", file, line) }
}

@MainActor
func expectFalse(_ value: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    Report.checks += 1
    if value { Report.fail("se esperaba false. \(message)", file, line) }
}

@MainActor
func expectNil<T>(_ value: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    Report.checks += 1
    if let value { Report.fail("se esperaba nil, llegó \(value). \(message)", file, line) }
}

@MainActor
func expectNotNil<T>(_ value: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    Report.checks += 1
    if value == nil { Report.fail("se esperaba no-nil. \(message)", file, line) }
}

@MainActor
func expectGreaterThan<T: Comparable>(_ actual: T, _ bound: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    Report.checks += 1
    if !(actual > bound) { Report.fail("se esperaba > \(bound), llegó \(actual). \(message)", file, line) }
}

@MainActor
enum TemporaryFiles {
    static let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("poketokenbar-selftest/\(UUID().uuidString)")

    static func uniqueDirectory() -> URL {
        let url = root.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

extension CapturedPokemon {
    /// Copia con otro progreso, para probar etapas sin recrear el ejemplar.
    func earning(_ tokens: Int) -> CapturedPokemon {
        var copy = self
        copy.tokensEarned = tokens
        return copy
    }

    /// Deja el ejemplar evolucionado a esas formas, en orden. Desde que la
    /// evolución es un hecho registrado y no una cuenta de tokens, un fixture
    /// que quiera un Wartortle tiene que decirlo, no acumular 300k.
    func evolved(to forms: Int...) -> CapturedPokemon {
        evolvedTo(forms)
    }

    func evolvedTo(_ forms: [Int]) -> CapturedPokemon {
        var copy = self
        copy.evolvedForms.append(contentsOf: forms)
        return copy
    }
}
