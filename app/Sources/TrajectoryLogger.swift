import ARKit
import Foundation
import simd

/// Registra la traiettoria della camera ARKit a 10 Hz, con il tempo di sistema e il tempo ARKit.
/// Serve al server per inizializzare l'allineamento con la traiettoria dello S20 (gps_time).
final class TrajectoryLogger {
    struct Row {
        let unixTime: Double      // secondi dal 1970, orologio del telefono
        let arTime: Double        // secondi dall'avvio del sistema (ARFrame.timestamp)
        let x: Float, y: Float, z: Float          // posizione camera, sistema RoomPlan/ARKit (Y verso l'alto)
        let qx: Float, qy: Float, qz: Float, qw: Float
        let trackingOK: Bool
    }

    private(set) var rows: [Row] = []
    private var timer: Timer?
    private weak var session: ARSession?

    func start(session: ARSession) {
        self.session = session
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        rows.removeAll()
    }

    private func sample() {
        guard let frame = session?.currentFrame else { return }
        let t = frame.camera.transform
        let q = simd_quatf(t)
        let p = t.columns.3
        var ok = false
        if case .normal = frame.camera.trackingState { ok = true }
        rows.append(Row(unixTime: Date().timeIntervalSince1970, arTime: frame.timestamp,
                        x: p.x, y: p.y, z: p.z,
                        qx: q.vector.x, qy: q.vector.y, qz: q.vector.z, qw: q.vector.w,
                        trackingOK: ok))
    }

    /// CSV con due sistemi: quello ARKit (Y up) e quello "pianta" usato nello skeleton.json (Z up: x, -z, y).
    func csv() -> String {
        var s = "unix_time;ar_time;x_arkit;y_arkit;z_arkit;qx;qy;qz;qw;tracking_ok;x_zup;y_zup;z_zup\n"
        for r in rows {
            s += String(format: "%.3f;%.4f;%.4f;%.4f;%.4f;%.5f;%.5f;%.5f;%.5f;%d;%.4f;%.4f;%.4f\n",
                        r.unixTime, r.arTime, r.x, r.y, r.z, r.qx, r.qy, r.qz, r.qw, r.trackingOK ? 1 : 0,
                        r.x, -r.z, r.y)
        }
        return s
    }
}
