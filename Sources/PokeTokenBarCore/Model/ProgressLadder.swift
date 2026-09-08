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
        let kantoOpen = wonLeagues.contains("johto")
        let champion = wonLeagues.contains("kanto")

        // Antes de la puerta solo cabe lo que se consigue con 8 medallas o
        // menos y sin Kanto. Ojo: hay hitos en zonas de Johto que piden 10
        // medallas (Ho-Oh, Lugia), y esas medallas solo llegan tras la puerta,
        // así que van en el tramo de después aunque su región sea Johto.
        for count in 0...8 {
            let opened = unlocks(atMedals: count, needsKanto: false)
            guard !opened.isEmpty else { continue }
            steps.append(LadderStep(requirement: .medals(count), unlocks: opened, reached: medals >= count))
        }

        if let johto = leagues["johto"] {
            let kantoZones = zones.all
                .filter { $0.unlock.requiresKanto && !$0.unlock.requiresChampion && $0.unlock.requiredMedals == 0 }
                .map { "Zona: \($0.name) · \($0.species.count) especies" }
            steps.append(
                LadderStep(
                    requirement: .league(id: johto.id, name: johto.name),
                    unlocks: ["Los 8 gimnasios de Kanto"] + kantoZones,
                    reached: kantoOpen
                )
            )
        }

        for count in 9...16 {
            let opened = unlocks(atMedals: count, needsKanto: true)
            guard !opened.isEmpty else { continue }
            steps.append(
                LadderStep(
                    requirement: .medals(count),
                    unlocks: opened,
                    reached: kantoOpen && medals >= count
                )
            )
        }

        if let kanto = leagues["kanto"] {
            var opened = ["Título de Campeón"]
            opened += zones.all.filter { $0.unlock.requiresChampion }.map { "Zona: \($0.name)" }
            opened += milestones.all
                .filter { zones[$0.zoneID]?.unlock.requiresChampion == true }
                .compactMap { pokedex[$0.speciesID]?.localizedName }
                .map { "Legendario: \($0)" }
            steps.append(
                LadderStep(
                    requirement: .league(id: kanto.id, name: kanto.name),
                    unlocks: opened,
                    reached: champion
                )
            )
        }

        return steps
    }

    /// Qué abre alcanzar esas medallas. `needsKanto` separa los dos tramos: lo
    /// de antes de la puerta y lo de después.
    private func unlocks(atMedals count: Int, needsKanto: Bool) -> [String] {
        var opened: [String] = []

        if let gym = gyms.all.first(where: { $0.order == count + 1 }),
           (gym.region == "kanto") == needsKanto {
            opened.append("Gimnasio: \(gym.leader) (\(gym.city))")
        }

        opened += zones.all
            .filter { zone in
                !zone.unlock.requiresChampion
                    && zone.unlock.requiredMedals == count
                    && zone.unlock.requiresKanto == needsKanto
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
                // Cae en el tramo de después si pide Kanto o más de 8 medallas,
                // que en la práctica es lo mismo.
                let afterGate = zone.unlock.requiresKanto || needed > 8
                return needed == count && afterGate == needsKanto
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
