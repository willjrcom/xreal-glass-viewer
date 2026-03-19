import Foundation
import simd

public final class FallbackTrackingAdapter: TrackingAdapter {
    private var timer: DispatchSourceTimer?

    public init() {}

    public func start(poseUpdated: @escaping (HeadPose) -> Void) throws {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler {
            let pose = HeadPose(timestamp: Date().timeIntervalSince1970,
                                orientation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
            poseUpdated(pose)
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }
}
