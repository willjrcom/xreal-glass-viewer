import SwiftUI
import PrismaXRRenderer
import ScreenCaptureKit

@available(macOS 12.3, *)
struct ControlPanelView: View {
    @ObservedObject var viewModel: LayoutViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("PrismaXR Control")
                    .font(.title3).bold()

                // Seletor de quantidade de telas
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quantidade de Telas").font(.headline)
                    Picker("Telas", selection: $viewModel.screenCount) {
                        Text("1 Tela").tag(1)
                        Text("2 Telas").tag(2)
                        Text("3 Telas").tag(3)
                    }
                    .pickerStyle(.segmented)
                }

                ForEach(Array(viewModel.desks.enumerated()), id: \.element.id) { index, _ in
                    DeskCardView(viewModel: viewModel, index: index)
                }

                VStack(alignment: .leading) {
                    Text("Presets").font(.headline)
                    HStack {
                        ForEach(LayoutViewModel.Preset.allCases) { preset in
                            Button(preset.rawValue) {
                                viewModel.resetPreset(preset)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 320, idealWidth: 360)
        .padding(.vertical, 8)
    }
}

@available(macOS 12.3, *)
private struct DeskCardView: View {
    @ObservedObject var viewModel: LayoutViewModel
    let index: Int

    var body: some View {
        if index < viewModel.desks.count {
        let desk = viewModel.desks[index]
        
        VStack(alignment: .leading, spacing: 8) {
            Text(desk.name).font(.headline)

            // Fonte: estilo Mission Control
            Picker("Fonte", selection: Binding(
                get: {
                    guard index < viewModel.desks.count else { return "d:0" }
                    if let winID = viewModel.desks[index].windowID { return "w:\(winID)" }
                    if let dispID = viewModel.desks[index].displayID { return "d:\(dispID)" }
                    return "d:0"
                },
                set: { newValue in
                    let parts = newValue.split(separator: ":")
                    guard parts.count == 2, let id = UInt32(parts[1]) else { return }
                    
                    if parts[0] == "w" {
                        if let window = viewModel.availableWindows.first(where: { $0.windowID == id }) {
                            viewModel.selectWindow(index: index, window: window)
                        }
                    } else {
                        if let display = viewModel.availableDisplays.first(where: { $0.displayID == id }) {
                            viewModel.selectDisplay(index: index, display: display)
                        } else if let first = viewModel.availableDisplays.first {
                            viewModel.selectDisplay(index: index, display: first)
                        }
                    }
                }
            )) {
                // Mesa 1 = Desktop principal
                ForEach(viewModel.availableDisplays.filter { display in
                    let screens = NSScreen.screens
                    return !screens.contains { screen in
                        let name = screen.localizedName.lowercased()
                        return (name.contains("xreal") || name.contains("air"))
                               && screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 == display.displayID
                    }
                }, id: \.displayID) { display in
                    Text("🖥 Mesa 1 (Desktop)").tag("d:\(display.displayID)")
                }
                
                Divider()
                
                // Cada app = uma "mesa" como no Mission Control
                ForEach(viewModel.availableWindows, id: \.windowID) { window in
                    let appName = window.owningApplication?.applicationName ?? window.title ?? "App"
                    Text(appName).tag("w:\(window.windowID)")
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text("Posição")
                Spacer()
                Text(String(format: "%.1fm", desk.horizontalOffset))
            }
            Slider(value: Binding(
                get: { index < viewModel.desks.count ? Double(viewModel.desks[index].horizontalOffset) : 0.0 },
                set: { if index < viewModel.desks.count { viewModel.desks[index].horizontalOffset = Float($0) } }),
                   in: -3.0...3.0,
                   step: 0.05)

            HStack {
                Text("Distância")
                Spacer()
                Text(String(format: "%.1fm", desk.radius))
            }
            Slider(value: Binding(
                get: { index < viewModel.desks.count ? Double(viewModel.desks[index].radius) : 1.6 },
                set: { if index < viewModel.desks.count { viewModel.desks[index].radius = Float($0) } }),
                   in: 0.3...3.5,
                   step: 0.1)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
