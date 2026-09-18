import Foundation

/// Tek dosyalık yedek: bütün kayıtlar + fatura ekleri.
/// Telefon kaybolsa ya da uygulama silinse bile bu dosyadan her şey geri gelir.
public struct BackupPackage: Codable, Sendable {
    public var tur: String
    public var surum: Int
    public var gun: DateKey
    public var olusturuldu: String
    /// Persistence.encode çıktısı (şema sürümüyle birlikte)
    public var veri: Data
    /// Fatura dosyaları: ad → içerik
    public var ekler: [String: Data]

    public static let turAdi = "mirissa-yedek"
}

/// Geri yüklemeden önce kullanıcıya gösterilen özet
public struct BackupPreview: Sendable {
    public var gun: DateKey?
    public var urun: Int
    public var malzeme: Int
    public var satis: Int
    public var gider: Int
    public var alim: Int
    public var fatura: Int
    /// Bozuk ya da sahipsiz olduğu için atlanacak satırlar ("3 satış kaydı" gibi)
    public var atlanan: [String]
    public var state: AppState
    public var ekler: [String: Data]
}

public enum BackupError: Error, CustomStringConvertible {
    case tanimsiz
    public var description: String { "Bu dosya bir Mirissa yedeği değil." }
}

public enum Backup {

    /// Yedek paketi oluşturur. Ekler verilen klasörden okunur; bulunamayan atlanır.
    public static func paket(_ s: AppState, ekURL: (String) -> URL, gun: DateKey = Dates.today()) throws -> Data {
        var ekler: [String: Data] = [:]
        for ad in s.attachmentNames {
            if let d = try? Data(contentsOf: ekURL(ad)) { ekler[ad] = d }
        }
        let p = BackupPackage(tur: BackupPackage.turAdi, surum: 1, gun: gun,
                              olusturuldu: ISO8601DateFormatter().string(from: Date()),
                              veri: try Persistence.encode(s), ekler: ekler)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(p)
    }

    /// Yedeği okur ve özetini çıkarır. Eski düz JSON yedekler de kabul edilir.
    public static func oku(_ data: Data) throws -> BackupPreview {
        var ham: AppState
        var ekler: [String: Data] = [:]
        var gun: DateKey?
        if let p = try? JSONDecoder().decode(BackupPackage.self, from: data),
           p.tur == BackupPackage.turAdi {
            ham = try Persistence.decodeUnvalidated(p.veri)
            ekler = p.ekler
            gun = p.gun
        } else {
            ham = try Persistence.decodeUnvalidated(data)
        }
        let temiz = Persistence.temizle(ham)

        var atlanan: [String] = []
        func fark(_ ad: String, _ a: Int, _ b: Int) {
            if a > b { atlanan.append("\(a - b) \(ad)") }
        }
        fark("satış kaydı", ham.sales.count, temiz.sales.count)
        fark("ay kaydı", ham.channelMonths.count, temiz.channelMonths.count)
        fark("alım", ham.purchases.count, temiz.purchases.count)
        fark("stok düzeltmesi", ham.adjustments.count, temiz.adjustments.count)
        fark("sayım", ham.counts.count, temiz.counts.count)
        fark("reçete satırı", ham.products.reduce(0) { $0 + $1.recipe.count },
             temiz.products.reduce(0) { $0 + $1.recipe.count })
        fark("set bileşeni", ham.products.reduce(0) { $0 + $1.components.count },
             temiz.products.reduce(0) { $0 + $1.components.count })

        return BackupPreview(gun: gun, urun: temiz.products.count, malzeme: temiz.materials.count,
                             satis: temiz.sales.count, gider: temiz.expenses.count,
                             alim: temiz.purchases.count, fatura: ekler.count,
                             atlanan: atlanan, state: temiz, ekler: ekler)
    }

    /// Otomatik yedek: günde bir dosya, en yeni `sakla` kadarı tutulur.
    @discardableResult
    public static func otomatikYedekAl(_ s: AppState, ekURL: (String) -> URL, klasor: URL,
                                       gun: DateKey = Dates.today(), onEk: String = "otomatik",
                                       sakla: Int = 14) throws -> URL {
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let url = klasor.appendingPathComponent("mirissa-\(onEk)-\(gun).json")
        try paket(s, ekURL: ekURL, gun: gun).write(to: url, options: .atomic)
        // Eski otomatik yedekleri temizle (geri yükleme öncesi kopyalara dokunma)
        let dosyalar = ((try? FileManager.default.contentsOfDirectory(atPath: klasor.path)) ?? [])
            .filter { $0.hasPrefix("mirissa-\(onEk)-") }
            .sorted()
        for fazla in dosyalar.dropLast(sakla) {
            try? FileManager.default.removeItem(at: klasor.appendingPathComponent(fazla))
        }
        return url
    }

    /// Otomatik yedeklerin durduğu klasör: Dosyalar uygulamasında
    /// "iPhone'umda → Mirissa Finans → Yedekler" olarak görünür, iCloud cihaz yedeğine girer.
    public static func varsayilanKlasor() -> URL {
        let docs = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("Yedekler", isDirectory: true)
    }

    /// Kaç gündür telefon dışına yedek alınmadı (hiç alınmadıysa nil)
    public static func yedeksizGun(_ s: AppSettings, bugun: DateKey = Dates.today()) -> Int? {
        s.ek.sonYedekPaylasim.map { Dates.daysBetween($0, bugun) }
    }
}
