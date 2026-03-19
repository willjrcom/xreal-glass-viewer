import Foundation
import IOKit.hid
import simd
import OSLog

@available(macOS 11.0, *)
public final class XrealHIDTrackingAdapter: TrackingAdapter {
    private let logger = Logger(subsystem: "com.prismaxr.tracking", category: "xreal_hid")
    private var manager: IOHIDManager?
    private var poseUpdated: ((HeadPose) -> Void)?
    
    // XREAL HID IDs
    private let vendorID: Int32 = 0x3318
    private let productIDs: [Int32] = [0x0424, 0x0428] // Air e Air 2
    
    // Sensor State
    private var currentOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var lastTimestamp: UInt64 = 0
    private var offsetOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    
    // Fusion Constants (Filtro Complementar)
    private let alpha: Float = 0.98
    
    // Calibration State
    private var gyroBias = SIMD3<Float>(0, 0, 0)
    private var calibrationSamples = 0
    private let maxCalibrationSamples = 100 // Testar mais rápido (~0.4s)
    private var isCalibrated = false
    private var gyroBiasSum = SIMD3<Float>(0, 0, 0)
    private var deviceMap: [ObjectIdentifier: (usagePage: Int, usage: Int)] = [:]
    
    public init() throws {}
    
    public func start(poseUpdated: @escaping (HeadPose) -> Void) throws {
        self.poseUpdated = poseUpdated
        
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        
        // Filtro específico para o IMU dos XREAL Air 2
        let deviceMatch: [String: Any] = [
            kIOHIDPrimaryUsagePageKey: 0xFF00,
            kIOHIDPrimaryUsageKey: 0x4
        ]
        IOHIDManagerSetDeviceMatching(manager, deviceMatch as CFDictionary)
        
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, type, reportID, report, reportLength in
            guard let context = context else { return }
            let adapter = Unmanaged<XrealHIDTrackingAdapter>.fromOpaque(context).takeUnretainedValue()
            adapter.handleReport(reportID: reportID, report: report, length: reportLength)
        }, context)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            print("❌ Falha ao abrir dispositivo XREAL IMU: \(openResult)")
            throw TrackingAdapterError.unavailable("Não foi possível acessar o IMU do XREAL.")
        }
        
        print("✅ XREAL HID Tracking (Absolute) iniciado.")
    }
    
    public func stop() {
        if let manager = manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        manager = nil
    }
    
    public func recenter() {
        offsetOrientation = currentOrientation.inverse
        logger.info("Orientação centralizada.")
    }
    
    private func handleReport(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) {
        let reportData = Data(bytes: report, count: length)
        func readFloat32(offset: Int) -> Float {
            guard offset + 4 <= length else { return 0 }
            return reportData.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: Float.self) }
        }
        func readInt16BE(offset: Int) -> Int16 {
            guard offset + 2 <= length else { return 0 }
            return Int16(bitPattern: UInt16(report[offset]) << 8 | UInt16(report[offset+1]))
        }
        
        if length == 122 && report[0] == 0xEC {
            // Air 2 / Ultra - Usar Orientação Absoluta (Euler Angles em Graus)
            // Identificamos nos logs (32, 36, 40)
            let pitchDeg = readFloat32(offset: 32)
            let yawDeg   = readFloat32(offset: 36)
            let rollDeg  = readFloat32(offset: 40)
            
            // Converter Graus -> Radianos
            let p = pitchDeg * .pi / 180.0
            let y = -yawDeg   * .pi / 180.0 
            let r = rollDeg  * .pi / 180.0
            
            // Criar Quaternions para cada eixo
            let qPitch = simd_quatf(angle: p, axis: SIMD3<Float>(1, 0, 0))
            let qYaw   = simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0))
            let qRoll  = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1)) // Travar Roll
            
            currentOrientation = qYaw * qPitch * qRoll
            
            if calibrationSamples % 30 == 0 {
                print("📐 POSE [\(calibrationSamples)]: P:\(String(format: "%.1f", pitchDeg)) Y:\(String(format: "%.1f", yawDeg)) R:\(String(format: "%.1f", rollDeg))")
                fflush(stdout)
            }
            calibrationSamples += 1
            
            let finalPose = HeadPose(timestamp: Date().timeIntervalSince1970,
                                     orientation: offsetOrientation * currentOrientation)
            
            DispatchQueue.main.async {
                self.poseUpdated?(finalPose)
            }
        } else if length == 64 {
            // Fallback para integração se for o Air 1 (64 bytes)
            let gyroScale: Float = 1.0 / 16.4 / 180.0 * .pi
            let gx_f = Float(readInt16BE(offset: 13)) * gyroScale
            let gy_f = Float(readInt16BE(offset: 15)) * gyroScale
            let gz_f = Float(readInt16BE(offset: 17)) * gyroScale
            
            let now = mach_absolute_time()
            if lastTimestamp == 0 { lastTimestamp = now; return }
            let dt = Float(now - lastTimestamp) / 1_000_000_000.0
            lastTimestamp = now
            
            let gyroVec = SIMD3<Float>(gx_f, gy_f, 0)
            let gyroLen = simd_length(gyroVec)
            if gyroLen > 0.0001 {
                let deltaRotation = simd_quatf(angle: gyroLen * dt, axis: normalize(gyroVec))
                currentOrientation = currentOrientation * deltaRotation
            }
            
            let finalPose = HeadPose(timestamp: Date().timeIntervalSince1970,
                                     orientation: offsetOrientation * currentOrientation)
            
            DispatchQueue.main.async {
                self.poseUpdated?(finalPose)
            }
        }
    }
}
