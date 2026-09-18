import Foundation

/// Sipariş önerisi: tüketim hızı ve tedarik süresine göre "en geç ne zaman, ne kadar".
/// Tedarik süresi girilmemiş kalemler için öneri yapılmaz (uydurma süre kullanılmaz).
public struct SiparisOnerisi: Identifiable, Hashable, Sendable {
    public var item: ItemRef
    public var ad: String
    public var birim: UnitCode
    /// Eldeki stok kaç gün yeter
    public var kalanGun: Int
    public var tedarikSuresiGun: Int
    /// En geç bu gün sipariş verilmeli
    public var sonSiparisGunu: DateKey
    /// Önerilen miktar (temel birim): tedarik süresi + 30 gün yetecek kadar, en az sipariş miktarından az değil
    public var miktar: Double
    /// Son gün geçti ya da bugün
    public var acil: Bool
    public var id: String { item.id }
}

public extension Engine {
    /// Güvenlik payı: tedarikte gecikme ve satış artışına karşı
    static let guvenlikGunu = 7
    /// Önerilen miktar tedarik süresinden sonra kaç gün yetsin
    static let kapsamaGunu = 30

    func siparisOnerisi(_ item: ItemRef, bugun: DateKey = Dates.today()) -> SiparisOnerisi? {
        let (sure, moq, ad, birim): (Int?, Double?, String, UnitCode)
        switch item.kind {
        case .material:
            guard let m = materialsById[item.id], !m.archived else { return nil }
            (sure, moq, ad, birim) = (m.tedarikSuresiGun, m.minSiparis, m.name, m.baseUnit)
        case .product:
            guard let p = productsById[item.id], !p.archived, p.tracksOwnStock else { return nil }
            (sure, moq, ad, birim) = (p.tedarikSuresiGun, p.minSiparis, p.name, .adet)
        }
        guard let s = sure, s >= 0 else { return nil }
        let hiz = consumptionRate(item, endingAt: Dates.month(of: bugun), bugun: bugun).perMonth / 30
        guard hiz > 0 else { return nil }
        let q = max(qty(item), 0)
        let kalan = Int((q / hiz).rounded(.down))
        let tetik = s + Engine.guvenlikGunu
        guard kalan <= tetik + 14 else { return nil }     // iki hafta öncesinden haber ver
        let sonGun = Dates.addDays(bugun, kalan - tetik)
        let ihtiyac = (hiz * Double(s + Engine.kapsamaGunu) - q).rounded(.up)
        let miktar = max(ihtiyac, moq ?? 0, hiz)   // en az bir günlük
        return SiparisOnerisi(item: item, ad: ad, birim: birim, kalanGun: kalan,
                              tedarikSuresiGun: s, sonSiparisGunu: sonGun, miktar: miktar,
                              acil: sonGun <= bugun)
    }

    /// Bütün kalemlerin sipariş önerileri, en acili önce
    func siparisOnerileri(bugun: DateKey = Dates.today()) -> [SiparisOnerisi] {
        let kalemler = state.materials.map { ItemRef.material($0.id) } + state.products.map { ItemRef.product($0.id) }
        return kalemler.compactMap { siparisOnerisi($0, bugun: bugun) }.sorted { $0.sonSiparisGunu < $1.sonSiparisGunu }
    }
}
