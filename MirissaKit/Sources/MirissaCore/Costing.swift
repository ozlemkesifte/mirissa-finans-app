import Foundation

public struct CostBreakdown: Hashable, Sendable {
    /// Ürünün kendi maliyet kalemleri (üretim vb.)
    public var ownLines: Kurus
    /// Set ise bileşen ürünlerin maliyeti (paketlemeleri hariç)
    public var components: Kurus
    /// Paketleme reçetesinin malzeme maliyeti
    public var packaging: Kurus
    /// Ürünün kendi maliyeti girilen kalemlerden değil, gerçek alımların
    /// ağırlıklı ortalamasından geldi
    public var ownFromPurchases: Bool = false
    /// Sipariş başına kullanılan malzemeler (koli): tek ürünlük bir siparişte.
    /// `packaging` bunları içermez; satışta koli sayısına göre ayrıca düşülür.
    public var orderPackaging: Kurus = 0

    /// Paketleme hariç ürün maliyeti — satılan malın maliyeti (SMM) budur
    public var intrinsic: Kurus { ownLines + components }
    /// Tek ürünlük bir siparişin toplam maliyeti
    public var total: Kurus { intrinsic + packaging + orderPackaging }

    public static let zero = CostBreakdown(ownLines: 0, components: 0, packaging: 0)
}

public enum CostingError: Error, CustomStringConvertible {
    case cycle([String])
    public var description: String {
        "Set tanımı kendini içeriyor: " + cycle.joined(separator: " → ")
    }
    private var cycle: [String] {
        if case let .cycle(c) = self { return c }
        return []
    }
}

/// Sipariş başına kullanılan malzemelerin (koli) aylık tüketimi.
///
/// Satışlar ay toplamı olarak girilir, siparişlerin kaç üründen oluştuğu bilinmez.
/// Kural: 1–2 ürünlük sipariş 1 koli, 3 ve üzeri ürünlük sipariş 2 koli.
///   koli = sipariş sayısı + 3 ve üzeri ürünlü sipariş sayısı
/// Sipariş sayısı girilmemişse her ürün ayrı koli sayılır (tahmini).
/// 3+ ürünlü sipariş sayısı girilmemişse her büyük siparişte 3 ürün olduğu varsayılır:
/// siparişlere 2'şer ürün düştükten sonra artan her ürün bir 3+ sipariş sayılır. Bu en az değer
/// değildir (büyük siparişler daha kalabalıksa koli daha az olur); sonuç "tahmini" işaretlenir,
/// 3+ ürünlü sipariş sayısı girilince kesinleşir.
public enum OrderPackaging {
    public static let ikinciKoliUrunSayisi = 3

    public struct Tuketim: Hashable, Sendable {
        public var materialId: Id
        /// Temel birim cinsinden (koli: adet)
        public var qty: BaseQty
    }

    public struct Sonuc: Hashable, Sendable {
        public var kalemler: [Tuketim]
        /// Gönderilen toplam koli (sipariş) birimi
        public var koliSayisi: Double
        public var siparisSayisi: Int?
        public var buyukSiparis: Int
        /// Sipariş sayısı ya da 3+ sipariş sayısı girilmediği için tahmin
        public var tahmini: Bool
        public static let bos = Sonuc(kalemler: [], koliSayisi: 0, siparisSayisi: nil,
                                      buyukSiparis: 0, tahmini: false)
    }

    /// Bir kanalın bir ayda kaç koli gönderdiği (malzemeden bağımsız)
    public static func siparisBilgisi(_ s: AppState, month: MonthKey, channelId: Id)
    -> (adet: Double, siparis: Int?, buyuk: Int, koli: Double, tahmini: Bool) {
        let adet = s.sales.filter { $0.month == month && $0.channelId == channelId && $0.qty > 0 }
            .reduce(0.0) { $0 + $1.qty }
        guard adet > 0 else { return (0, nil, 0, 0, false) }
        let cm = s.channelMonth(month: month, channelId: channelId)
        guard let girilen = cm?.orderCount, girilen > 0 else {
            // Sipariş sayısı yoksa her ürün ayrı sipariş sayılır (tahmini)
            return (adet, nil, 0, adet, true)
        }
        let o = min(girilen, Int(adet.rounded(.up)))
        var buyuk = 0
        var tahmini = true
        if let b = cm?.bigOrderCount {
            buyuk = min(max(b, 0), o)
            tahmini = false
        } else {
            buyuk = min(max(Int((adet - 2 * Double(o)).rounded(.up)), 0), o)
        }
        return (adet, o, buyuk, min(Double(o + buyuk), adet), tahmini)
    }

