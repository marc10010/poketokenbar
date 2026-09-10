import CoreGraphics
import Foundation
import PokeTokenBarCore

/// Las medidas son las de un portátil con un monitor encima y a la izquierda,
/// que es donde salió el fallo: arrastrar el HUD fuera de la principal era
/// imposible.
@MainActor
enum HUDPlacementTests: TestSuite {
    static let suiteName = "HUDPlacement"

    static let tests: [(String, () throws -> Void)] = [
        ("una posición del todo dentro se respeta", testInsideIsUntouched),
        ("pisando las dos pantallas no vuelve a la principal", testStraddlingKeepsGoing),
        ("cruzar entero al segundo monitor se queda", testSecondScreenIsAllowed),
        ("el barrido de un borde al otro no da ningún salto", testDragAcrossNeverJumps),
        ("bajo la barra de menú no la reencuadra", testMenuBarStripIsRespected),
        ("si casi no se ve, vuelve a lo visible", testSliverIsRescued),
        ("sin pantalla que la aguante, no hay sitio", testOffAllScreens),
        ("sin pantallas devuelve nil", testNoScreens),
    ]

    private static let laptop = HUDPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visible: CGRect(x: 0, y: 0, width: 1512, height: 950)
    )
    private static let external = HUDPlacement.Screen(
        frame: CGRect(x: -501, y: 982, width: 2560, height: 1440),
        visible: CGRect(x: -501, y: 982, width: 2560, height: 1440)
    )
    private static let screens = [laptop, external]
    private static let size = CGSize(width: 268, height: 104)

    private static func hud(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    static func testInsideIsUntouched() {
        let candidate = hud(400, 300)
        expectEqual(HUDPlacement.free(candidate, screens: screens), candidate)
    }

    static func testStraddlingKeepsGoing() {
        // Mitad en el portátil y mitad en el monitor: es el instante que hacía
        // saltar la ventana de vuelta.
        let candidate = hud(300, 930)
        expectEqual(HUDPlacement.free(candidate, screens: screens), candidate)
    }

    static func testSecondScreenIsAllowed() {
        let candidate = hud(-495, 2301)
        expectEqual(HUDPlacement.free(candidate, screens: screens), candidate)
        // Y también en la parte del monitor que cae a la izquierda del
        // portátil, que en coordenadas es x negativa.
        let leftOfLaptop = hud(-480, 1200)
        expectEqual(HUDPlacement.free(leftOfLaptop, screens: screens), leftOfLaptop)
    }

    static func testDragAcrossNeverJumps() {
        // Subiendo de 20 en 20 desde el portátil hasta bien dentro del
        // monitor, ni un solo paso puede moverse a otro sitio: un salto en
        // mitad del arrastre es justo el fallo.
        for y in stride(from: CGFloat(0), through: 1400, by: 20) {
            let candidate = hud(300, y)
            expectEqual(HUDPlacement.free(candidate, screens: screens), candidate, "en y=\(Int(y))")
        }
    }

    static func testMenuBarStripIsRespected() {
        // Entre 950 y 982 está la barra de menú del portátil: fuera de
        // `visibleFrame` pero dentro de la pantalla. Dejarla ahí es una
        // decisión de quien arrastra, no un despiste que corregir.
        let candidate = hud(600, 960)
        expectEqual(HUDPlacement.free(candidate, screens: screens), candidate)
    }

    static func testSliverIsRescued() throws {
        // Arrastrada casi del todo fuera por abajo: quedan 10 pt a la vista y
        // con eso no se agarra.
        let rescued = try unwrap(HUDPlacement.free(hud(400, -94), screens: screens))
        expectTrue(laptop.visible.contains(rescued), "vuelve a lo visible del portátil")
        expectEqual(rescued.size, size, "rescatar no cambia el tamaño")
    }

    static func testOffAllScreens() {
        // El monitor que la tenía, desconectado: su sitio ya no existe.
        expectNil(HUDPlacement.free(hud(-495, 2301), screens: [laptop]))
    }

    static func testNoScreens() {
        expectNil(HUDPlacement.free(hud(0, 0), screens: []))
    }
}
