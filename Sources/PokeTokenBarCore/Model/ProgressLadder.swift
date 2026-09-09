import Foundation

/// Un escalón de la progresión: qué hace falta y qué abre.
public struct LadderStep: Identifiable, Hashable, Sendable {
    public enum Requirement: Hashable, Sendable {
        case medals(Int)
        case league(id: String, name: String)

        public var label: String {
            switch self {
            case .medals(0): return "Desde el principio"
            case .medals(let count): return "\(count) medalla\(count == 1 ? "" : "s")"
            case .league(_, let name): return "Ganar \(name)"
            }
        }
    }

    public let requirement: Requirement
    public let unlocks: [String]
    public let reached: Bool

    public var id: String {
        switch requirement {
        case .medals(let count): return "medals-\(count)"
        case .league(let id, _): return "league-\(id)"
        }
    }
}

/// Construye la escalera de desbloqueo a partir de los catálogos, para que la
/// progresión se vea en un sitio en vez de repartida entre cuatro secciones.
///
/// Se deriva de los datos y no se escribe a mano: si mañana una zona cambia de
/// requisito, la escalera cambia con ella.
public struct ProgressLadder {
    private let zones: ZoneCatalog
    private let gyms: GymCatalog
    private let milestones: MilestoneCatalog
    private let leagues: LeagueCatalog
    private let pokedex: Pokedex

    public init(
        zones: ZoneCatalog = .shared,
        gyms: GymCatalog = .shared,
        milestones: MilestoneCatalog = .shared,
        leagues: LeagueCatalog = .shared,
        pokedex: Pokedex = .shared
    ) {
        self.zones = zones
        self.gyms = gyms
        self.milestones = milestones
        self.leagues = leagues
        self.pokedex = pokedex
    }

    public func steps(medals: Int, wonLeagues: Set<String>) -> [LadderStep] {
        var steps: [LadderStep] = []
        // Las regiones salen del orden de los gimnasios, no de sus nombres:
        // esta escalera tenía "kanto" escrito en seis sitios y se rompió al
        // invertir el orden de juego.
        let regions = gyms.regions
        let second = regions.count > 1 ? regions[1] : nil
        let gate = second.flatMap { region in leagues.all.first { $0.reward.opensRegion == region } }
        let final = leagues.all.first { $0.reward == .champion }
        let secondOpen = gate.map { wonLeagues.contains($0.id) } ?? true
        let champion = final.map { wonLeagues.contains($0.id) } ?? false

        // Antes de la puerta solo cabe lo que se consigue con 8 medallas o
        // menos y sin la segunda región. Ojo: hay hitos en zonas de la segunda
        // región que piden más de 8 medallas, y esas medallas solo llegan tras
        // la puerta, así que van en el tramo de después.
        for count in 0...8 {
            let opened = unlocks(atMedals: count, second: second, afterGate: false)
            guard !opened.isEmpty else { continue }
            steps.append(LadderStep(requirement: .medals(count), unlocks: opened, reached: medals >= count))
        }

        if let gate, let second {
            let zonesOfSecond = zones.all
                .filter { $0.unlock.requiredRegion == second && !$0.unlock.requiresChampion && $0.unlock.requiredMedals == 0 }
                .map { "Zona: \($0.name) · \($0.species.count) especies" }
            steps.append(
                LadderStep(
                    requirement: .league(id: gate.id, name: gate.name),
                    unlocks: ["Los 8 gimnasios de \(second.capitalized)"] + zonesOfSecond,
                    reached: secondOpen
                )
            )
        }

        for count in 9...16 {
            let opened = unlocks(atMedals: count, second: second, afterGate: true)
            guard !opened.isEmpty else { continue }
            steps.append(
                LadderStep(
                    requirement: .medals(count),
                    unlocks: opened,
                    reached: secondOpen && medals >= count
                )
            )
        }

        if let final {
            var opened = ["Título de Campeón"]
            opened += zones.all.filter { $0.unlock.requiresChampion }.map { "Zona: \($0.name)" }
            opened += milestones.all
                .filter { zones[$0.zoneID]?.unlock.requiresChampion == true }
                .compactMap { pokedex[$0.speciesID]?.localizedName }
                .map { "Legendario: \($0)" }
            steps.append(
                LadderStep(
                    requirement: .league(id: final.id, name: final.name),
                    unlocks: opened,
                    reached: champion
                )
            )
        }

        return steps
    }

    /// Qué abre alcanzar esas medallas. `afterGate` separa los dos tramos: lo
    /// de antes de la puerta entre regiones y lo de después.
    private func unlocks(atMedals count: Int, second: String?, afterGate: Bool) -> [String] {
        var opened: [String] = []

        if let gym = gyms.all.first(where: { $0.order == count + 1 }),
           (gym.region == second) == afterGate {
            opened.append("Gimnasio: \(gym.leader) (\(gym.city))")
        }

        opened += zones.all
            .filter { zone in
                !zone.unlock.requiresChampion
                    && zone.unlock.requiredMedals == count
                    && (zone.unlock.requiredRegion == second) == afterGate
                    && count > 0
            }
            .map { "Zona: \($0.name) · \($0.species.count) especies" }

        opened += milestones.all
            .filter { milestone in
                guard milestone.requiredSpecies == nil,
                      let zone = zones[milestone.zoneID],
                      !zone.unlock.requiresChampion
                else { return false }
                let needed = max(zone.unlock.requiredMedals, milestone.extraMedals)
                // Cae en el tramo de después si pide la segunda región o más de
                // 8 medallas, que en la práctica es lo mismo.
                let after = zone.unlock.requiredRegion == second || needed > 8
                return needed == count && after == afterGate
            }
            .compactMap { pokedex[$0.speciesID].map { "Legendario: \($0.localizedName)" } }

        opened += Rarity.allCases
            .filter { $0.spawnsInTheWild && $0.requiredRank.requiredMedals == count && count > 0 }
            .map { "Aparecen los \($0.label.lowercased())s" }

        if let league = leagues.all.first(where: { $0.requiredMedals == count }), count > 0 {
            opened.append("Se puede retar: \(league.name)")
        }

        return opened
    }
}
