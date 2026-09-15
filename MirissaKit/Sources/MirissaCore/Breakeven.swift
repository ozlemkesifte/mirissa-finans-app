import Foundation

/// Hesabın neden yapılamadığını ya da neden yaklaşık olduğunu anlatan uyarılar.
public enum BreakevenIssue: String, Sendable, Hashable, Identifiable {
    case satisYok
    case siparisYok
    case katkiNegatif
    case sabitGiderYok
    case urunMaliyetiYok
    case siparisSayisiTahmini
    case gelecekAy

    public var id: String { rawValue }

    public var message: String {
        switch self {
        case .satisYok:
            return "Bu ay henüz satış girilmedi. Satış ekleyince başa baş noktası hesaplanır."
        case .siparisYok:
            return "Sipariş sayısı sıfır görünüyor. Satışlar ekranından kanalın sipariş sayısını gir."
        case .katkiNegatif:
            return "Sipariş başına kazanç şu an eksi. Bu fiyat ve maliyetlerle satış arttıkça zarar da artar — fiyat, kargo veya ürün maliyetine bakmak gerekiyor."
        case .sabitGiderYok:
            return "Sabit gider girilmemiş. Muhasebeci, ajans gibi aylık giderleri ekleyince başa baş noktası gerçekçi olur."
        case .urunMaliyetiYok:
            return "Ürün maliyetleri girilmemiş. Ürün & Stok ekranından üretim maliyetini girersen kâr hesabı doğru olur."
        case .siparisSayisiTahmini:
            return "Sipariş sayısı girilmediği için satılan adetten tahmin edildi. Kanal kartından gerçek sipariş sayısını girersen daha doğru olur."
        case .gelecekAy:
            return "Bu ay henüz başlamadı."
        }
    }

    /// Hesabı tamamen imkânsız kılan sorunlar
    public var isBlocking: Bool {
        switch self {
        case .satisYok, .siparisYok, .katkiNegatif, .gelecekAy: return true
        case .sabitGiderYok, .urunMaliyetiYok, .siparisSayisiTahmini: return false
        }
    }
}

/// Bir kâr hedefi için gereken tempo.
public struct GoalLine: Hashable, Sendable, Identifiable {
    public var targetProfit: Kurus
    public var isCustom: Bool
    /// Hedefe ulaşmak için ayın tamamında gereken sipariş
    public var orders: Int
    /// Gereken yaklaşık ürün adedi
    public var products: Double
    /// Gereken yaklaşık ciro
    public var revenue: Kurus
    /// Bugünden sonra gereken sipariş
    public var remainingOrders: Int
    /// Kalan günlerde günde kaç sipariş
    public var dailyOrders: Int
    /// Mevcut tempoyla bu hedefe ulaşılır mı
    public var onTrack: Bool
    public var alreadyReached: Bool

    public var id: String { "\(targetProfit)-\(isCustom)" }
}

public struct Breakeven: Hashable, Sendable {
    public var month: MonthKey
    public var isCurrentMonth: Bool
    public var isPast: Bool

    public var daysInMonth: Int
    public var elapsedDays: Int
    public var remainingDays: Int

    // Şu ana kadar
    public var ordersSoFar: Int
    public var unitsSoFar: Double
    public var netSalesSoFar: Kurus
    public var contribution: Kurus
    public var fixedCosts: Kurus
    public var profitSoFar: Kurus
    public var cashOut: Kurus

    // Sipariş başına ortalamalar (kuruş / adet)
    public var contributionPerOrder: Double
    public var revenuePerOrder: Double
    public var unitsPerOrder: Double

    // Başa baş
    public var breakevenOrders: Int?
    public var ordersToBreakeven: Int?
    public var dailyOrdersToBreakeven: Int?
    public var reachedBreakeven: Bool

    // Ay sonu tahmini
    public var projectedOrders: Int?
    public var projectedRevenue: Kurus?
    public var projectedProfit: Kurus?

    public var goals: [GoalLine]
    public var issues: [BreakevenIssue]

    /// Başa baş ve hedefler hesaplanabildi mi
    public var canCompute: Bool { breakevenOrders != nil }
    public var blocking: BreakevenIssue? { issues.first { $0.isBlocking } }
    public var notes: [BreakevenIssue] { issues.filter { !$0.isBlocking } }

