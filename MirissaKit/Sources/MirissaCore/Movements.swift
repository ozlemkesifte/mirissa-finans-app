import Foundation

public enum MovementKind: String, Codable, Sendable {
    case opening, purchase, iade, satis, duzeltme, sayim

    /// Aynı gün içindeki kesin sıralama. Sayım her zaman en sonda:
    /// gün sonunda gözlenen gerçek odur.
    public var seq: Int {
        switch self {
        case .opening: return 0
        case .purchase: return 1
        case .iade: return 2
        case .satis: return 3
        case .duzeltme: return 4
        case .sayim: return 5
        }
    }
}

public enum MovementSource: String, Codable, Sendable {
    case opening, purchase, adjustment, count, sales
}

public struct Movement: Identifiable, Hashable, Sendable {
    public var id: String
    public var item: ItemRef
    /// Kullanıcıya gösterilen tarih
    public var date: DateKey
    /// Sıralamada kullanılan tarih. Sayımlar ayın sonuna alınır:
    /// aylık satış toplu girildiği için, ay içinde yapılan bir sayımın
    /// ardından o ayın satışlarının tekrar düşülmesi yanlış olurdu.
    public var sortDate: DateKey?
    public var kind: MovementKind
    /// Temel birim cinsinden işaretli değişim. `sayim` için katlama sırasında doldurulur.
    public var delta: BaseQty
    /// Sadece `sayim`: stoğun sabitleneceği mutlak değer
    public var absoluteTo: BaseQty?
    /// Stoğa giren toplam maliyet (alım / açılış)
    public var inCost: Kurus?
    public var source: MovementSource
    public var sourceId: Id
    public var reason: AdjustReason?
    public var label: String

    public var effectiveDate: DateKey { sortDate ?? date }

    /// (tarih, tür, kaynak, kalem) ile tam belirli sıralama
    public func isBefore(_ o: Movement) -> Bool {
        if effectiveDate != o.effectiveDate { return effectiveDate < o.effectiveDate }
        if kind.seq != o.kind.seq { return kind.seq < o.kind.seq }
        if sourceId != o.sourceId { return sourceId < o.sourceId }
        return item.id < o.item.id
    }
}

public enum Movements {
    /// Tüm kaynakları tek bir sıralı hareket akışına dönüştürür.
    public static func all(_ s: AppState) -> [Movement] {
        var out: [Movement] = []
        out.reserveCapacity(s.purchases.count + s.adjustments.count + s.counts.count + s.sales.count * 6)
        out += opening(s)
        out += fromPurchases(s)
        out += fromAdjustments(s)
        out += fromCounts(s)
        out += fromSales(s)
        out.sort { $0.isBefore($1) }
        return out
    }

    // MARK: Açılış stokları

    static func opening(_ s: AppState) -> [Movement] {
        var out: [Movement] = []
        for m in s.materials {
            guard let q = m.openingQty, q != 0 else { continue }
            out.append(Movement(
                id: "mv:opening:\(m.id)",
                item: .material(m.id),
                date: m.openingDate ?? "1970-01-01",
                sortDate: nil,
                kind: .opening,
                delta: q,
                absoluteTo: nil,
                inCost: Money.roundHalfAwayFromZero(Double(m.openingUnitCost ?? 0) * q),
                source: .opening,
                sourceId: m.id,
                reason: nil,
                label: "Başlangıç stoğu"
            ))
        }
        for p in s.products {
            guard let q = p.openingQty, q != 0 else { continue }
            out.append(Movement(
                id: "mv:opening:\(p.id)",
                item: .product(p.id),
                date: p.openingDate ?? "1970-01-01",
                sortDate: nil,
                kind: .opening,
                delta: q,
                absoluteTo: nil,
                inCost: Money.roundHalfAwayFromZero(Double(p.openingUnitCost ?? 0) * q),
                source: .opening,
                sourceId: p.id,
                reason: nil,
                label: "Başlangıç stoğu"
            ))
        }
        return out
    }

    // MARK: Alımlar

    static func fromPurchases(_ s: AppState) -> [Movement] {
        s.purchases.compactMap { p in
            guard s.itemExists(p.item) else { return nil }
            guard let base = Units.toBaseOrNil(
                qty: p.qty, unit: p.unit,
                baseUnit: s.itemBaseUnit(p.item),
                packSizes: s.itemPackSizes(p.item)
            ), base != 0 else { return nil }
            return Movement(
                id: "mv:purchase:\(p.id)",
                item: p.item,
                date: p.date,
                sortDate: nil,
                kind: .purchase,
                delta: base,
                absoluteTo: nil,
                // Stok maliyeti KDV HARİÇ: indirilecek KDV, ödenecek KDV'den
                // mahsup edilir; ürün maliyetine yazılırsa kârlılık yanlış çıkar.
                inCost: p.landedSplit.net,
                source: .purchase,
                sourceId: p.id,
                reason: nil,
                label: "Satın alındı"
            )
        }
    }

    // MARK: Düzeltmeler (fire, kırık, numune...)

