import AppKit

@main
struct PokeTokenBarApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--render-ui"),
           let path = CommandLine.arguments.dropFirst(index + 1).first {
            application.setActivationPolicy(.prohibited)
            exit(UIRender.run(into: URL(fileURLWithPath: path)))
        }
        if CommandLine.arguments.contains("--ui-smoke-test") {
            application.setActivationPolicy(.prohibited)
            exit(UISmokeTest.run())
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        // .accessory: sin icono en el Dock ni menú propio, solo barra de estado.
        application.setActivationPolicy(.accessory)
        application.run()
        // `run()` retiene el delegate a través de NSApp; esta referencia evita
        // que el optimizador lo libere antes de arrancar el run loop.
        _ = delegate
    }
}
