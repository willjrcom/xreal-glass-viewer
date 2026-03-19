import Foundation
import CoreGraphics

public struct DeskLayoutConfiguration: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var horizontalOffset: Float
    public var radius: Float
    public var height: Float
    public var tilt: Float
    public var windowID: UInt32?
    public var displayID: UInt32?

    public init(id: UUID = UUID(),
                name: String,
                horizontalOffset: Float,
                radius: Float,
                height: Float = 0,
                tilt: Float = 0,
                windowID: UInt32? = nil) {
        self.id = id
        self.name = name
        self.horizontalOffset = horizontalOffset
        self.radius = radius
        self.height = height
        self.tilt = tilt
        self.windowID = windowID
    }
}

public extension Array where Element == DeskLayoutConfiguration {
    static func defaultDeskLayouts() -> [DeskLayoutConfiguration] {
        [
            DeskLayoutConfiguration(name: "Mesa A", horizontalOffset: -2.0, radius: 1.8, tilt: 0.0),
            DeskLayoutConfiguration(name: "Mesa B", horizontalOffset: 0.0, radius: 1.6, tilt: 0.0),
            DeskLayoutConfiguration(name: "Mesa C", horizontalOffset: 2.0, radius: 1.8, tilt: 0.0)
        ]
    }
}