    static func fromAdjustments(_ s: AppState) -> [Movement] {
        s.adjustments.compactMap { a in
            guard s.itemExists(a.item) else { return nil }
            guard let base = Units.toBaseOrNil(
                qty: abs(a.qty), unit: a.unit,
                baseUnit: s.itemBaseUnit(a.item),
                packSizes: s.itemPackSizes(a.item)
            ), base != 0 else { return nil }
            return Movement(
                id: "mv:adjustment:\(a.id)",
                item: a.item,
                date: a.date,
                sortDate: nil,
                kind: .duzeltme,
                delta: a.isIncrease ? base : -base,
                absoluteTo: nil,
                inCost: nil,
                source: .adjustment,
                sourceId: a.id,
                reason: a.reason,
                label: a.reason.displayName
            )
        }
    }

    // MARK: Sayımlar

    static func fromCounts(_ s: AppState) -> [Movement] {
        s.counts.compactMap { c in
            guard s.itemExists(c.item) else { return nil }
            guard let base = Units.toBaseOrNil(
                qty: c.countedQty, unit: c.unit,
                baseUnit: s.itemBaseUnit(c.item),
                packSizes: s.itemPackSizes(c.item)
            ) else { return nil }
            return Movement(
                id: "mv:count:\(c.id)",
                item: c.item,
                date: c.date,
                // Sayım, ait olduğu ayın son sözüdür: o ayın satışlarından sonra uygulanır
                sortDate: Dates.monthEnd(Dates.month(of: c.date)),
                kind: .sayim,
                delta: 0,
                absoluteTo: base,
                inCost: nil,
                source: .count,
                sourceId: c.id,
                reason: c.reason,
                label: "Stok sayımı"
            )
        }
    }

    // MARK: Satışlar — ürün açılımı + reçete tüketimi

    /// Aylık satış kaydı ayın **son gününe** tarihlenir: ay içinde alınan
    /// malzemeler, o ayın satışları değerlenmeden önce ortalama maliyete girer.
    static func fromSales(_ s: AppState) -> [Movement] {
        var out: [Movement] = []
        let byId = Dictionary(uniqueKeysWithValues: s.products.map { ($0.id, $0) })

        for e in s.sales {
            guard let sold = byId[e.productId], e.qty != 0 || e.returnsQty != 0 else { continue }
            let date = Dates.monthEnd(e.month)
            let channelName = s.channel(e.channelId)?.name ?? "Satış"

            // 1) Ürün stoğu: set ise bileşenlerine iner
            let leaves = Costing.explodeToLeafProducts(products: byId, productId: e.productId, qty: 1)
            for (leafId, mult) in leaves {
                guard let leaf = byId[leafId], leaf.tracksOwnStock else { continue }
                let grossOut = e.qty * mult
                if grossOut != 0 {
                    out.append(Movement(
                        id: "mv:sales:\(e.id):p:\(leafId)",
                        item: .product(leafId),
                        date: date,
                        sortDate: nil,
                        kind: .satis,
                        delta: -grossOut,
                        absoluteTo: nil,
                        inCost: nil,
                        source: .sales,
                        sourceId: e.id,
                        reason: nil,
                        label: "\(channelName) satışı — \(sold.name)"
                    ))
                }
                // İade her zaman stoğa girer; satılabilir değilse hemen fire olarak
                // çıkar. Net etki aynı, ama geçmişte ne olduğu görünür.
                let backIn = e.returnsQty * mult
                if backIn != 0 {
                    out.append(Movement(
                        id: "mv:sales:\(e.id):r:\(leafId)",
                        item: .product(leafId),
                        date: date,
                        sortDate: nil,
                        kind: .iade,
                        delta: backIn,
                        absoluteTo: nil,
                        inCost: nil,
                        source: .sales,
                        sourceId: e.id,
                        reason: nil,
                        label: "\(channelName) iadesi — \(sold.name)"
                    ))
                    if !e.returnsRestock {
                        out.append(Movement(
                            id: "mv:sales:\(e.id):f:\(leafId)",
                            item: .product(leafId),
                            date: date,
                            sortDate: nil,
                            kind: .duzeltme,
                            delta: -backIn,
                            absoluteTo: nil,
                            inCost: nil,
                            source: .sales,
                            sourceId: e.id,
                            reason: .hasarli,
                            label: "İade hasarlı — fire"
                        ))
                    }
                }
            }

            // 2) Paketleme malzemeleri: SADECE satılan ürünün kendi reçetesi.
            //    (Set satıldığında bileşenlerin kendi kutuları kullanılmaz,
            //     set kutusu kullanılır — bu yüzden bileşen reçeteleri uygulanmaz.)
            //    İade edilse bile koli/patpat geri gelmez: brüt adet üzerinden düşer.
            for line in sold.recipe {
                guard let mat = s.material(line.materialId) else { continue }
                guard let perUnit = Units.toBaseOrNil(
                    qty: line.qty, unit: line.unit,
                    baseUnit: mat.baseUnit, packSizes: mat.packSizes
                ), perUnit != 0 else { continue }
                let total = perUnit * e.qty
                guard total != 0 else { continue }
                out.append(Movement(
                    id: "mv:sales:\(e.id):m:\(line.id)",
                    item: .material(mat.id),
                    date: date,
                    sortDate: nil,
                    kind: .satis,
                    delta: -total,
                    absoluteTo: nil,
                    inCost: nil,
                    source: .sales,
                    sourceId: e.id,
                    reason: nil,
                    label: "\(sold.name) paketlemesinde kullanıldı"
                ))
            }
        }
        return out
    }
}
