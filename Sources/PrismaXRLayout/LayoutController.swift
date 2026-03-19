import Foundation
import Combine
import AppKit
import OSLog
import CoreMedia

public enum WorkspaceEvent {
    case spaceChanged(UUID)
    case missionControlInvoked
    case missionControlDismissed
}

@available(macOS 11.0, *)
public protocol LayoutConsumer: AnyObject {
    func layoutController(_ controller: LayoutController, didReceive sampleBuffer: CMSampleBuffer)
}

@available(macOS 11.0, *)
public final class LayoutController {
    private let logger = Logger(subsystem: "com.prismaxr.layout", category: "controller")
    private var cancellables = Set<AnyCancellable>()
    public let workspaceEvents = PassthroughSubject<WorkspaceEvent, Never>()
    public weak var consumer: LayoutConsumer?

    public init(notificationCenter: NotificationCenter = .default, consumer: LayoutConsumer? = nil) {
        self.consumer = consumer
        notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                let identifier = UUID()
                self?.logger.info("Space changed")
                self?.workspaceEvents.send(.spaceChanged(identifier))
            }
            .store(in: &cancellables)
    }

    public func route(sampleBuffer: CMSampleBuffer) {
        consumer?.layoutController(self, didReceive: sampleBuffer)
    }

    public func missionControl(begin: Bool) {
        workspaceEvents.send(begin ? .missionControlInvoked : .missionControlDismissed)
    }
}
