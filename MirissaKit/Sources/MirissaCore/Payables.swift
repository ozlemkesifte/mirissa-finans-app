import Foundation

/// Vadeli / taksitli alımın ödeme planı.
/// Maliyet ve KDV alım günündedir (fatura tarihi); yalnızca paranın kasadan
/// çıkış zamanı değişir. Peşin + taksitler, ödenen toplamı (KDV dahil) vermelidir.
public struct OdemePlani: Codable, Hashable, Sendable {
    /// Alım günü ödenen kısım
    public var pesinat: Kurus
    public var taksitler: [Taksit]

    public init(pesinat: Kurus, taksitler: [Taksit]) {
        self.pesinat = pesinat
        self.taksitler = taksitler
    }

    public var toplam: Kurus { pesinat + taksitler.reduce(0) { $0 + $1.tutar } }

    /// Kalan tutarı eşit taksitlere böler; kuruş farkı son taksite eklenir
    public static func esit(toplam: Kurus, pesinat: Kurus, taksitSayisi: Int,
                            ilkVade: DateKey, aralikAy: Int = 1) -> OdemePlani {
        let n = max(taksitSayisi, 1)
        let kalan = max(toplam - pesinat, 0)
        let parca = kalan / Kurus(n)
        var liste: [Taksit] = []
        for i in 0..<n {
            let tutar = i == n - 1 ? kalan - parca * Kurus(n - 1) : parca
            liste.append(Taksit(vade: Dates.addMonthsToDate(ilkVade, i * aralikAy), tutar: tutar))
        }
        return OdemePlani(pesinat: pesinat, taksitler: liste)
    }
}

public struct Taksit: Codable, Hashable, Sendable, Identifiable {
    public var id: Id
    public var vade: DateKey
    public var tutar: Kurus
    /// Ödendiyse ödeme günü (vadeden farklı olabilir)
    public var odemeTarihi: DateKey?

    public init(id: Id = UUID().uuidString, vade: DateKey, tutar: Kurus, odemeTarihi: DateKey? = nil) {
        self.id = id
        self.vade = vade
        self.tutar = tutar
        self.odemeTarihi = odemeTarihi
    }

    public var odendi: Bool { odemeTarihi != nil }
    /// Paranın kasadan çıktığı (ya da çıkacağı) gün
    public var nakitGunu: DateKey { odemeTarihi ?? vade }
}

/// Ödenmemiş taksit — tedarikçi borcu
public struct AcikBorc: Identifiable, Hashable, Sendable {
    public var purchaseId: Id
    public var taksit: Taksit
    public var kalem: String
    public var tedarikci: String?
    public var gecikti: Bool
    public var id: String { "\(purchaseId)#\(taksit.id)" }
}

public extension Engine {
    /// Ödenmemiş taksitler, vadesine göre
    func acikBorclar(today: DateKey = Dates.today()) -> [AcikBorc] {
        state.purchases.flatMap { p -> [AcikBorc] in
            (p.odeme?.taksitler ?? []).filter { !$0.odendi }.map {
                AcikBorc(purchaseId: p.id, taksit: $0, kalem: state.itemName(p.item),
                         tedarikci: p.vendor, gecikti: $0.vade < today)
            }
        }
        .sorted { $0.taksit.vade < $1.taksit.vade }
    }

    var acikBorcToplami: Kurus { acikBorclar().reduce(0) { $0 + $1.taksit.tutar } }
}
