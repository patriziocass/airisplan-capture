import ARKit
import RoomPlan
import SwiftUI
import UIKit

/// Controller che tiene la RoomCaptureView di Apple e gestisce avvio, fine stanza, stanza successiva.
final class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    var onRoomFinished: ((CapturedRoom) -> Void)?
    var onError: ((String) -> Void)?

    private var captureView: RoomCaptureView!
    let trajectory = TrajectoryLogger()
    private(set) var isScanning = false

    init() { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func viewDidLoad() {
        super.viewDidLoad()
        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.delegate = self
        captureView.captureSession.delegate = self
        view.addSubview(captureView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startScan()
    }

    /// Avvia (o riavvia per la stanza successiva) la scansione. L'ARSession resta la stessa,
    /// quindi tutte le stanze sono nello stesso sistema di coordinate.
    func startScan() {
        guard !isScanning else { return }
        var config = RoomCaptureSession.Configuration()
        config.isCoachingEnabled = true
        captureView.captureSession.run(configuration: config)
        trajectory.start(session: captureView.captureSession.arSession)
        isScanning = true
    }

    /// Chiude la stanza corrente ma non ferma l'ARSession: si puo' passare alla stanza successiva.
    func finishRoom() {
        guard isScanning else { return }
        isScanning = false
        captureView.captureSession.stop(pauseARSession: false)
    }

    /// Fine rilievo: ferma tutto.
    func stopAll() {
        trajectory.stop()
        if isScanning {
            isScanning = false
            captureView.captureSession.stop()
        }
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error = error {
            onError?(error.localizedDescription)
        }
        onRoomFinished?(processedResult)
    }

    // MARK: RoomCaptureSessionDelegate

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        if let error = error {
            onError?(error.localizedDescription)
        }
    }
}

/// Ponte verso SwiftUI: i pulsanti dell'interfaccia chiamano il controller attraverso questo oggetto.
final class CaptureBridge: ObservableObject {
    weak var controller: RoomCaptureViewController?
}

struct RoomCaptureScreen: UIViewControllerRepresentable {
    let bridge: CaptureBridge
    let onRoomFinished: (CapturedRoom) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> RoomCaptureViewController {
        let vc = RoomCaptureViewController()
        vc.onRoomFinished = onRoomFinished
        vc.onError = onError
        bridge.controller = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: RoomCaptureViewController, context: Context) {}
}