    /// Tahmin cümlelerinde kuruş göstermeyelim — bunlar zaten yaklaşık rakamlar
    static func tam(_ k: Kurus) -> String {
        Money.format(Money.roundHalfAwayFromZero(Double(k) / 100) * 100)
    }

    /// Yaklaşık rakamları bine yuvarlar — hedef cirosu gibi tahminlerde okunaklı olsun
    static func yuvarla(_ kurus: Double) -> Kurus {
        let tl = kurus / 100
        guard abs(tl) >= 10_000 else { return Money.roundHalfAwayFromZero(kurus) }
        return Money.roundHalfAwayFromZero((tl / 1000).rounded() * 1000) * 100
    }

    /// Kendi hedefine göre önde mi geride mi
    public var customGoalSentence: String? {
        guard let g = goals.first(where: { $0.isCustom }), let p = projectedProfit else { return nil }
        let fark = p - g.targetProfit
        let hedef = Money.format(g.targetProfit)
        if isPast {
            return fark >= 0
                ? "\(hedef) hedefi yaklaşık \(Breakeven.tam(fark)) aşıldı."
                : "\(hedef) hedefinin yaklaşık \(Breakeven.tam(-fark)) gerisinde kalındı."
        }
        return fark >= 0
            ? "Mevcut tempoyla \(hedef) hedefini yaklaşık \(Breakeven.tam(fark)) aşıyorsun."
            : "Mevcut tempoyla \(hedef) hedefinin yaklaşık \(Breakeven.tam(-fark)) gerisinde kalıyorsun."
    }

    /// "Mevcut tempoyla ay sonunda yaklaşık 42.000 TL kâr görünüyorsun."
    public var projectionSentence: String? {
        guard let p = projectedProfit else { return nil }
        if isPast {
            return p < 0
                ? "Bu ay yaklaşık \(Breakeven.tam(-p)) zarar edildi."
                : "Bu ay yaklaşık \(Breakeven.tam(p)) kâr edildi."
        }
        return p < 0
            ? "Mevcut tempoyla ay sonunda yaklaşık \(Breakeven.tam(-p)) zarar görünüyorsun."
            : "Mevcut tempoyla ay sonunda yaklaşık \(Breakeven.tam(p)) kâr görünüyorsun."
    }
}

public extension Engine {

    /// Varsayılan kâr hedefleri
    static let defaultGoals: [Kurus] = [
        Money.fromTL(25_000), Money.fromTL(50_000), Money.fromTL(100_000),
    ]