    /// Bir kanalın bir aydaki sipariş başı malzeme tüketimi.
    /// `stokIcin` true ise stoktan düşen satırlar, false ise maliyete giren satırlar sayılır:
    /// iki bayrak ayrı ayrı işaretlenebildiği için hesap da ayrı yapılır.
    public static func hesapla(_ s: AppState, month: MonthKey, channelId: Id,
                               stokIcin: Bool = true) -> Sonuc {
        let satirlar = s.sales.filter { $0.month == month && $0.channelId == channelId && $0.qty > 0 }
        let adet = satirlar.reduce(0.0) { $0 + $1.qty }
        guard adet > 0 else { return .bos }
        let malzemeler = s.malzemelerTarihli(Dates.monthEnd(month))
        // O ayda geçerli reçetelerle
        let urunler = s.urunlerTarihli(Dates.monthEnd(month))

        // Her sipariş-başı malzeme için: bu malzemeyi kullanan ürün adedi × satırdaki miktar
        var agirlik: [Id: Double] = [:]
        for e in satirlar {
            guard let p = urunler[e.productId] else { continue }
            for line in p.recipe where (stokIcin ? line.resolvedConsumesStock : line.resolvedAddsCost) {
                guard let m = malzemeler[line.materialId], m.usedPerOrder,
                      let birim = Units.toBaseOrNil(qty: line.qty, unit: line.unit,
                                                    baseUnit: m.baseUnit, packSizes: m.packSizes),
                      birim > 0 else { continue }
                agirlik[m.id, default: 0] += birim * e.qty
            }
        }
        guard !agirlik.isEmpty else { return .bos }

        let bilgi = siparisBilgisi(s, month: month, channelId: channelId)
        let (koli, tahmini, buyuk, siparis) = (bilgi.koli, bilgi.tahmini, bilgi.buyuk, bilgi.siparis)
        let kalemler = agirlik.keys.sorted().map { id -> Tuketim in
            // Koli sayısı, malzemeyi kullanan ürünlerin payı kadar
            let q = (koli * agirlik[id]! / adet).rounded()
            return Tuketim(materialId: id, qty: max(q, 1))
        }
        return Sonuc(kalemler: kalemler, koliSayisi: koli, siparisSayisi: siparis,
                     buyukSiparis: buyuk, tahmini: tahmini)
    }

    /// Bir siparişte ortalama kaç koli gider (sipariş sayısı girilmiş son aydan).
    /// Veri yoksa ürün adedine kuraldan: 3 ve üzeri 2, değilse 1.
    public static func koliPerSiparis(_ s: AppState, channelId: Id, month: MonthKey,
                                      urunAdedi: Double) -> Double {
        for geri in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 0] {
            let ay = Dates.addMonths(month, -geri)
            let r = siparisBilgisi(s, month: ay, channelId: channelId)
            if let o = r.siparis, o > 0 { return r.koli / Double(o) }
        }
        // Veri yoksa: 2 ürüne kadar 1 koli, üstündeki her ürün için 3+ olma olasılığı
        // kadar ikinci koli. 2 üründe 1, 3 üründe 2 koli; aradaki ortalamalar orantılı.
        return 1 + min(max(urunAdedi - 2, 0), 1)
    }
}

public enum Costing {
    static let maxDepth = 8

    /// Bir ürünü stok tutan yaprak ürünlere açar.
    /// Set → bileşenleri (çarpanla). Normal ürün → kendisi.
    /// Kendini içeren set tanımında sonsuz döngüye girmez.
    public static func explodeToLeafProducts(
        products: [Id: Product],
        productId: Id,
        qty: Double,
        visiting: Set<Id> = [],
        depth: Int = 0
    ) -> [Id: Double] {
        guard depth < maxDepth, !visiting.contains(productId),
              let p = products[productId] else { return [:] }
        guard p.isBundle, !p.components.isEmpty else { return [productId: qty] }

        var out: [Id: Double] = [:]
        var next = visiting
        next.insert(productId)
        for c in p.components {
            let sub = explodeToLeafProducts(
                products: products, productId: c.productId,
                qty: qty * c.qty, visiting: next, depth: depth + 1
            )
            for (k, v) in sub { out[k, default: 0] += v }
        }
        return out
    }

    /// Setin kendini içerip içermediğini kontrol eder.
    public static func hasCycle(products: [Id: Product], productId: Id) -> Bool {
        func walk(_ id: Id, _ seen: Set<Id>, _ depth: Int) -> Bool {
            if seen.contains(id) { return true }
            if depth >= maxDepth { return true }
            guard let p = products[id], p.isBundle else { return false }
            var s = seen
            s.insert(id)
            return p.components.contains { walk($0.productId, s, depth + 1) }
        }
        return walk(productId, [], 0)
    }

