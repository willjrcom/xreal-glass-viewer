# XR Multi-Monitor Proposal (Codename: PrismaXR)

## 1. Why a New App?
Nebula for Mac provides the baseline virtual display experience for XREAL glasses but struggles with macOS Mission Control, often losing window focus when spaces change and failing to respect full-screen transitions. Community feedback also highlights stability drops after resume and limited layout persistence. Competing tools such as BetterDisplay and RealWarp focus on mirroring or warp effects instead of offering a full XR workspace, so there is room for a purpose-built alternative that maintains macOS ergonomics while exploiting XR depth.

## 2. Product Goals
1. Feel native to macOS Mission Control and Spaces.
2. Preserve 60 FPS (target 16 ms frame budget) even when three 4K virtual displays are active.
3. Support both virtual monitors (floating planes) and passthrough windows anchored to real-world surfaces.
4. Offer quick layout presets and automated window binding for common workflows (IDE + docs + comms).
5. Ship with a recovery mode that restores a safe default layout if head-tracking or capture fails.

## 3. User Journeys
- **Focus Mode:** User pins a single “main” screen but gestures left/right to reveal adjacent screens without invoking Mission Control. Ideal for coding sprints.
- **Presentation Mode:** PrismaXR streams one virtual canvas to conferencing software (via virtual camera) so remote peers see the XR layout.
- **Research Mode:** Up to three XR screens arranged in an arc, each bound to a Mission Control Space. Switching spaces re-routes capture surfaces instantly.

## 4. System Architecture
```
App Shell (SwiftUI + AppKit bridge)
  ├─ CaptureService (ScreenCaptureKit) → CGImage / CVPixelBuffer
  ├─ LayoutController (Mission Control & Spaces awareness)
  ├─ SceneGraph (MetalKit + RealityKit abstractions)
  │     ├─ PlaneMesh nodes per virtual monitor
  │     └─ SpatialAnchors (ARKit / XREAL SDK)
  ├─ HeadTrackingService (CoreMotion + device IMU via vendor SDK)
  └─ OutputPipelines
        ├─ XR Glasses (DisplayPort Alt Mode)
        └─ Preview window (for debugging / recording)
```

### 4.1 Capture Layer
- Leverage ScreenCaptureKit per-window capture with `SCContentFilter(window:)` to keep latency low and allow privacy indicator compliance.
- Implement time-stamped frame queues (`MetalSharedEvent`) so Pose updates and textures stay synchronized.
- Use IOSurface-backed textures to avoid CPU copies when feeding Metal pipelines.

### 4.2 Scene Graph + Renderer
- Metal renderer built on triple-buffered command queues; each virtual monitor is a textured plane with emissive bloom disabled to reduce halo artifacts.
- Support curved layouts by tessellating the plane (subdivisions = 16) and binding captured texture with UV remap for slight curvature.
- Add thin-film shader variant to simulate anti-aliasing when text is viewed off-axis.

### 4.3 Head Tracking + Spatial Persistence
- Fuse CoreMotion gyro data at 200 Hz with vendor-specific inside-out tracking (XREAL NRSDK) using complementary filters.
- Persist anchors in `NSUbiquitousKeyValueStore` so layouts sync across Macs.
- Add jitter guard: clamp sudden >3° deltas within 1 frame to avoid nausea.

### 4.4 Mission Control Compatibility
- Subscribe to `NSWorkspaceActiveSpaceDidChangeNotification` to re-map captured windows when the user changes Spaces.
- Represent each Mission Control Space as a logical layer in LayoutController; if a window goes full-screen, capture the `ScreenCaptureSession` tied to that space and reposition the XR plane rather than forcing macOS to create a new desktop.
- Provide Adaptive Focus: when the user invokes Mission Control, pause XR rendering and show a macOS-native HUD overlay so the system gesture is not blocked.

### 4.5 Reliability + Recovery
- Watchdog monitors (`dispatch_source_make_timer`) restart ScreenCapture sessions if no new frame arrives after 250 ms.
- Ship a menu-bar “panic” toggle that collapses all XR planes back to a 2D mirrored view for quick recovery.

## 5. Implementation Roadmap
1. **Foundation (Weeks 0-4)**
   - Scaffold Swift package with ScreenCaptureKit capture demo and Metal preview window.
   - Integrate NRSDK for pose data; log 6DoF streams.
2. **Mission Control Integration (Weeks 4-8)**
   - Build LayoutController with Space awareness and window-binding UI.
   - Add fail-safe overlay for Mission Control invocation.
3. **XR Scene + Performance (Weeks 8-12)**
   - Implement curved layout renderer, frame pacing, and triple buffering.
   - Tune GPU counters using Xcode GPU Frame Debugger; ensure <16 ms frame time baseline.
4. **Experience Layer (Weeks 12-16)**
   - Preset manager, gesture shortcuts, and presentation streaming (Metal texture → virtual camera driver).
   - Telemetry + crash reporting (MetricKit) and recovery flows.

## 6. Risks & Mitigations
- **OS-level constraints:** macOS still treats XR glasses as a single external monitor. Mitigation: run PrismaXR as the only app drawing to that display while presenting multiple virtual planes inside our compositor.
- **Latency spikes from ScreenCaptureKit:** Pre-allocate capture pipelines, avoid resizing sessions mid-stream, and throttle to 45 FPS when resource pressure rises.
- **SDK fragmentation:** Abstract head tracking behind protocol-based adapters so we can support XREAL, Viture, and future Apple XR APIs without rewriting core logic.

## 7. Next Steps
- Validate legal licensing for NRSDK distribution.
- Prototype Mission Control-aware capture on macOS 14.5 and 15 beta to ensure APIs remain stable.
- Conduct user tests with 5 power users who currently rely on Nebula to benchmark stability improvements and gather feature requests.
