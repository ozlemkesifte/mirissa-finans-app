import Foundation

public enum StockStatus: String, Sendable, Comparable {
    case negatif, kritik, azaliyor, normal

    public var isProblem: Bool { self != .normal }

    public var displayName: String {
        switch self {
        case .negatif: return "Stok eksiye düştü"
        case .kritik: return "Stok bitmek üzere. Sipariş ver."
        case .azaliyor: return "Stok azalıyor."
        case .normal: return "Yeterli"
        }
    }

    public var shortLabel: String {
        switch self {
        case .negatif: return "EKSİ"
        case .kritik: return "KRİTİK"
        case .azaliyor: return "AZALIYOR"
        case .normal: return "YETERLİ"
        }
    }

    private var rank: Int {
        switch self {
        case .negatif: return 0
        case .kritik: return 1
        case .azaliyor: return 2
        case .normal: return 3
        }
    }

    public static func < (a: StockStatus, b: StockStatus) -> Bool { a.rank < b.rank }
}

public struct ConsumptionRate: Hashable, Sendable {
    /// Sipariş başına ortalama tüketim (temel birim)
    public var perOrder: Double
    /// Ay başına ortalama tüketim (temel birim)
    public var perMonth: Double
    /// Hesapta kullanılan ay sayısı
    public var windowMonths: Int
    public var hasData: Bool { perOrder > 0 || perMonth > 0 }

    public static let none = ConsumptionRate(perOrder: 0, perMonth: 0, windowMonths: 0)
}

public struct StockAlert: Identifiable, Hashable, Sendable {
    public var item: ItemRef
    public var name: String
    public var status: StockStatus
    public var qty: BaseQty
    public var baseUnit: UnitCode
    public var ordersLeft: Int?
    public var id: String { item.id }

    public var qtyText: String { Units.formatQty(qty, baseUnit: baseUnit) }
}

public extension Engine {
    // MARK: - Uyarı seviyeleri

    func status(_ item: ItemRef) -> StockStatus {
        let b = ledger.balance(item)
        if b.qty < 0 { return .negatif }
        let (minQ, critQ) = thresholds(item)
        if let c = critQ, b.qty <= c { return .kritik }
        if let m = minQ, b.qty <= m { return .azaliyor }
        return .normal
    }

    func thresholds(_ item: ItemRef) -> (min: BaseQty?, critical: BaseQty?) {
        switch item.kind {
        case .material:
            let m = materialsById[item.id]
            return (m?.minQty, m?.criticalQty)
        case .product:
            let p = productsById[item.id]
            return (p?.minQty, p?.criticalQty)
        }
    }

    /// Sadece sorunlu stoklar — ana sayfa uyarı alanı için.
    /// Her şey yolundaysa boş döner ve ekran gereksiz bilgiyle dolmaz.
    func stockAlerts(endingAt month: MonthKey? = nil) -> [StockAlert] {
        var out: [StockAlert] = []
        for m in state.activeMaterials {
            let ref = ItemRef.material(m.id)
            let st = status(ref)
            guard st.isProblem else { continue }
            out.append(StockAlert(
                item: ref, name: m.name, status: st,
                qty: qty(ref), baseUnit: m.baseUnit,
                ordersLeft: ordersLeft(ref, endingAt: month)
            ))
        }
        for p in state.activeProducts where p.tracksOwnStock {
            let ref = ItemRef.product(p.id)
            let st = status(ref)
            guard st.isProblem else { continue }
            out.append(StockAlert(
                item: ref, name: p.name, status: st,
                qty: qty(ref), baseUnit: .adet,
                ordersLeft: ordersLeft(ref, endingAt: month)
            ))
        }
        out.sort { a, b in
            a.status == b.status ? a.name < b.name : a.status < b.status
        }
        return out
    }

    // MARK: - Tüketim hızı ve "kaç siparişlik kaldı"

