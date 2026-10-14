import RoomPlan
import SwiftUI
import UIKit

let appVersion: String = {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    return "\(v) (\(b))"
}()

@MainActor
final class CaptureModel: ObservableObject {
    enum Phase: Equatable {
        case scanning          // RoomPlan attivo sulla stanza corrente
        case roomDone          // stanza chiusa, scelta: altra stanza o termina
        case exporting
        case done
        case failed(String)
    }

    @Published var phase: Phase = .scanning
    @Published var rooms: [CapturedRoom] = []
    @Published var lastRoomSummary = ""
    @Published var result: ExportStore.Result?
    let bridge = CaptureBridge()

    func roomFinished(_ room: CapturedRoom) {
        rooms.append(room)
        lastRoomSummary = "Stanza \(rooms.count): \(room.walls.count) muri, \(room.doors.count) porte, " +
            "\(room.windows.count) finestre, \(room.openings.count) varchi, \(room.objects.count) arredi"
        phase = .roomDone
    }

    func finishRoom() {
        bridge.controller?.finishRoom()
    }

    func nextRoom() {
        phase = .scanning
        bridge.controller?.startScan()
    }

    func finishSurvey() {
        bridge.controller?.stopAll()
        let csv = bridge.controller?.trajectory.csv() ?? ""
        phase = .exporting
        let rooms = self.rooms
        Task {
            do {
                let r = try await ExportStore.export(rooms: rooms, trajectoryCSV: csv, appVersion: appVersion)
                self.result = r
                self.phase = .done
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }
}

struct ContentView: View {
    @State private var showCapture = false
    @State private var exports: [URL] = ExportStore.listExports()
    @State private var shareItems: [URL]? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showCapture = true
                    } label: {
                        Label("Nuovo rilievo", systemImage: "camera.metering.matrix")
                            .font(.title3.weight(.semibold))
                    }
                    .disabled(!RoomCaptureSession.isSupported)
                    if !RoomCaptureSession.isSupported {
                        Text("Questo iPhone non ha il LiDAR: RoomPlan non e' disponibile.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Rilievi salvati") {
                    if exports.isEmpty {
                        Text("Nessun rilievo. I file finiscono in File > Su questo iPhone > AirisPlan Rilievo > Rilievi.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(exports, id: \.self) { url in
                        Button {
                            let fm = FileManager.default
                            let files = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                            shareItems = files
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                Text(url.lastPathComponent)
                                Spacer()
                                Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("Versione \(appVersion). I rilievi producono skeleton.json (contratto AirisPlan v1), roomplan.json, modello.usdz, mesh.usdz e traiettoria.csv.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AirisPlan Rilievo")
        }
        .fullScreenCover(isPresented: $showCapture, onDismiss: { exports = ExportStore.listExports() }) {
            CaptureFlowView()
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems {
                ShareSheet(items: items)
            }
        }
    }
}

struct CaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CaptureModel()
    @State private var errorText: String? = nil
    @State private var showShare = false

    var body: some View {
        ZStack {
            RoomCaptureScreen(bridge: model.bridge,
                              onRoomFinished: { room in Task { @MainActor in model.roomFinished(room) } },
                              onError: { msg in Task { @MainActor in errorText = msg } })
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Annulla") {
                        model.bridge.controller?.stopAll()
                        dismiss()
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Text("Stanze: \(model.rooms.count)")
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding()
                Spacer()
                bottomBar
                    .padding()
            }

            if model.phase == .exporting {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView("Salvataggio del rilievo…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("Errore", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .sheet(isPresented: $showShare, onDismiss: { dismiss() }) {
            if let r = model.result {
                ShareSheet(items: r.files)
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch model.phase {
        case .scanning:
            Button {
                model.finishRoom()
            } label: {
                Text("Fine stanza")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
        case .roomDone:
            VStack(spacing: 10) {
                Text(model.lastRoomSummary)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button {
                        model.nextRoom()
                    } label: {
                        Text("Altra stanza").frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(.bordered)
                    Button {
                        model.finishSurvey()
                    } label: {
                        Text("Termina rilievo").frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .exporting:
            EmptyView()
        case .done:
            VStack(spacing: 10) {
                Text(model.result?.summary ?? "")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Text("Chiudi").frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(.bordered)
                    Button {
                        showShare = true
                    } label: {
                        Text("Condividi i file").frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .failed(let msg):
            VStack(spacing: 10) {
                Text("Salvataggio fallito: \(msg)")
                    .font(.footnote)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                Button("Chiudi") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
