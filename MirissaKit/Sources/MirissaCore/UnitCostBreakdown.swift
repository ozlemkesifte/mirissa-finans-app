import Foundation

/// Bir ürünün TEK satışının maliyet dökümü: ürünün kendisi, her ambalaj malzemesi
/// (kutu, koli, poşet, patpat, dolgu, etiket…) ve kanal kesintileri ayrı ayrı.
/// Rakamların hepsi kullanıcının girdiği alımlardan, maliyetlerden ve kanal ayarlarından gelir;
/// bilinmeyen kalem 0 gösterilmez, "maliyeti bilinmiyor" diye işaretlenir.
public struct BirimMaliyetKalemi: Identifiable, Hashable, Sendable {
    public enum Tur: String, Sendable { case urun, ambalaj, koli, kesinti, kargo }
    public var id: String
    public var tur: Tur
    public var ad: String
    /// Nasıl hesaplandı: "1 adet × 11,00 TL" gibi
    public var detay: String
    public var tutar: Kurus
    /// Maliyeti girilmemiş / alımı yok
    public var bilinmiyor: Bool = false
}

public struct BirimMaliyetDokumu: Hashable, Sendable {
    public var productId: Id
    public var kalemler: [BirimMaliyetKalemi]
    public var kanalAdi: String?
    public var toplam: Kurus { kalemler.reduce(0) { $0 + $1.tutar } }
    public var eksikVar: Bool { kalemler.contains(where: \.bilinmiyor) }
}

public extension Engine {

    /// `channelId` verilirse o kanalın komisyon ve kargosu da eklenir (fiyat biliniyorsa).
    func birimMaliyetDokumu(productId: Id, channelId: Id? = nil,
                            on date: DateKey = Dates.today()) -> BirimMaliyetDokumu? {
        guard let p = productsById[productId] else { return nil }
        var out: [BirimMaliyetKalemi] = []
        let b = cost(of: productId, asOf: date)

        // 1) Ürünün kendisi
        if p.isBundle {
            for c in p.components {
                let alt = cost(of: c.productId, asOf: date)
                let ad = productsById[c.productId]?.name ?? "Bileşen"
                out.append(BirimMaliyetKalemi(
                    id: "bilesen-\(c.productId)", tur: .urun, ad: ad,
                    detay: "\(Units.formatQty(c.qty, baseUnit: .adet)) × \(Money.format(alt.intrinsic))",
                    tutar: Money.roundHalfAwayFromZero(Double(alt.intrinsic) * c.qty),
                    bilinmiyor: alt.intrinsic == 0 && !alt.ownFromPurchases))
            }
            for l in p.costLines(on: date) where l.amount != 0 {
                out.append(BirimMaliyetKalemi(id: "kalem-\(l.id)", tur: .urun, ad: l.label.isEmpty ? "Set ek maliyeti" : l.label,
                                              detay: "girdiğin maliyet", tutar: l.amount))
            }
        } else if b.ownFromPurchases {
            out.append(BirimMaliyetKalemi(id: "urun", tur: .urun, ad: "Ürün (alımların ortalaması)",
                                          detay: "stok alımlarında ödediğin ortalama", tutar: b.ownLines))
        } else {
            let satirlar = p.costLines(on: date).filter { $0.amount != 0 }
            if satirlar.isEmpty {
                out.append(BirimMaliyetKalemi(id: "urun", tur: .urun, ad: "Ürün maliyeti",
                                              detay: "girilmedi", tutar: 0, bilinmiyor: true))
            }
            for l in satirlar {
                out.append(BirimMaliyetKalemi(id: "kalem-\(l.id)", tur: .urun,
                                              ad: l.label.isEmpty ? "Ürün maliyeti" : l.label,
                                              detay: "girdiğin maliyet", tutar: l.amount))
            }
        }

        // 2) Ambalaj: reçetedeki her malzeme ayrı
        for line in p.recipe where line.resolvedAddsCost {
            guard let m = materialsById[line.materialId],
                  let taban = Units.toBaseOrNil(qty: line.qty, unit: line.unit,
                                                baseUnit: m.baseUnit, packSizes: m.packSizes) else { continue }
            let birim = unitCost(.material(m.id), asOf: date)
            let tutar = Money.roundHalfAwayFromZero(taban * birim)
            let fiyat = birim >= 100 || birim == 0
                ? Money.format(Money.roundHalfAwayFromZero(birim))
                : Money.format(Money.roundHalfAwayFromZero(birim * 1_000)) + " / 1.000 \(m.baseUnit.displayName)"
            out.append(BirimMaliyetKalemi(
                id: "ambalaj-\(line.id)", tur: m.usedPerOrder ? .koli : .ambalaj, ad: m.name,
                detay: "\(Units.formatQty(line.qty, baseUnit: line.unit)) × \(fiyat)"
                    + (m.usedPerOrder ? " · siparişte 1–2 üründe 1 adet" : ""),
                tutar: tutar, bilinmiyor: birim == 0))
        }

        // 3) Kanal: komisyon ve kargo (fiyat girilmişse)
        var kanalAdi: String?
        if let kid = channelId, let u = unitContribution(productId: productId, channelId: kid, on: date),
           let ch = state.channel(kid) {
            kanalAdi = ch.name
            let yuzde = u.channelFees - u.perOrderFees
            let r = ch.rates(on: date)
            if yuzde != 0 {
                out.append(BirimMaliyetKalemi(
                    id: "kesinti", tur: .kesinti, ad: "\(ch.name) komisyon ve kesintiler",
                    detay: "\(Money.format(u.price)) satış fiyatının %\(RoasFormat.format(r.commissionPct + r.paymentPct + r.otherDeductionPct).replacingOccurrences(of: ",00", with: "")), KDV'siz",
                    tutar: yuzde))
            }
            if u.perOrderFees != 0 {
                out.append(BirimMaliyetKalemi(
                    id: "kargo", tur: .kargo, ad: "\(ch.name) kargo ve hizmet bedeli",
                    detay: "sipariş başına, KDV'siz", tutar: u.perOrderFees))
            }
            for e in u.missingFees {
                out.append(BirimMaliyetKalemi(id: "eksik-\(e)", tur: .kesinti, ad: "\(ch.name) \(e.lowercased())",
                                              detay: "aylık tutarı hiç girilmedi", tutar: 0, bilinmiyor: true))
            }
        }
        return BirimMaliyetDokumu(productId: productId, kalemler: out, kanalAdi: kanalAdi)
    }
}
