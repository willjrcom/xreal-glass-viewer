import Combine
import PrismaXRRenderer
import ScreenCaptureKit

@available(macOS 12.3, *)
final class LayoutViewModel: ObservableObject {
    @Published var desks: [DeskLayoutConfiguration] {
        didSet { onChange(desks) }
    }

    @Published var availableWindows: [SCWindow] = []
    @Published var availableDisplays: [SCDisplay] = []
    @Published var screenCount: Int = 3 {
        didSet { applyScreenCount() }
    }
    
    var onChange: ([DeskLayoutConfiguration]) -> Void = { _ in }
    var onWindowSelect: (Int, SCWindow) -> Void = { _, _ in }
    var onDisplaySelect: (Int, SCDisplay) -> Void = { _, _ in }
    var onPanorama: (() -> Void)?
    var onCycleScreens: (() -> Void)?
    var onRecenter: (() -> Void)?
    var onScreenCountChanged: ((Int) -> Void)?

    init(initialDesks: [DeskLayoutConfiguration] = Renderer.defaultLayouts()) {
        self.desks = initialDesks
    }
    
    public func triggerRecenter() {
        onRecenter?()
    }
    
    private func applyScreenCount() {
        let allLayouts: [DeskLayoutConfiguration] = .defaultDeskLayouts()
        switch screenCount {
        case 1:
            desks = [allLayouts[1]] // Mesa central
        case 2:
            desks = [allLayouts[0], allLayouts[1]] // Esquerda + centro
        default:
            desks = allLayouts // Todas
        }
        onScreenCountChanged?(screenCount)
    }

    func updateAvailableWindows(_ windows: [SCWindow]) {
        self.availableWindows = windows
    }

    func updateAvailableDisplays(_ displays: [SCDisplay]) {
        self.availableDisplays = displays
    }

    func selectWindow(index: Int, window: SCWindow) {
        guard index >= 0 && index < desks.count else { return }
        desks[index].windowID = window.windowID
        desks[index].displayID = nil
        onWindowSelect(index, window)
    }

    func selectDisplay(index: Int, display: SCDisplay) {
        guard index >= 0 && index < desks.count else { return }
        desks[index].windowID = nil
        desks[index].displayID = display.displayID
        onDisplaySelect(index, display)
    }

    func triggerPanorama() {
        onPanorama?()
    }

    func resetPreset(_ preset: Preset) {
        switch preset {
        case .focus:
            desks = [
                DeskLayoutConfiguration(name: "Principal", horizontalOffset: 0, radius: 1.8),
                DeskLayoutConfiguration(name: "Aux 1", horizontalOffset: -1.4, radius: 2.1),
                DeskLayoutConfiguration(name: "Aux 2", horizontalOffset: 1.4, radius: 2.1)
            ]
        case .research:
            desks = [
                DeskLayoutConfiguration(name: "Pesquisa", horizontalOffset: -1.6, radius: 2.3),
                DeskLayoutConfiguration(name: "Docs", horizontalOffset: 0, radius: 2.5),
                DeskLayoutConfiguration(name: "Comms", horizontalOffset: 1.6, radius: 2.3)
            ]
        case .presentation:
            desks = [
                DeskLayoutConfiguration(name: "Apresentação", horizontalOffset: 0, radius: 2.0),
                DeskLayoutConfiguration(name: "Notas", horizontalOffset: -1.7, radius: 2.2),
                DeskLayoutConfiguration(name: "Chat", horizontalOffset: 1.7, radius: 2.2)
            ]
        }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case focus = "Foco"
        case research = "Pesquisa"
        case presentation = "Apresentação"

        var id: String { rawValue }
    }
}
