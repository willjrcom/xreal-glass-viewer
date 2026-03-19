import AppKit
import CoreGraphics
import OSLog

// CGVirtualDisplay API declarations (private CoreGraphics API, used by Chromium & BetterDisplay)
@objc protocol CGVirtualDisplayMode_P {
    @objc var width: Int { get }
    @objc var height: Int { get }
    @objc var refreshRate: Double { get }
    init(width: Int, height: Int, refreshRate: Double)
}

@objc protocol CGVirtualDisplayDescriptor_P {
    @objc var vendorID: UInt32 { get set }
    @objc var productID: UInt32 { get set }
    @objc var serialNum: UInt32 { get set }
    @objc var name: String { get set }
    @objc var maxPixelsWide: UInt32 { get set }
    @objc var maxPixelsHigh: UInt32 { get set }
    @objc var sizeInMillimeters: CGSize { get set }
    @objc var queue: DispatchQueue { get set }
    init()
}

@objc protocol CGVirtualDisplaySettings_P {
    @objc var hiDPI: Int { get set }
    init()
}

@objc protocol CGVirtualDisplay_P {
    @objc var displayID: UInt32 { get }
    init?(descriptor: AnyObject)
    @objc func applySettings(_ settings: AnyObject) -> Bool
}

@available(macOS 12.0, *)
public final class VirtualDisplayManager {
    private let logger = Logger(subsystem: "com.prismaxr.virtualdisplay", category: "manager")
    private var virtualDisplays: [AnyObject] = []
    private var displayIDs: [CGDirectDisplayID] = []

    public var createdDisplayIDs: [CGDirectDisplayID] { displayIDs }

    public init() {}

    /// Cria `count` displays virtuais posicionados ao lado do monitor principal.
    public func createDisplays(count: Int = 2, width: Int = 1920, height: Int = 1080) -> [CGDirectDisplayID] {
        // Carregar classes dinamicamente
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
            logger.error("CGVirtualDisplay API não disponível neste macOS.")
            return []
        }

        var ids: [CGDirectDisplayID] = []

        for i in 0..<count {
            // Criar descriptor
            let descriptor = descriptorClass.init()
            descriptor.setValue(UInt32(0x1234), forKey: "vendorID")
            descriptor.setValue(UInt32(0x5678 + i), forKey: "productID")
            descriptor.setValue(UInt32(100 + i), forKey: "serialNum")
            descriptor.setValue("PrismaXR \(i + 1)", forKey: "name")
            descriptor.setValue(UInt32(width), forKey: "maxPixelsWide")
            descriptor.setValue(UInt32(height), forKey: "maxPixelsHigh")
            descriptor.setValue(CGSize(width: 600, height: 340), forKey: "sizeInMillimeters")
            descriptor.setValue(DispatchQueue.main, forKey: "queue")

            // Criar modo
            let modeObj = modeClass.init()
            modeObj.setValue(width, forKey: "width")
            modeObj.setValue(height, forKey: "height")
            modeObj.setValue(60.0, forKey: "refreshRate")

            descriptor.setValue([modeObj], forKey: "modes")

            // Criar virtual display
            guard let display = displayClass.perform(NSSelectorFromString("initWithDescriptor:"), with: descriptor)?.takeUnretainedValue() else {
                logger.error("Falha ao criar virtual display \(i + 1)")
                continue
            }

            // Aplicar settings (HiDPI)
            let settings = settingsClass.init()
            settings.setValue(0, forKey: "hiDPI")
            _ = display.perform(NSSelectorFromString("applySettings:"), with: settings)

            if let displayID = display.value(forKey: "displayID") as? UInt32 {
                ids.append(displayID)
                virtualDisplays.append(display)
                logger.info("Virtual display criado: PrismaXR \(i + 1) (ID: \(displayID))")
            }
        }

        displayIDs = ids
        return ids
    }

    /// Remove todos os displays virtuais.
    public func destroyAll() {
        virtualDisplays.removeAll()
        displayIDs.removeAll()
        logger.info("Todos os displays virtuais removidos.")
    }

    deinit {
        destroyAll()
    }
}
