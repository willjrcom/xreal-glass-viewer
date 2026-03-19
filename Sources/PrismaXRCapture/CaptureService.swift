import AppKit
import ScreenCaptureKit
import OSLog
import CoreMedia

@available(macOS 12.3, *)
public protocol CaptureServiceDelegate: AnyObject {
    func captureService(_ service: CaptureService, didProduce sampleBuffer: CMSampleBuffer)
    func captureService(_ service: CaptureService, didFailWith error: Error)
}

@available(macOS 12.3, *)
public final class CaptureService: NSObject {
    private let logger = Logger(subsystem: "com.prismaxr.capture", category: "service")
    private var stream: SCStream?
    private var reconnectTask: Task<Void, Never>?
    private var isStoppedManually = false
    public weak var delegate: CaptureServiceDelegate?

    public override init() {
        super.init()
    }

    public func startCapturingMainDisplay() {
        isStoppedManually = false
        Task {
            if let display = try? await fetchAvailableDisplays().first {
                await configureDisplayStream(display)
            }
        }
    }

    public func startCapturingDisplay(_ display: SCDisplay) {
        isStoppedManually = false
        Task { await configureDisplayStream(display) }
    }

    public func stop() {
        isStoppedManually = true
        reconnectTask?.cancel()
        reconnectTask = nil
        let s = stream
        stream = nil
        Task {
            try? await s?.stopCapture()
        }
    }

    private func configureDisplayStream(_ display: SCDisplay) async {
        do {
            // Excluir o próprio app da captura para evitar recursão (hall-of-mirrors)
            let content = try await SCShareableContent.current
            let myPID = ProcessInfo.processInfo.processIdentifier
            let excludedApps = content.applications.filter { app in
                app.processID == myPID
            }

            let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.width = Int(display.width) * 2
            configuration.height = Int(display.height) * 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 8

            let oldStream = self.stream
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            self.stream = stream
            try stream.addStreamOutput(self, type: SCStreamOutputType.screen, sampleHandlerQueue: DispatchQueue.main)
            try await stream.startCapture()
            Task { try? await oldStream?.stopCapture() }
            logger.info("Capture stream started for display \(display.displayID)")
        } catch {
            logger.error("Failed to start capture: \(error.localizedDescription)")
            delegate?.captureService(self, didFailWith: error)
            scheduleReconnect(after: 2)
        }
    }

    private func scheduleReconnect(after seconds: UInt64, display: SCDisplay? = nil) {
        guard !isStoppedManually else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if let display = display {
                await configureDisplayStream(display)
            } else if let firstDisplay = try? await fetchAvailableDisplays().first {
                await configureDisplayStream(firstDisplay)
            }
        }
    }

    public func startCapturingWindow(_ window: SCWindow) {
        isStoppedManually = false
        Task { await configureWindowStream(window) }
    }

    private func configureWindowStream(_ window: SCWindow) async {
        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.width = Int(window.frame.width * 2)
            configuration.height = Int(window.frame.height * 2)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 8

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            let oldStream = self.stream
            self.stream = stream
            
            try stream.addStreamOutput(self, type: SCStreamOutputType.screen, sampleHandlerQueue: DispatchQueue.main)
            try await stream.startCapture()
            
            Task { try? await oldStream?.stopCapture() }
            
            logger.info("Capture stream started for window: \(window.title ?? "Unknown")")
        } catch {
            logger.error("Failed to start window capture: \(error.localizedDescription)")
            delegate?.captureService(self, didFailWith: error)
        }
    }

    public func fetchAvailableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.current
        let myPID = ProcessInfo.processInfo.processIdentifier
        
        // Títulos de sistema que nunca devem aparecer
        let systemTitles: Set<String> = [
            "StatusIndicator", "AudioVideoModule", "underbelly",
            "Menubar", "Fullscreen Backdrop", "Offscreen Wallpaper Window",
            "ScreenMirroring", "Launchpad", "Window", "Notification Center"
        ]
        
        return content.windows.filter { window in
            // Precisa ter título
            guard let title = window.title, !title.isEmpty else { return false }
            // Excluir janelas do próprio PrismaXR
            guard window.owningApplication?.processID != myPID else { return false }
            // Excluir sistema por título exato
            guard !systemTitles.contains(title) else { return false }
            // Excluir Wallpapers e agents do sistema
            guard !title.hasPrefix("Wallpaper-") else { return false }
            guard !title.contains("TextInputMenuAgent") else { return false }
            guard !title.hasPrefix("com.apple.") else { return false }
            guard !title.hasPrefix("org.") || title.contains(" ") else { return false }
            // Excluir janelas muito pequenas (system overlays)
            guard window.frame.width > 50 && window.frame.height > 50 else { return false }
            // Layer 0 = janelas normais, layers acima são overlays do sistema
            guard window.windowLayer == 0 else { return false }
            return true
        }
    }

    public func fetchAvailableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.current
        return content.displays
    }
}

@available(macOS 12.3, *)
extension CaptureService: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("Capture stream stopped: \(error.localizedDescription)")
        delegate?.captureService(self, didFailWith: error)
        scheduleReconnect(after: 2)
    }
}

@available(macOS 12.3, *)
extension CaptureService: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        delegate?.captureService(self, didProduce: sampleBuffer)
    }
}

public enum CaptureError: LocalizedError {
    case displayNotFound

    public var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "No displays available for capture"
        }
    }
}
