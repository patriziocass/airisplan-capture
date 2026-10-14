import Foundation
import RoomPlan

/// Scrive i file di un rilievo in Documenti/Rilievi/<data-ora>/ (visibile nell'app File e via iTunes).
enum ExportStore {
    struct Result {
        let folder: URL
        let files: [URL]
        let summary: String
    }

    static var rootFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Rilievi", isDirectory: true)
    }

    static func listExports() -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: rootFolder, includingPropertiesForKeys: nil) else { return [] }
        return items.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func export(rooms: [CapturedRoom], trajectoryCSV: String, appVersion: String) async throws -> Result {
        let fm = FileManager.default
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let name = df.string(from: Date())
        let folder = rootFolder.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        var files: [URL] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let input: SkeletonExporter.Input
        if rooms.count >= 2 {
            let builder = StructureBuilder(options: [.beautifyObjects])
            let structure = try await builder.capturedStructure(from: rooms)
            input = SkeletonExporter.input(from: structure)

            let model = folder.appendingPathComponent("modello.usdz")
            try structure.export(to: model, exportOptions: .parametric)
            files.append(model)
            let mesh = folder.appendingPathComponent("mesh.usdz")
            try structure.export(to: mesh, exportOptions: .mesh)
            files.append(mesh)
            let json = folder.appendingPathComponent("roomplan.json")
            try encoder.encode(structure).write(to: json)
            files.append(json)
        } else if let room = rooms.first {
            input = SkeletonExporter.input(from: room)

            let model = folder.appendingPathComponent("modello.usdz")
            try room.export(to: model, exportOptions: .parametric)
            files.append(model)
            let mesh = folder.appendingPathComponent("mesh.usdz")
            try room.export(to: mesh, exportOptions: .mesh)
            files.append(mesh)
            let json = folder.appendingPathComponent("roomplan.json")
            try encoder.encode(room).write(to: json)
            files.append(json)
        } else {
            throw NSError(domain: "AirisPlan", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nessuna stanza acquisita."])
        }

        let skeleton = SkeletonExporter.skeleton(from: input, levelName: name, appVersion: appVersion)
        let skelURL = folder.appendingPathComponent("skeleton.json")
        try SkeletonExporter.jsonData(skeleton).write(to: skelURL)
        files.append(skelURL)

        let trajURL = folder.appendingPathComponent("traiettoria.csv")
        try trajectoryCSV.data(using: .utf8)?.write(to: trajURL)
        files.append(trajURL)

        let summary = "\(input.roomCount) stanze, \(input.walls.count) muri, \(input.doors.count) porte, " +
            "\(input.windows.count) finestre, \(input.openings.count) varchi, \(input.objects.count) arredi"
        let infoURL = folder.appendingPathComponent("riepilogo.txt")
        try "AirisPlan Rilievo \(appVersion)\n\(name)\n\(summary)\n".data(using: .utf8)?.write(to: infoURL)
        files.append(infoURL)

        return Result(folder: folder, files: files, summary: summary)
    }
}