    /// Son aylardaki gerçek satış tüketiminden ortalama çıkarır.
    /// Fire / numune / sayım farkı bu orana katılmaz — yoksa oran şişer.
    func consumptionRate(_ item: ItemRef, endingAt month: MonthKey? = nil,
                         bugun: DateKey? = nil) -> ConsumptionRate {
        let buAy = Dates.month(of: bugun ?? Dates.today())
        let istenen = month ?? buAy
        // Önce istek anahtarıyla önbelleğe bakılır: kalemin hareketleri yalnızca ilk seferde taranır
        let istekAnahtari = "\(item.id)|\(istenen)|\(buAy)"
        if let c = consumptionCache[istekAnahtari] { return c }
        let satirlar = ledger.rows(for: item)
        // Kalem ilk kez ne zaman göründü: yeni ürünün oranı, henüz yokken geçen
        // aylarla sulandırılmasın
        let ilkAy = satirlar.map { Dates.month(of: $0.date) }.min()
        // Bitmemiş ay tam ay sayılmaz (ayın 1'inde oran 3'te 2'ye düşerdi): son biten aya kadar
        // bakılır. Kalem bu ay ilk kez satıldıysa elde yalnızca bu ay vardır, o kullanılır.
        let ilkSatisAy = satirlar.filter { $0.movement.source == .sales && $0.kind == .satis }
            .map { Dates.month(of: $0.date) }.min()
        let end = istenen >= buAy && (ilkSatisAy ?? istenen) < buAy ? Dates.addMonths(buAy, -1) : istenen
        let key = "\(item.id)|\(end)"
        if let c = consumptionCache[key] { consumptionCache[istekAnahtari] = c; return c }

        var result = ConsumptionRate.none
        for window in [state.settings.consumptionWindowMonths, 6, 12] where window > 0 {
            let start = max(Dates.addMonths(end, -(window - 1)), ilkAy ?? end)
            guard start <= end else { continue }
            let months = Set(Dates.monthRange(from: start, to: end))
            // Satışın net tüketimi: stoğa geri dönen iadeler düşülür.
            // Fire, numune ve sayım farkı katılmaz — yoksa oran şişer.
            var used = 0.0
            for r in satirlar
            where r.movement.source == .sales && (r.kind == .satis || r.kind == .iade)
                && months.contains(Dates.month(of: r.date)) {
                used += -r.delta
            }
            guard used > 0 else { continue }
            var orders = 0
            for m in months { orders += companyMonth(m).orders }
            result = ConsumptionRate(
                perOrder: orders > 0 ? used / Double(orders) : 0,
                perMonth: used / Double(months.count),
                windowMonths: months.count
            )
            break
        }
        consumptionCache[key] = result
        consumptionCache[istekAnahtari] = result
        return result
    }

    /// Eldeki stokla yaklaşık kaç sipariş daha karşılanır. Veri yoksa `nil`.
    func ordersLeft(_ item: ItemRef, endingAt month: MonthKey? = nil) -> Int? {
        let rate = consumptionRate(item, endingAt: month)
        guard rate.perOrder > 0 else { return nil }
        let q = qty(item)
        guard q > 0 else { return 0 }
        // Küçük pay: 35 ÷ (700/600) = 29,99999… gibi kayan nokta artıkları bir eksik saymasın
        return Int((q / rate.perOrder + 1e-9).rounded(.down))
    }

    /// Eldeki bileşen stoğuyla bu setten en fazla kaç adet hazırlanabilir.
    /// Set değilse veya bileşeni yoksa `nil`.
    /// Setin kendi stoğu tutulmaz; sayı her zaman bileşenlerden türetilir.
    func buildable(_ productId: Id) -> Int? {
        let byId = Dictionary(uniqueKeysWithValues: state.products.map { ($0.id, $0) })
        guard let p = byId[productId], p.isBundle, !p.components.isEmpty else { return nil }
        let leaves = Costing.explodeToLeafProducts(products: byId, productId: productId, qty: 1)
        var enAz: Int?
        for (leafId, mult) in leaves where mult > 0 {
            // Stok tutmayan (boş set) yaprak sınırlamaz; kayan nokta artığına küçük pay
            guard byId[leafId]?.tracksOwnStock == true else { continue }
            let adet = Int((qty(.product(leafId)) / mult + 1e-9).rounded(.down))
            enAz = min(enAz ?? adet, adet)
        }
        return enAz.map { max(0, $0) }
    }

    /// Setin hazırlanmasını sınırlayan bileşen — "en az hangisi yetiyor".
    func buildableBottleneck(_ productId: Id) -> (productId: Id, adet: Int)? {
        let byId = Dictionary(uniqueKeysWithValues: state.products.map { ($0.id, $0) })
        guard let p = byId[productId], p.isBundle, !p.components.isEmpty else { return nil }
        let leaves = Costing.explodeToLeafProducts(products: byId, productId: productId, qty: 1)
        var en: (Id, Int)?
        for (leafId, mult) in leaves where mult > 0 {
            // Stok tutmayan (boş set) yaprak sınırlamaz; kayan nokta artığına küçük pay
            guard byId[leafId]?.tracksOwnStock == true else { continue }
            let adet = Int((qty(.product(leafId)) / mult + 1e-9).rounded(.down))
            if en == nil || adet < en!.1 { en = (leafId, adet) }
        }
        return en.map { ($0.0, max(0, $0.1)) }
    }

    /// Eldeki stok yaklaşık kaç ay yeter. Veri yoksa `nil`.
    func monthsLeft(_ item: ItemRef, endingAt month: MonthKey? = nil) -> Double? {
        let rate = consumptionRate(item, endingAt: month)
        guard rate.perMonth > 0 else { return nil }
        let q = qty(item)
        guard q > 0 else { return 0 }
        return q / rate.perMonth
    }
}
