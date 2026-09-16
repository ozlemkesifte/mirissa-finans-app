import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Fatura ve fiş dosyaları. Uygulamanın kendi klasöründe durur;
/// kayıtta sadece dosya adı tutulur.
public enum AttachmentStore {
    /// Testlerin gerçek uygulama klasörüne dokunmaması için
    nonisolated(unsafe) public static var overrideDirectory: URL?

    public static func directory() -> URL {
        let base = overrideDirectory ?? Persistence.defaultDirectory()
        let dir = base.appendingPathComponent("ekler", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func url(_ name: String) -> URL {
        directory().appendingPathComponent(name)
    }

    public static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    public static func isPDF(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".pdf")
    }

    /// Dosyayı kaydeder ve dosya adını döner.
    /// Fotoğraflar 2000 piksele sığdırılıp JPEG'e çevrilir — telefonda yer kaplamasın.
    public static func save(data: Data, suggestedExtension ext: String) throws -> String {
        let name = "ek_\(Ids.make(.expense))"
        if ext.lowercased() == "pdf" {
            let file = "\(name).pdf"
            try data.write(to: url(file), options: .atomic)
            return file
        }
        let file = "\(name).jpg"
        let out = shrinkToJPEG(data) ?? data
        try out.write(to: url(file), options: .atomic)
        return file
    }

    public static func save(fileAt source: URL) throws -> String {
        let data = try Data(contentsOf: source)
        return try save(data: data, suggestedExtension: source.pathExtension)
    }

    public static func delete(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(name))
    }

    public static func all() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory(), includingPropertiesForKeys: nil)) ?? []
    }

    /// Hiçbir kayda bağlı olmayan dosyaları siler.
    public static func prune(keeping names: Set<String>) {
        for f in all() where !names.contains(f.lastPathComponent) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// Belirli bir klasörde temizlik. Klasör verilmezse uygulamanın klasörü.
    /// Birden çok depo aynı anda çalışıyorsa (testler) her biri yalnızca
    /// kendi klasörünü temizler; birbirinin dosyasını silmez.
    public static func prune(keeping names: Set<String>, in klasor: URL?) {
        guard let klasor else { prune(keeping: names); return }
        let ekler = klasor.appendingPathComponent("ekler", isDirectory: true)
        let dosyalar = (try? FileManager.default.contentsOfDirectory(
            at: ekler, includingPropertiesForKeys: nil)) ?? []
        for f in dosyalar where !names.contains(f.lastPathComponent) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// Büyük fotoğrafları küçültür. Platformdan bağımsız (ImageIO).
    static func shrinkToJPEG(_ data: Data, maxPixel: Int = 2000, quality: Double = 0.72) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

public extension AppState {
    /// Kayıtlara bağlı bütün fatura dosyalarının adları
    var attachmentNames: Set<String> {
        var out: Set<String> = []
        for e in expenses {
            if let a = e.attachment { out.insert(a) }
            for (_, ov) in e.overrides { if let a = ov.attachment { out.insert(a) } }
        }
        for p in purchases { if let a = p.attachment { out.insert(a) } }
        return out
    }
}
