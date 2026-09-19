import Foundation

/// Bir ürünün bir kanaldaki dönem sonucu.
/// Kanalın kesinti ve giderleri ürünlere dağıtılır; bir kanaldaki ürünlerin
/// "kalan" toplamı, kanalın "kanalda kalan" tutarına kuruşu kuruşuna eşittir.
public struct UrunKanalSonuc: Identifiable, Hashable, Sendable {
    public var productId: Id
    public var productName: String
    public var channelId: Id
    public var channelName: String
    public var adet: Double
    public var iadeAdet: Double
    /// KDV hariç net satış (indirim ve iade düşülmüş)
    public var netSatis: Kurus
    /// Komisyon, ödeme ve diğer yüzde kesintiler + aylık sabit ücret payı
    public var kesinti: Kurus
    /// `kesinti` içindeki aylık sabit ücret payı (satış olmasa da ödenen kısım)
    public var sabitKesinti: Kurus = 0
    /// Kargo ve hizmet bedeli payı (adede göre)
    public var kargo: Kurus
    public var urunMaliyeti: Kurus
    /// Ürün başı ambalaj + koli payı
    public var ambalaj: Kurus
    /// Reklam payı (ciroya göre dağıtılır)
    public var reklam: Kurus
    /// Kanala işaretlenmiş diğer giderlerin payı (ciroya göre)
    public var digerGider: Kurus

    public var id: String { "\(channelId)#\(productId)" }

    public var reklamOncesiKalan: Kurus { netSatis - kesinti - kargo - urunMaliyeti - ambalaj }
    public var kalan: Kurus { reklamOncesiKalan - reklam - digerGider }
    public var marjPct: Double { netSatis > 0 ? Double(kalan) / Double(netSatis) * 100 : 0 }
    /// Satılan (iade düşülmüş) adet başına kalan
    public var adetBasiKalan: Double? {
        let net = adet - iadeAdet
        return net > 0 ? Double(kalan) / net : nil
    }

    static func topla(_ a: UrunKanalSonuc, _ b: UrunKanalSonuc) -> UrunKanalSonuc {
        var r = a
        r.adet += b.adet; r.iadeAdet += b.iadeAdet; r.netSatis += b.netSatis
        r.kesinti += b.kesinti; r.kargo += b.kargo; r.urunMaliyeti += b.urunMaliyeti
        r.ambalaj += b.ambalaj; r.reklam += b.reklam; r.digerGider += b.digerGider
        r.sabitKesinti += b.sabitKesinti
        return r
    }
}

public extension Engine {

    /// Toplamı bozmadan dağıtır: en büyük kalan yöntemiyle kuruşlar yuvarlanır,
    /// parçaların toplamı her zaman `toplam`a eşittir.
    static func dagit(_ toplam: Kurus, _ agirlik: [Double]) -> [Kurus] {
        guard !agirlik.isEmpty else { return [] }
        let t = agirlik.reduce(0, +)
        guard t > 0 else {
            // Ağırlık yoksa eşit böl
            return dagit(toplam, Array(repeating: 1, count: agirlik.count))
        }
        let ham = agirlik.map { Double(toplam) * $0 / t }
        var tam = ham.map { Kurus($0.rounded(.towardZero)) }
        var kalan = toplam - tam.reduce(0, +)
        let sira = ham.indices.sorted {
            abs(ham[$0] - Double(tam[$0])) > abs(ham[$1] - Double(tam[$1]))
        }
        var i = 0
        let adim: Kurus = kalan >= 0 ? 1 : -1
        while kalan != 0, !sira.isEmpty {
            tam[sira[i % sira.count]] += adim
            kalan -= adim
            i += 1
        }
        return tam
    }

