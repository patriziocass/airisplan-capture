import Foundation
import RoomPlan
import simd

/// Converte il risultato di RoomPlan nel contratto `skeleton.json` versione 1 di AirisPlan.
///
/// Sistema di uscita: "pianta" con Z verso l'alto. Da RoomPlan (Y verso l'alto):
///   x_pianta = x,  y_pianta = -z,  altezza = y - y_pavimento.
/// Tutte le coordinate sono ancora nel sistema dell'iPhone: `transform_to_cloud` e' "none",
/// l'allineamento alla nuvola S20 lo fa il motore sul server.
enum SkeletonExporter {

    struct Input {
        var walls: [CapturedRoom.Surface]
        var doors: [CapturedRoom.Surface]
        var windows: [CapturedRoom.Surface]
        var openings: [CapturedRoom.Surface]
        var floors: [CapturedRoom.Surface]
        var objects: [CapturedRoom.Object]
        var sections: [CapturedRoom.Section]
        var roomCount: Int
    }

    static func input(from room: CapturedRoom) -> Input {
        Input(walls: room.walls, doors: room.doors, windows: room.windows, openings: room.openings,
              floors: room.floors, objects: room.objects, sections: room.sections, roomCount: 1)
    }

    static func input(from structure: CapturedStructure) -> Input {
        Input(walls: structure.walls, doors: structure.doors, windows: structure.windows,
              openings: structure.openings, floors: structure.floors, objects: structure.objects,
              sections: structure.rooms.flatMap { $0.sections }, roomCount: structure.rooms.count)
    }

    // MARK: geometria

