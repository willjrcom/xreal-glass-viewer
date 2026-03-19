import AppKit
import MetalKit
import ScreenCaptureKit
import SwiftUI
import PrismaXRCapture
import PrismaXRRenderer
import PrismaXRTracking
import PrismaXRLayout
import PrismaXRVirtualDisplay

@available(macOS 12.3, *)
@available(macOS 12.3, *)
@available(macOS 12.3, *)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let window = NSWindow(contentRect: .init(x: 100, y: 100, width: 1280, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered,
                                  defer: false)
    private var renderers: [Renderer] = []
    private var captureServices: [CaptureService] = [CaptureService(), CaptureService(), CaptureService()]
    private let trackingService = HeadTrackingService()
    private var layoutController: LayoutController?
    private var xrWindow: NSWindow?
    private var controlPanel: NSPanel?
    private let layoutViewModel = LayoutViewModel(initialDesks: Renderer.defaultLayouts())
    private let virtualDisplayManager = VirtualDisplayManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        let previewView = MTKView(frame: window.contentView?.bounds ?? .zero)
        previewView.autoresizingMask = [.width, .height]
        window.contentView = previewView
        window.title = "PrismaXR Preview"
        window.makeKeyAndOrderFront(nil)

        guard let previewRenderer = Renderer(mtkView: previewView) else {
            fatalError("Unable to configure Metal renderer")
        }
        renderers.append(previewRenderer)
        
        layoutViewModel.onChange = { [weak self] configs in
            self?.renderers.forEach { $0.updateLayout(configs) }
        }
        
        setupXRWindowIfPossible()
        trackingService.delegate = self
        trackingService.start()
        
        setupInputMonitors()
        
        layoutViewModel.onWindowSelect = { [weak self] index, window in
            self?.captureServices[index].startCapturingWindow(window)
        }
        
        layoutViewModel.onDisplaySelect = { [weak self] index, display in
            self?.captureServices[index].startCapturingDisplay(display)
        }

        captureServices.forEach { $0.delegate = self }
        
        // Virtual displays desabilitados por enquanto (API privada instável)
        // let virtualIDs = virtualDisplayManager.createDisplays(count: 2, width: 1920, height: 1080)
        
        refreshAvailableContent()
        
        showControlPanel()
        
        layoutViewModel.onCycleScreens = { [weak self] in
            self?.cycleScreens()
        }

        layoutViewModel.onRecenter = { [weak self] in
            self?.trackingService.recenter()
            // Resetar também o controle manual por teclado
            self?.currentYaw = 0
            self?.currentPitch = 0
        }
        
        layoutViewModel.onScreenCountChanged = { [weak self] count in
            guard let self = self else { return }
            // Parar capturas das telas que não estão mais ativas
            for i in count..<3 {
                self.captureServices[i].stop()
            }
            // Re-mapear displays para as telas ativas
            self.refreshAvailableContent()
            print("Telas ativas: \(count)")
        }

        NotificationCenter.default.addObserver(self, 
                                               selector: #selector(screensDidChange), 
                                               name: NSApplication.didChangeScreenParametersNotification, 
                                               object: nil)
    }
    
    private func refreshAvailableContent() {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let windows = try await captureServices[0].fetchAvailableWindows()
                let displays = try await captureServices[0].fetchAvailableDisplays()
                
                await MainActor.run {
                    self.layoutViewModel.updateAvailableWindows(windows)
                    self.layoutViewModel.updateAvailableDisplays(displays)
                    
                    // Auto-atribuir se for a primeira vez (vazio)
                    let allEmpty = self.layoutViewModel.desks.allSatisfy { $0.windowID == nil && $0.displayID == nil }
                    if allEmpty {
                        // Filtrar displays XREAL (são saída, não entrada)
                        let captureDisplays = displays.filter { display in
                            let screens = NSScreen.screens
                            let isXR = screens.contains { screen in
                                let name = screen.localizedName.lowercased()
                                return (name.contains("xreal") || name.contains("air") || name.contains("xr")) 
                                       && screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 == display.displayID
                            }
                            return !isXR
                        }
                        
                        guard let mainDisplay = captureDisplays.first ?? displays.first else {
                            print("Nenhum display disponível para captura!")
                            return
                        }
                        
                        print("Auto-mapeando \(self.layoutViewModel.desks.count) mesa(s) para display \(mainDisplay.displayID)")
                        
                        // Cada mesa captura o display principal
                        for i in 0..<self.layoutViewModel.desks.count {
                            self.layoutViewModel.selectDisplay(index: i, display: mainDisplay)
                        }
                    }
                }
            } catch {
                print("Failed to fetch windows/displays: \(error)")
            }
            
            // Auto refresh a cada 10 segundos
            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            self.refreshAvailableContent()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureServices.forEach { $0.stop() }
        trackingService.stop()
        virtualDisplayManager.destroyAll()
        renderers.removeAll()
        xrWindow?.close()
        controlPanel?.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    // Novas propriedades para controle espacial manual
    private var currentYaw: Float = 0
    private var currentPitch: Float = 0
}

@available(macOS 12.3, *)
extension AppDelegate: HeadTrackingServiceDelegate {
    func headTrackingService(_ service: HeadTrackingService, didUpdate pose: HeadPose) {
        // Se o pose for identidade (fallback), permitimos o override manual ou apenas ignoramos
        // No entanto, se o XrealHIDTrackingAdapter estiver ativo, ele enviará poses reais.
        renderers.forEach { $0.updateCameraOrientation(pose.orientation) }
    }
}