    /// Başa baş noktası ve kâr hedefleri.
    ///
    /// Sipariş başına kazanç, o ayın **gerçek kanal ve ürün karışımından**
    /// hesaplanır — bütün siparişler aynı kârlılıktaymış gibi varsayılmaz.
    /// Stok alımları kâr hesabına girmez (satıldıkça maliyet olur); ödenen
    /// tutar ayrıca "nakit çıkışı" olarak taşınır.
    func breakeven(
        month: MonthKey,
        today: DateKey = Dates.today(),
        goalTargets: [Kurus]? = nil
    ) -> Breakeven {
        let r = companyMonth(month)
        let thisMonth = Dates.month(of: today)
        let isCurrent = month == thisMonth
        let isPast = month < thisMonth
        let days = Dates.daysInMonth(year: Dates.year(of: month), month: Dates.monthNumber(of: month))

        let elapsed: Int
        let remaining: Int
        if isCurrent {
            elapsed = min(max(Dates.day(of: today), 1), days)
            remaining = days - elapsed + 1      // bugün de sayılır
        } else if isPast {
            elapsed = days
            remaining = 0
        } else {
            elapsed = 0
            remaining = days
        }

        let orders = r.orders
        let units = r.units
        let contribution = r.toplamKatki
        let fixed = r.toplamSabitGider

        var out = Breakeven(
            month: month,
            isCurrentMonth: isCurrent,
            isPast: isPast,
            daysInMonth: days,
            elapsedDays: elapsed,
            remainingDays: remaining,
            ordersSoFar: orders,
            unitsSoFar: units,
            netSalesSoFar: r.gercekCiro,
            contribution: contribution,
            fixedCosts: fixed,
            profitSoFar: r.gercekKar,
            cashOut: r.nakitCikisi,
            contributionPerOrder: 0,
            revenuePerOrder: 0,
            unitsPerOrder: 0,
            breakevenOrders: nil,
            ordersToBreakeven: nil,
            dailyOrdersToBreakeven: nil,
            reachedBreakeven: r.gercekKar >= 0 && orders > 0,
            projectedOrders: nil,
            projectedRevenue: nil,
            projectedProfit: nil,
            goals: [],
            issues: []
        )

        // --- Eksik veri kontrolü ---
        if !isCurrent && !isPast { out.issues.append(.gelecekAy); return out }
        if r.gercekCiro == 0 && orders == 0 { out.issues.append(.satisYok); return out }
        if orders <= 0 { out.issues.append(.siparisYok); return out }

        if r.channels.contains(where: { !$0.isEmpty && $0.ordersIsEstimate }) {
            out.issues.append(.siparisSayisiTahmini)
        }
        if fixed == 0 { out.issues.append(.sabitGiderYok) }
        if satilanUrunlerinMaliyetiGirilmemis(month: month) { out.issues.append(.urunMaliyetiYok) }

        let cpo = Double(contribution) / Double(orders)
        out.contributionPerOrder = cpo
        out.revenuePerOrder = Double(r.gercekCiro) / Double(orders)
        out.unitsPerOrder = units / Double(orders)

        // --- Ay sonu tahmini (katkı negatifken de anlamlı) ---
        if elapsed > 0 {
            let perDay = Double(orders) / Double(elapsed)
            let projected = isPast ? orders : Int((perDay * Double(days)).rounded())
            out.projectedOrders = projected
            out.projectedRevenue = Money.roundHalfAwayFromZero(out.revenuePerOrder * Double(projected))
            out.projectedProfit = Money.roundHalfAwayFromZero(cpo * Double(projected)) - fixed
        }

        guard cpo > 0 else { out.issues.append(.katkiNegatif); return out }

        // --- Başa baş ---
        let be = ordersNeeded(forProfit: 0, fixed: fixed, perOrder: cpo)
        out.breakevenOrders = be
        if let be {
            out.ordersToBreakeven = max(be - orders, 0)
            out.dailyOrdersToBreakeven = remaining > 0
                ? Int(ceil(Double(max(be - orders, 0)) / Double(remaining)))
                : nil
            out.reachedBreakeven = orders >= be
        }

        // --- Kâr hedefleri ---
        var targets = (goalTargets ?? Engine.defaultGoals).filter { $0 > 0 }
        let custom = state.settings.profitGoal(for: month)
        if let custom, custom > 0 { targets.append(custom) }
        targets = Array(Set(targets)).sorted()

        out.goals = targets.compactMap { t in
            guard let need = ordersNeeded(forProfit: t, fixed: fixed, perOrder: cpo) else { return nil }
            let kalan = max(need - orders, 0)
            return GoalLine(
                targetProfit: t,
                isCustom: custom == t,
                orders: need,
                products: Double(need) * out.unitsPerOrder,
                revenue: Breakeven.yuvarla(out.revenuePerOrder * Double(need)),
                remainingOrders: kalan,
                dailyOrders: remaining > 0 ? Int(ceil(Double(kalan) / Double(remaining))) : 0,
                onTrack: (out.projectedOrders ?? 0) >= need,
                alreadyReached: orders >= need
            )
        }
        return out
    }

    /// Hedef kâr için gereken sipariş sayısı. Ulaşılamayacak kadar büyükse `nil`.
    private func ordersNeeded(forProfit profit: Kurus, fixed: Kurus, perOrder: Double) -> Int? {
        guard perOrder > 0 else { return nil }
        let needed = (Double(fixed) + Double(profit)) / perOrder
        guard needed.isFinite, needed < 5_000_000 else { return nil }
        return Int(ceil(max(needed, 0)))
    }

    /// O ay satılan ürünlerden en az birinin maliyeti hiç girilmemiş mi
    private func satilanUrunlerinMaliyetiGirilmemis(month: MonthKey) -> Bool {
        let satilan = Set(state.sales.filter { $0.month == month }.map(\.productId))
        guard !satilan.isEmpty else { return false }
        return satilan.contains { cost(of: $0, asOf: Dates.monthEnd(month)).total == 0 }
    }
}
