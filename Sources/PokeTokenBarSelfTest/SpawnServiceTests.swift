import Foundation
import PokeTokenBarCore

@MainActor
enum SpawnServiceTests: TestSuite {
    static let suiteName = "SpawnService"

    static let tests: [(String, () throws -> Void)] = [
        ("el gate es el rango, no los tokens", testTierGatesByRank),
        ("los tiers bloqueados no salen", testGatedTiersNeverSpawn),
        ("dentro de la zona los pesos son 45/33/22", testWeightsInsideTheZone),
        ("una zona sin raros reparte su peso entre los demás", testMissingTierRedistributes),
        ("el HP es el de la zona, no el del tier", testHPComesFromTheZone),
        ("solo sale lo que vive en la zona", testOnlyWhatLivesHere),
        ("ninguna zona se queda sin candidatas", testEveryZoneCanSpawn),
        ("shiny rate is about one percent", testShinyRateIsAboutOnePercent),
    ]

    private static let spawner = SpawnService()
    private static let zones = ZoneCatalog.shared

    private static func zone(_ id: String) -> Zone {
        guard let zone = zones[id] else { fatalError("falta la zona \(id)") }
        return zone
    }

    /// Ruta grande de la primera región: tiene los tres tiers, que es lo que
    /// hace falta para leer los pesos.
    private static let ruta = zone("rutas-kanto-sur")
    /// Una cueva de una sola especie: el caso extremo del bombo pequeño.
    private static let cueva = zone("cueva-diglett")

    static func testTierGatesByRank() {
        expectEqual(spawner.availableTiers(rank: .novato, in: ruta), [.common, .uncommon])
        expectEqual(spawner.availableTiers(rank: .entrenador, in: ruta), [.common, .uncommon, .rare])
        // Ni con el rango máximo aparece el tier legendario: son hitos.
        expectEqual(spawner.availableTiers(rank: .campeon, in: ruta), [.common, .uncommon, .rare])
        // Y una zona solo ofrece los tiers que tiene.
        expectEqual(spawner.availableTiers(rank: .campeon, in: cueva), [.common])
    }

    static func testGatedTiersNeverSpawn() {
        var rng = SeededRandomProvider(seed: 99)
        for _ in 0..<3_000 {
            let encounter = spawner.spawn(zone: ruta, rank: .novato, using: &rng)
            expectTrue([.common, .uncommon].contains(encounter.rarity))
        }
    }

    /// La rareza dejó de ser HP y pasó a ser probabilidad, así que los pesos
    /// son lo único que la hace notar. Más planos que el 60/28/10 de cuando el
    /// bombo era global: con la zona como único bombo, un sesgo fuerte hace
    /// eternas las cacerías concretas.
    static func testWeightsInsideTheZone() {
        var rng = SeededRandomProvider(seed: 4242)
        var counts: [Rarity: Int] = [:]
        let samples = 200_000
        for _ in 0..<samples {
            counts[spawner.rollTier(rank: .campeon, in: ruta, using: &rng) ?? .legendary, default: 0] += 1
        }

        expectEqual(counts[.legendary] ?? 0, 0, "un legendario no puede aparecer de rival salvaje")
        for (rarity, expected) in [(Rarity.common, 0.45), (.uncommon, 0.33), (.rare, 0.22)] {
            let observed = Double(counts[rarity] ?? 0) / Double(samples)
            expectEqual(observed, expected, accuracy: 0.01, "\(rarity)")
        }
    }

    static func testMissingTierRedistributes() throws {
        // Bosque Verde no tiene raros: su 22 % se reparte entre común y poco
        // común en proporción, no se sortea en vacío.
        let bosque = zone("bosque-verde")
        let present = Set(spawner.pool(bosque).map(\.rarity))
        expectFalse(present.contains(.rare), "el test necesita una zona sin raros")

        var rng = SeededRandomProvider(seed: 77)
        var counts: [Rarity: Int] = [:]
        let samples = 100_000
        for _ in 0..<samples {
            counts[try unwrap(spawner.rollTier(rank: .campeon, in: bosque, using: &rng)), default: 0] += 1
        }
        let total = present.reduce(0.0) { $0 + $1.spawnWeight }
        for rarity in present {
            let observed = Double(counts[rarity] ?? 0) / Double(samples)
            expectEqual(observed, rarity.spawnWeight / total, accuracy: 0.01, "\(rarity)")
        }
    }

    /// Dentro de una zona todos aguantan lo mismo: un raro sale menos, no pesa
    /// más. Y entre zonas la vida sube con la profundidad.
    static func testHPComesFromTheZone() {
        var rng = SeededRandomProvider(seed: 7)
        for _ in 0..<2_000 {
            let encounter = spawner.spawn(zone: ruta, rank: .campeon, using: &rng)
            expectEqual(encounter.maxHP, zones.hp(of: ruta), "\(encounter.rarity) con HP de tier")
            expectEqual(encounter.currentHP, encounter.maxHP)
        }
        expectEqual(zones.hp(of: ruta), Int(GameRules.zoneBaseHP), "la primera zona es la base")

        let ordenadas = zones.inUnlockOrder
        for (shallow, deep) in zip(ordenadas, ordenadas.dropFirst()) {
            expectGreaterThan(
                zones.hp(of: deep),
                zones.hp(of: shallow),
                "\(deep.name) debería pesar más que \(shallow.name)"
            )
        }
        let ultima = try? unwrap(ordenadas.last)
        if let ultima {
            let ratio = Double(zones.hp(of: ultima)) / GameRules.zoneBaseHP
            expectEqual(ratio, 6, accuracy: 0.35, "de punta a punta la curva multiplica por seis")
        }
    }

    static func testOnlyWhatLivesHere() {
        var rng = SeededRandomProvider(seed: 5)
        for zone in [ruta, cueva, self.zone("monte-moon")] {
            let vive = Set(spawner.pool(zone).map(\.id))
            for _ in 0..<1_000 {
                let encounter = spawner.spawn(zone: zone, rank: .campeon, using: &rng)
                expectTrue(vive.contains(encounter.speciesID), "#\(encounter.speciesID) no vive en \(zone.name)")
            }
        }
    }

    /// El invariante del que depende que la zona pueda ser el único bombo.
    static func testEveryZoneCanSpawn() {
        for zone in zones.all {
            expectGreaterThan(spawner.pool(zone).count, 0, "\(zone.name) no puede dar ningún rival")
        }
    }

    static func testShinyRateIsAboutOnePercent() {
        var rng = SeededRandomProvider(seed: 1234)
        var shinies = 0
        let samples = 100_000
        for _ in 0..<samples where spawner.spawn(zone: ruta, rank: .campeon, using: &rng).isShiny {
            shinies += 1
        }
        expectEqual(Double(shinies) / Double(samples), 0.01, accuracy: 0.002)
    }
}
