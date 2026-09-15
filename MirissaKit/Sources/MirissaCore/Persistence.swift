import Foundation

/// Diske yazılan zarf. Sürüm numarası ileride veri yapısı değişirse
/// eski kayıtların kaybolmadan taşınmasını sağlar.
public struct PersistedBlob: Codable {
    public var schemaVersion: Int
    public var savedAt: String
    public var state: AppState

    public init(schemaVersion: Int = Persistence.currentVersion, savedAt: String = ISO8601DateFormatter().string(from: Date()), state: AppState) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.state = state
    }
}

public enum PersistenceError: Error, CustomStringConvertible {
    case futureVersion(Int)
    case corrupt(String)

    public var description: String {
        switch self {
        case let .futureVersion(v):
            return "Bu yedek uygulamanın daha yeni bir sürümünden (\(v)). Önce uygulamayı güncelle."
        case let .corrupt(m):
            return "Yedek dosyası okunamadı: \(m)"
        }
    }
}

public enum Persistence {
    public static let currentVersion = 1

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    public static func encode(_ state: AppState) throws -> Data {
        try encoder().encode(PersistedBlob(state: state))
    }

    /// Sürüm göçlerini sırayla uygular. Bilinmeyen ileri sürüm reddedilir —
    /// veriyi bozarak açmaktansa açmamak daha güvenli.
    public static func decode(_ data: Data) throws -> AppState {
        let decoder = JSONDecoder()
        let blob: PersistedBlob
        do {
            blob = try decoder.decode(PersistedBlob.self, from: data)
        } catch {
            throw PersistenceError.corrupt(String(describing: error))
        }
        guard blob.schemaVersion <= currentVersion else {
            throw PersistenceError.futureVersion(blob.schemaVersion)
        }
        var state = blob.state
        for v in blob.schemaVersion..<currentVersion {
            state = migrate(state, from: v)
        }
        return validate(state)
    }

    /// Fiyat geçmişinde "başlangıçtan beri geçerli" anlamına gelir.
    static let enEskiTarih: DateKey = "1970-01-01"

    static func migrate(_ s: AppState, from version: Int) -> AppState {
        // Sürüm 1 ilk sürüm; ileride buraya (1 -> 2) gibi dönüşümler eklenecek.
        s
    }

    /// Bozuk satırlar uygulamayı çökertmez; sessizce ayıklanır.
    static func validate(_ s: AppState) -> AppState {
        var s = s
        let materialIds = Set(s.materials.map(\.id))
        let productIds = Set(s.products.map(\.id))
        let channelIds = Set(s.channels.map(\.id))

        for i in s.products.indices {
            // Eski ürün bazlı "maliyete dahil" listesi satır bazlı bayrağa taşınır.
            // Stok tüketimi hiçbir şekilde etkilenmez.
            if !s.products[i].costIncludesMaterials.isEmpty {
                let dahil = Set(s.products[i].costIncludesMaterials)
                for j in s.products[i].recipe.indices
                where dahil.contains(s.products[i].recipe[j].materialId) {
                    s.products[i].recipe[j].addsCost = false
                }
                s.products[i].costIncludesMaterials = []
            }
            // Tarihçesiz tek fiyat alanları fiyat geçmişine taşınır.
            // Eski fiyat "her zaman geçerliydi" sayılır ki geçmiş raporlar bozulmasın.
            let eskiFiyatlar = s.products[i].listPrice.map {
                [PricePoint(channelId: nil, amount: $0, from: Persistence.enEskiTarih)]
            } ?? []
            let eskiKanal = (s.products[i].channelPrices ?? [:])
                .sorted { $0.key < $1.key }
                .map { PricePoint(channelId: $0.key, amount: $0.value,
                                  from: Persistence.enEskiTarih) }
            if !eskiFiyatlar.isEmpty || !eskiKanal.isEmpty {
                var liste = s.products[i].priceHistory ?? []
                liste += eskiFiyatlar + eskiKanal
                s.products[i].priceHistory = liste.sorted { $0.from < $1.from }
                s.products[i].listPrice = nil
                s.products[i].channelPrices = nil
            }

            let selfId = s.products[i].id
            s.products[i].recipe.removeAll { !materialIds.contains($0.materialId) }
            s.products[i].components.removeAll { !productIds.contains($0.productId) || $0.productId == selfId }
        }
        // Silinmiş ürünler kanalın "burada satılıyor" listesinde kalmasın
        for i in s.channels.indices {
            if let liste = s.channels[i].soldProductIds {
                let temiz = liste.filter { productIds.contains($0) }
                s.channels[i].soldProductIds = temiz.isEmpty ? nil : temiz
            }
        }
        s.sales.removeAll { !productIds.contains($0.productId) || !channelIds.contains($0.channelId) }
        s.channelMonths.removeAll { !channelIds.contains($0.channelId) }
        s.purchases.removeAll { !exists($0.item, materialIds, productIds) }
        s.adjustments.removeAll { !exists($0.item, materialIds, productIds) }
        s.counts.removeAll { !exists($0.item, materialIds, productIds) }
        return s
    }

    private static func exists(_ ref: ItemRef, _ mats: Set<Id>, _ prods: Set<Id>) -> Bool {
        ref.kind == .material ? mats.contains(ref.id) : prods.contains(ref.id)
    }

    // MARK: - Dosya konumu

    public static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("MirissaFinans", isDirectory: true)
    }

    public static func defaultFile() -> URL {
        defaultDirectory().appendingPathComponent("data.json")
    }
}

/// Diske okuma/yazma. Yazma atomiktir: yarım kalan dosya oluşmaz.
public final class FileStore {
    public let url: URL

    public init(url: URL = Persistence.defaultFile()) {
        self.url = url
    }

    public func load() -> (state: AppState?, error: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, nil) }
        do {
            let data = try Data(contentsOf: url)
            return (try Persistence.decode(data), nil)
        } catch {
            // Bozuk dosyayı silme — kenara al, kullanıcı verisi asla kaybolmasın
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("bozuk-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            return (nil, String(describing: error))
        }
    }

    public func save(_ state: AppState) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try Persistence.encode(state)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        if FileManager.default.fileExists(atPath: tmp.path) {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}
