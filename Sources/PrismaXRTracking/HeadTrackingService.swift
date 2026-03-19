import Foundation
import OSLog
import simd

#if canImport(CoreMotion) && !os(macOS)
import CoreMotion
#endif

@available(macOS 11.0, *)
public protocol HeadTrackingServiceDelegate: AnyObject {
    func headTrackingService(_ service: HeadTrackingService, didUpdate pose: HeadPose)
}

public struct HeadPose {
    public let timestamp: TimeInterval
    public let orientation: simd_quatf
}

@available(macOS 11.0, *)
public final class HeadTrackingService {
    private let logger = Logger(subsystem: "com.prismaxr.tracking", category: "head")
    public weak var delegate: HeadTrackingServiceDelegate?
    private let adapter: TrackingAdapter
    private var fallbackTimer: DispatchSourceTimer?

    public init(adapter: TrackingAdapter? = nil) {
        if let adapter {
            self.adapter = adapter
        } else {
            if let xreal = try? XrealHIDTrackingAdapter() {
                self.adapter = xreal
            } else if #available(macOS 12.3, *) {
                self.adapter = NRSDKTrackingAdapter()
            } else {
                self.adapter = FallbackTrackingAdapter()
            }
        }
    }

    public func recenter() {
        (adapter as? XrealHIDTrackingAdapter)?.recenter()
    }

    public func start() {
        do {
            try adapter.start { [weak self] pose in
                guard let self else { return }
                self.delegate?.headTrackingService(self, didUpdate: pose)
            }
        } catch {
            logger.error("Adapter indisponível: \(error.localizedDescription). Ativando fallback.")
            startFallbackPose()
        }
    }

    public func stop() {
        adapter.stop()
        fallbackTimer?.cancel()
        fallbackTimer = nil
    }

    private func startFallbackPose() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let pose = HeadPose(timestamp: Date().timeIntervalSince1970,
                                orientation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
            delegate?.headTrackingService(self, didUpdate: pose)
        }
        timer.resume()
        fallbackTimer = timer
    }
}