    /// Bir ayın ürün × kanal sonuçları
    func urunKanalKarliligi(month: MonthKey) -> [UrunKanalSonuc] {
        let asOf = Dates.monthEnd(month)
        var out: [UrunKanalSonuc] = []
        for r in companyMonth(month).channels {
            let satirlar = state.sales.filter { $0.month == month && $0.channelId == r.channelId }
            // Aynı ürünün birden çok satırı tek kalemde toplanır
            var urunler: [Id] = []
            for e in satirlar where !urunler.contains(e.productId) { urunler.append(e.productId) }
            guard !urunler.isEmpty else { continue }

            func toplam(_ p: Id, _ f: (SalesEntry) -> Double) -> Double {
                satirlar.filter { $0.productId == p }.reduce(0) { $0 + f($1) }
            }
            let net = urunler.map { p in toplam(p) { Double($0.vatSplit.net) } }
            let kdvDahil = urunler.map { p in toplam(p) { Double($0.vatSplit.net + $0.vatSplit.vat) } }
            let adet = urunler.map { p in toplam(p) { $0.qty } }
            let iade = urunler.map { p in toplam(p) { $0.returnsQty } }

            // Ürün maliyeti ve ürün başı ambalaj: motorla aynı satır hesabı
            var maliyet: [Kurus] = [], birimAmbalaj: [Kurus] = []
            for p in urunler {
                let b = cost(of: p, asOf: asOf)
                let birim = birimUrunMaliyeti(p, asOf: asOf)
                maliyet.append(satirlar.filter { $0.productId == p }.reduce(0) {
                    $0 + Money.roundHalfAwayFromZero(birim * $1.netQty) })
                birimAmbalaj.append(satirlar.filter { $0.productId == p }.reduce(0) {
                    $0 + Money.roundHalfAwayFromZero(Double(b.packaging) * $1.qty) })
            }
            // Koli: ambalaj toplamının ürün başı kısmı dışında kalanı, koli kullanan ürünlere
            let koliToplam = r.packagingCost - birimAmbalaj.reduce(0, +)
            let koliAgirlik = zip(urunler, adet).map { p, a in
                cost(of: p, asOf: asOf).orderPackaging > 0 ? a : 0
            }
            let koli = Engine.dagit(koliToplam, koliAgirlik.reduce(0, +) > 0 ? koliAgirlik : adet)

            let yuzdeKesinti = r.commission.amount + (r.otherDeduction.amount - r.fixedDeduction)
            let sabitKesinti = Engine.dagit(r.fixedDeduction, net)
            let kesinti = zip(Engine.dagit(yuzdeKesinti, kdvDahil), sabitKesinti).map(+)
            let kargo = Engine.dagit(r.shipping.amount + r.serviceFee.amount, adet)
            let reklam = Engine.dagit(r.ads.amount, net)
            let diger = Engine.dagit(r.otherChannelExpensesTotal, net)
            // Net satış: kanal toplamıyla birebir aynı olsun diye kanal tutarı dağıtılır
            let netSatis = Engine.dagit(r.netSales, net)
            let urunMaliyeti = Engine.dagit(r.productCost, maliyet.map(Double.init))

            for (i, p) in urunler.enumerated() {
                out.append(UrunKanalSonuc(
                    productId: p, productName: productsById[p]?.name ?? "Ürün",
                    channelId: r.channelId, channelName: r.channelName,
                    adet: adet[i], iadeAdet: iade[i], netSatis: netSatis[i],
                    kesinti: kesinti[i], sabitKesinti: sabitKesinti[i], kargo: kargo[i], urunMaliyeti: urunMaliyeti[i],
                    ambalaj: birimAmbalaj[i] + koli[i], reklam: reklam[i], digerGider: diger[i]))
            }
        }
        return out
    }

    /// Bir dönemin ürün × kanal sonuçları (aylar toplanır)
    func urunKanalKarliligi(from: MonthKey, to: MonthKey) -> [UrunKanalSonuc] {
        var toplam: [String: UrunKanalSonuc] = [:]
        var sira: [String] = []
        for m in Dates.monthRange(from: from, to: to) {
            for s in urunKanalKarliligi(month: m) {
                if let v = toplam[s.id] { toplam[s.id] = UrunKanalSonuc.topla(v, s) }
                else { toplam[s.id] = s; sira.append(s.id) }
            }
        }
        return sira.compactMap { toplam[$0] }.sorted { $0.kalan > $1.kalan }
    }
}

/// Çok ürünlü satış girişinde toplam iade adedinin ürünlere bölünmesi
public enum SaleSplit {
    /// Toplam iade adedi, satılan adetle orantılı ve tam adet olarak bölünür (toplam korunur);
    /// hiçbir satıra sattığından fazla iade yazılmaz.
    public static func iadeAdetleri(_ toplam: Double, adetler: [Double]) -> [Double] {
        guard !adetler.isEmpty else { return [] }
        let hedef = Int(min(toplam, adetler.reduce(0, +)).rounded())
        var parca = Engine.dagit(hedef, adetler).map(Double.init)
        // Sınırı aşan satırın fazlası, yeri olan satırlara kaydırılır
        var fazla = 0.0
        for i in parca.indices where parca[i] > adetler[i] {
            fazla += parca[i] - adetler[i]
            parca[i] = adetler[i]
        }
        for i in parca.indices where fazla > 0 {
            let yer = adetler[i] - parca[i]
            let ek = min(yer.rounded(.down), fazla)
            parca[i] += ek
            fazla -= ek
        }
        return parca
    }
}
