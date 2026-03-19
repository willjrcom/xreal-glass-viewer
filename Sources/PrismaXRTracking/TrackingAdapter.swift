import Foundation
import OSLog
import simd

public enum TrackingAdapterError: LocalizedError {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}

public protocol TrackingAdapter {
    func start(poseUpdated: @escaping (HeadPose) -> Void) throws
    func stop()
}

@available(macOS 12.3, *)
public final class NRSDKTrackingAdapter: TrackingAdapter {
    private let logger = Logger(subsystem: "com.prismaxr.tracking", category: "nrsdk")

    public init() {}

    public func start(poseUpdated: @escaping (HeadPose) -> Void) throws {
#if canImport(NRSDK)
        logger.info("NRSDK detectado – inicializando sessão real")
        // TODO: instanciar sessão NRSDK, registrar callbacks e encaminhar HeadPose.
        // Exemplo ilustrativo (ajustar após integração real):
        // session = NRSDKSession()
        // session?.delegate = self
        // session?.start()
#else
        throw TrackingAdapterError.unavailable("NRSDK.framework não encontrado no ambiente. Adicione o SDK ao projeto e certifique-se de que esté em DYLD_FRAMEWORK_PATH.")
#endif
    }

    public func stop() {
#if canImport(NRSDK)
        logger.info("Encerrando sessão NRSDK")
        // session?.stop()
#endif
    }
}