@available(macOS 12.3, *)
extension AppDelegate {
    private func setupInputMonitors() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            let step: Float = 0.05
            switch event.keyCode {
            case 123: // Left
                self.currentYaw += step
            case 124: // Right
                self.currentYaw -= step
            case 126: // Up
                self.currentPitch += step
            case 125: // Down
                self.currentPitch -= step
            case 53: // Escape
                if let xr = self.xrWindow {
                    self.renderers.removeAll(where: { $0 === (xr.contentView as? MTKView)?.delegate })
                    xr.close()
                    self.xrWindow = nil
                }
            case 12: // Cmd+Q
                 if event.modifierFlags.contains(.command) { NSApp.terminate(nil) }
            default:
                break
            }
            
            let yawQuat = simd_quatf(angle: self.currentYaw, axis: SIMD3<Float>(0, 1, 0))
            let pitchQuat = simd_quatf(angle: self.currentPitch, axis: SIMD3<Float>(1, 0, 0))
            let combined = yawQuat * pitchQuat
            self.renderers.forEach { $0.updateCameraOrientation(combined) }
            
            return event
        }
    }
}

@available(macOS 12.3, *)
extension AppDelegate: CaptureServiceDelegate {
    func captureService(_ service: CaptureService, didProduce sampleBuffer: CMSampleBuffer) {
        // Roteia baseado em qual serviço produziu o buffer
        if let index = captureServices.firstIndex(of: service) {
            renderers.forEach { $0.updateFrame(sampleBuffer: sampleBuffer, index: index) }
        }
    }

    func captureService(_ service: CaptureService, didFailWith error: Error) {
        print("Capture error: \(error)")
    }
}

@available(macOS 12.3, *)
extension AppDelegate: LayoutConsumer {
    func layoutController(_ controller: LayoutController, didReceive sampleBuffer: CMSampleBuffer) {
        // LayoutController agora é menos usado para roteamento direto
    }
}

@available(macOS 12.3, *)
extension AppDelegate {
    func setupXRWindowIfPossible() {
        if let xrScreen = NSScreen.screens.first(where: { screen in
            let name = screen.localizedName.lowercased()
            return name.contains("xreal") || name.contains("xr") || name.contains("air")
        }) {
            setupXRWindow(on: xrScreen)
        } else {
            print("Nenhum display XREAL encontrado; usando apenas preview.")
        }
    }

    func showControlPanel() {
        let hostingView = NSHostingView(rootView: ControlPanelView(viewModel: layoutViewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        let panel = NSPanel(contentRect: NSRect(x: window.frame.maxX + 16,
                                                y: window.frame.maxY - 520,
                                                width: 360,
                                                height: 520),
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered,
                            defer: false)
        
        panel.title = "Controle PrismaXR"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        
        panel.contentView = hostingView
        
        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
        
        panel.makeKeyAndOrderFront(nil)
        controlPanel = panel
    }

    func cycleScreens() {
        let screens = NSScreen.screens
        // Removi o guard para permitir testar mesmo com 1 tela
        
        let currentScreen = xrWindow?.screen ?? screens.first!
        let currentIndex = screens.firstIndex(of: currentScreen) ?? 0
        let nextIndex = (currentIndex + 1) % screens.count
        let nextScreen = screens[nextIndex]
        
        print("Cycling to screen: \(nextScreen.localizedName)")
        setupXRWindow(on: nextScreen)
    }

    @objc func screensDidChange(_ notification: Notification) {
        let screens = NSScreen.screens
        let xrealScreen = screens.first { screen in
            let name = screen.localizedName.lowercased()
            return name.contains("xreal") || name.contains("xr") || name.contains("air")
        }
        
        if let xrWindow = self.xrWindow {
            if xrealScreen == nil {
                print("XREAL desconectado. Fechando janela XR.")
                renderers.removeAll(where: { $0 === (xrWindow.contentView as? MTKView)?.delegate })
                xrWindow.close()
                self.xrWindow = nil
            }
        } else if let screen = xrealScreen {
            print("XREAL detectado após mudança. Abrindo janela XR.")
            setupXRWindow(on: screen)
        }
    }

    func setupXRWindow(on screen: NSScreen) {
        // Remover o renderer antigo do array se ele pertencer à janela que estamos fechando
        if let oldXR = self.xrWindow {
            renderers.removeAll(where: { $0 === (oldXR.contentView as? MTKView)?.delegate })
            oldXR.close()
            self.xrWindow = nil
        }
        
        let frame = screen.frame
        let newWindow = NSWindow(contentRect: frame,
                                 styleMask: [.borderless],
                                 backing: .buffered,
                                 defer: false)
        
        // Garantir que a janela esteja na tela correta e cubra o frame todo
        newWindow.setFrame(frame, display: true)
        newWindow.level = .screenSaver
        newWindow.isReleasedWhenClosed = false
        newWindow.hidesOnDeactivate = false
        newWindow.canHide = false
        newWindow.tabbingMode = .disallowed
        newWindow.backgroundColor = .black
        newWindow.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]
        
        let xrView = MTKView(frame: newWindow.contentView?.bounds ?? .zero)
        xrView.autoresizingMask = [.width, .height]
        newWindow.contentView = xrView
        
        if let xrRenderer = Renderer(mtkView: xrView) {
            renderers.append(xrRenderer)
            xrRenderer.updateLayout(layoutViewModel.desks)
            self.xrWindow = newWindow
            newWindow.makeKeyAndOrderFront(nil)
            
            print("XR Window initialized on: \(screen.localizedName) at \(frame)")
        } else {
            newWindow.close()
        }
    }
}

let app = NSApplication.shared
if #available(macOS 12.3, *) {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
} else {
    fatalError("PrismaXR requires macOS 12.3 or later")
}