    /// Paketleme reçetesinin maliyeti: her satır için (temel birim miktarı × malzeme birim maliyeti)
    public static func packagingCost(
        product: Product,
        materials: [Id: StockMaterial],
        unitCostOf: (Id) -> Double,
        perOrder: Bool = false
    ) -> Kurus {
        var total = 0.0
        for line in product.recipe {
            // Üretim maliyetine zaten dahilse maliyeti tekrar sayma.
            // Stok hareketi bundan etkilenmez; yalnızca çift maliyet önlenir.
            guard line.resolvedAddsCost else { continue }
            guard let mat = materials[line.materialId], mat.usedPerOrder == perOrder else { continue }
            guard let base = Units.toBaseOrNil(
                qty: line.qty, unit: line.unit,
                baseUnit: mat.baseUnit, packSizes: mat.packSizes
            ) else { continue }
            total += base * unitCostOf(mat.id)
        }
        return Money.roundHalfAwayFromZero(total)
    }

    /// Bir ürünün kendi (paketleme ve bileşen hariç) birim maliyeti.
    ///
    /// Kullanıcının girdiği maliyet kalemleri önceliklidir: yazdığı rakam
    /// sessizce başka bir rakamla değiştirilmez.
    /// Maliyet hiç girilmemiş ama ürün stok alımıyla alınmışsa (fason üretim,
    /// hazır ürün) ödenen tutarların ağırlıklı ortalaması kullanılır. Aksi halde
    /// maliyet 0 sayılır, alım da gider yazılmadığı için o para hiçbir yerde
    /// gider olarak görünmezdi. İkisi birbirini tutmuyorsa Integrity uyarır.
    static func ownCost(_ p: Product, asOf: DateKey?,
                        purchasedUnitCostOf: (Id) -> Double) -> (Kurus, Bool) {
        let girilen = p.costLines(on: asOf).reduce(0) { $0 + $1.amount }
        if girilen == 0, !p.isBundle, p.tracksOwnStock {
            let alim = purchasedUnitCostOf(p.id)
            if alim > 0 { return (Money.roundHalfAwayFromZero(alim), true) }
        }
        return (girilen, false)
    }

    /// Paketleme hariç ürün maliyeti (kendi kalemleri + bileşenlerin aynı şekilde hesaplanmışı)
    public static func intrinsicCost(
        products: [Id: Product],
        productId: Id,
        asOf: DateKey? = nil,
        visiting: Set<Id> = [],
        depth: Int = 0,
        purchasedUnitCostOf: (Id) -> Double = { _ in 0 }
    ) -> Kurus {
        guard depth < maxDepth, !visiting.contains(productId),
              let p = products[productId] else { return 0 }
        var total = ownCost(p, asOf: asOf, purchasedUnitCostOf: purchasedUnitCostOf).0
        if p.isBundle {
            var next = visiting
            next.insert(productId)
            for c in p.components {
                let sub = intrinsicCost(
                    products: products, productId: c.productId, asOf: asOf,
                    visiting: next, depth: depth + 1,
                    purchasedUnitCostOf: purchasedUnitCostOf
                )
                total += Money.roundHalfAwayFromZero(Double(sub) * c.qty)
            }
        }
        return total
    }

    public static func breakdown(
        products: [Id: Product],
        materials: [Id: StockMaterial],
        productId: Id,
        asOf: DateKey? = nil,
        unitCostOf: (Id) -> Double,
        purchasedUnitCostOf: (Id) -> Double = { _ in 0 }
    ) -> CostBreakdown {
        guard let p = products[productId] else { return .zero }
        let (own, alimdan) = ownCost(p, asOf: asOf, purchasedUnitCostOf: purchasedUnitCostOf)
        var comps = 0
        if p.isBundle {
            for c in p.components {
                let sub = intrinsicCost(products: products, productId: c.productId, asOf: asOf,
                                        visiting: [productId], depth: 1,
                                        purchasedUnitCostOf: purchasedUnitCostOf)
                comps += Money.roundHalfAwayFromZero(Double(sub) * c.qty)
            }
        }
        let pack = packagingCost(product: p, materials: materials, unitCostOf: unitCostOf)
        let siparis = packagingCost(product: p, materials: materials, unitCostOf: unitCostOf,
                                    perOrder: true)
        return CostBreakdown(ownLines: own, components: comps, packaging: pack,
                             ownFromPurchases: alimdan, orderPackaging: siparis)
    }
}