    private static func world(_ t: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> {
        let v = t * SIMD4<Float>(p.x, p.y, p.z, 1)
        return SIMD3<Float>(v.x, v.y, v.z)
    }

    private static func plan(_ p: SIMD3<Float>) -> [Double] {
        [round4(Double(p.x)), round4(Double(-p.z))]
    }

    private static func round4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
    private static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    private static func position(_ t: simd_float4x4) -> SIMD3<Float> {
        SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    /// Estremi in pianta di una superficie verticale (muro, porta, finestra, varco): asse locale X = larghezza.
    private static func endpoints(_ s: CapturedRoom.Surface) -> (SIMD3<Float>, SIMD3<Float>) {
        let half = s.dimensions.x / 2
        return (world(s.transform, SIMD3<Float>(-half, 0, 0)), world(s.transform, SIMD3<Float>(half, 0, 0)))
    }

    /// Poligono in pianta di un pavimento. `polygonCorners` (iOS 17) puo' essere nel sistema locale
    /// della superficie o in quello del mondo: si decide guardando dove sta il baricentro.
    private static func floorPolygon(_ s: CapturedRoom.Surface) -> (poly: [[Double]], frame: String) {
        let corners = s.polygonCorners
        if corners.count >= 3 {
            let c = corners.reduce(SIMD3<Float>(0, 0, 0), +) / Float(corners.count)
            let pos = position(s.transform)
            let asLocal = simd_length(c)
            let asWorld = simd_length(c - pos)
            if asWorld < asLocal {
                return (corners.map { plan($0) }, "world")
            } else {
                return (corners.map { plan(world(s.transform, $0)) }, "local->world")
            }
        }
        // ripiego: rettangolo dalle dimensioni (larghezza X, profondita' Z nel piano locale)
        let hx = s.dimensions.x / 2, hz = s.dimensions.z / 2
        let pts = [SIMD3<Float>(-hx, 0, -hz), SIMD3<Float>(hx, 0, -hz), SIMD3<Float>(hx, 0, hz), SIMD3<Float>(-hx, 0, hz)]
        return (pts.map { plan(world(s.transform, $0)) }, "rect")
    }

    private static func objectPolygon(_ o: CapturedRoom.Object) -> [[Double]] {
        let hx = o.dimensions.x / 2, hz = o.dimensions.z / 2
        let pts = [SIMD3<Float>(-hx, 0, -hz), SIMD3<Float>(hx, 0, -hz), SIMD3<Float>(hx, 0, hz), SIMD3<Float>(-hx, 0, hz)]
        return pts.map { plan(world(o.transform, $0)) }
    }

    private static func pointInPolygon(_ p: [Double], _ poly: [[Double]]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let xi = poly[i][0], yi = poly[i][1], xj = poly[j][0], yj = poly[j][1]
            if (yi > p[1]) != (yj > p[1]) {
                let x = (xj - xi) * (p[1] - yi) / (yj - yi) + xi
                if p[0] < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private static func polygonArea(_ poly: [[Double]]) -> Double {
        var a = 0.0
        for i in 0..<poly.count {
            let j = (i + 1) % poly.count
            a += poly[i][0] * poly[j][1] - poly[j][0] * poly[i][1]
        }
        return abs(a) / 2
    }

    private static func label(_ section: CapturedRoom.Section) -> String {
        "\(section.label)"
    }

    // MARK: skeleton

    static func skeleton(from input: Input, levelName: String, appVersion: String) -> [String: Any] {
        // quota del pavimento nel sistema RoomPlan (Y): la piu' bassa fra i pavimenti, altrimenti 0
        let floorY: Float = input.floors.map { position($0.transform).y }.min() ?? 0

        func opening(_ s: CapturedRoom.Surface) -> [String: Any] {
            let (a, b) = endpoints(s)
            let c = position(s.transform)
            let wallAny: Any = s.parentIdentifier.map { $0.uuidString as Any } ?? NSNull()
            return [
                "id": s.identifier.uuidString,
                "wall": wallAny,
                "p1": plan(a), "p2": plan(b),
                "width": round3(Double(s.dimensions.x)),
                "sill": round3(Double(c.y - s.dimensions.y / 2 - floorY)),
                "top": round3(Double(c.y + s.dimensions.y / 2 - floorY)),
                "confidence": "\(s.confidence)",
                "snapped": false,
            ]
        }

        let walls: [[String: Any]] = input.walls.map { s in
            let (a, b) = endpoints(s)
            let c = position(s.transform)
            return [
                "id": s.identifier.uuidString,
                "p1": plan(a), "p2": plan(b),
                "length": round3(Double(s.dimensions.x)),
                "thickness": NSNull(),               // RoomPlan non misura lo spessore
                "height": round3(Double(s.dimensions.y)),
                "base": round3(Double(c.y - s.dimensions.y / 2 - floorY)),
                "is_curved": s.curve != nil,
                "confidence": "\(s.confidence)",
                "snapped": false,
            ]
        }

        // locali: poligono del pavimento + nome dalla sezione che ci cade dentro
        var rooms: [[String: Any]] = []
        for (i, f) in input.floors.enumerated() {
            let (poly, frame) = floorPolygon(f)
            var name = "Other"
            for sec in input.sections {
                let c = plan(SIMD3<Float>(sec.center.x, sec.center.y, sec.center.z))
                if pointInPolygon(c, poly) {
                    name = label(sec)
                    break
                }
            }
            rooms.append([
                "id": "Floor_\(i)",
                "roomplan_id": f.identifier.uuidString,
                "name": name,
                "polygon": poly,
                "polygon_frame": frame,
                "area_m2": round3(polygonArea(poly)),
                "floor_y_roomplan": round3(Double(position(f.transform).y)),
            ])
        }

        let furniture: [[String: Any]] = input.objects.map { o in
            let c = position(o.transform)
            return [
                "id": o.identifier.uuidString,
                "category": "\(o.category)",
                "polygon": objectPolygon(o),
                "height": round3(Double(c.y + o.dimensions.y / 2 - floorY)),
                "confidence": "\(o.confidence)",
            ]
        }

        return [
            "schema_version": 1,
            "source": "roomplan-app",
            "app_version": appVersion,
            "units": "m", "up_axis": "z", "heights_from": "floor",
            "coordinate_note": "sistema iPhone/ARKit convertito a Z up: x_pianta = x, y_pianta = -z. Non ancora allineato alla nuvola.",
            "level": ["name": levelName, "floor_z": round3(Double(floorY)), "rooms_scanned": input.roomCount],
            "transform_to_cloud": ["rotation_deg": 0, "translation": [0, 0], "scale": 1.0,
                                   "method": "none", "rms_m": NSNull(), "matched_walls": 0, "total_walls": walls.count],
            "walls": walls,
            "doors": input.doors.map { opening($0) },
            "windows": input.windows.map { opening($0) },
            "openings": input.openings.map { opening($0) },
            "rooms": rooms,
            "furniture": furniture,
            "furniture_ignored": furniture.map { $0["id"] as? String ?? "" },
            "to_verify": [],
        ]
    }

    static func jsonData(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }
}
