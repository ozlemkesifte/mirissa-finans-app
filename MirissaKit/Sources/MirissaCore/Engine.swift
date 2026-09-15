import Foundation

/// Tüm türetilmiş hesapları üreten motor.
///
/// Hiçbir sonuç saklanmaz; her şey `AppState`'ten yeniden hesaplanır.
/// Bir kayıt değiştiğinde yeni bir `Engine` kurulur ve bütün ekranlar
/// kendiliğinden doğru rakamı gösterir. Katman katman önbellekleme
/// sayesinde bu, tek bir karede biter.
public final class Engine {
    public let state: AppState

    public private(set) lazy var productsById: [Id: Product] =
        Dictionary(state.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    public private(set) lazy var materialsById: [Id: StockMaterial] =
        Dictionary(state.materials.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public private(set) lazy var movements: [Movement] = Movements.all(state)
    public private(set) lazy var ledger: LedgerResult = Ledger.fold(movements)

    /// Kalem başına (tarih, birim maliyet) geçmişi — geçmişe dönük maliyet için
    private lazy var costHistory: [Id: [(date: DateKey, cost: Double)]] = {
        var out: [Id: [(DateKey, Double)]] = [:]
        for r in ledger.rows {
            out[r.item.id, default: []].append((r.date, r.unitCostAfter))
        }
        return out
    }()

    private var costCache: [String: CostBreakdown] = [:]
    private var companyCache: [MonthKey: CompanyMonthResult] = [:]
    private var expenseCache: [MonthKey: [ExpenseInstance]] = [:]
    var consumptionCache: [String: ConsumptionRate] = [:]

    public init(_ state: AppState) {
        self.state = state
    }

    // MARK: - Stok

    public func balance(_ item: ItemRef) -> ItemBalance { ledger.balance(item) }

    public func qty(_ item: ItemRef) -> BaseQty { ledger.balance(item).qty }

    public func history(_ item: ItemRef) -> [LedgerRow] {
        ledger.rows(for: item).reversed()
    }

    /// Güncel ağırlıklı ortalama birim maliyet (temel birim başına kuruş)
    public func unitCost(_ item: ItemRef) -> Double { ledger.balance(item).unitCost }

    /// Belirli bir tarihteki birim maliyet. O tarihe kadar hareket yoksa ilk bilinen maliyet.
    public func unitCost(_ item: ItemRef, asOf date: DateKey) -> Double {
        guard let h = costHistory[item.id], !h.isEmpty else { return 0 }
        var lo = 0, hi = h.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if h[mid].date <= date { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found >= 0 ? h[found].cost : h[0].cost
    }

    public var totalStockValue: Kurus {
        ledger.balances.values.reduce(0) { $0 + max($1.value, 0) }
    }

    // MARK: - Maliyet

    /// Ürün maliyeti dökümü. `asOf` verilirse o tarihteki malzeme maliyetleri kullanılır.
    public func cost(of productId: Id, asOf: DateKey? = nil) -> CostBreakdown {
        let key = "\(productId)|\(asOf ?? "now")"
        if let c = costCache[key] { return c }
        let lookup: (Id) -> Double = { [weak self] matId in
            guard let self else { return 0 }
            let ref = ItemRef.material(matId)
            return asOf.map { self.unitCost(ref, asOf: $0) } ?? self.unitCost(ref)
        }
        let b = Costing.breakdown(
            products: productsById, materials: materialsById,
            productId: productId, unitCostOf: lookup
        )
        costCache[key] = b
        return b
    }

    public func hasCycle(_ productId: Id) -> Bool {
        Costing.hasCycle(products: productsById, productId: productId)
    }

    // MARK: - Giderler

    public func expenseInstances(month: MonthKey) -> [ExpenseInstance] {
        if let c = expenseCache[month] { return c }
        let v = Expenses.instances(state, from: month, to: month)
        expenseCache[month] = v
        return v
    }

    public func expenseInstances(from: MonthKey, to: MonthKey) -> [ExpenseInstance] {
        Dates.monthRange(from: from, to: to).flatMap { expenseInstances(month: $0) }
    }

    // MARK: - Kanal kârlılığı

    public func channelResult(channelId: Id, month: MonthKey) -> ChannelMonthResult {
        companyMonth(month).channels.first { $0.channelId == channelId }
            ?? .empty(channelId: channelId, channelName: state.channel(channelId)?.name ?? "Kanal", month: month)
    }

    // MARK: - Şirket

    public func companyMonth(_ month: MonthKey) -> CompanyMonthResult {
        if let c = companyCache[month] { return c }
        let r = computeCompanyMonth(month)
        companyCache[month] = r
        return r
    }

    private func computeCompanyMonth(_ month: MonthKey) -> CompanyMonthResult {
        let asOf = Dates.monthEnd(month)
        let instances = expenseInstances(month: month)
        let salesOfMonth = state.sales.filter { $0.month == month }

        // Giderleri kapsamlarına göre ayır
        var ortakByCat: [ExpenseCategory: Kurus] = [:]
        var channelByCat: [Id: [ExpenseCategory: Kurus]] = [:]
        var stokAlimi: Kurus = 0
        var nakit: Kurus = 0

        for i in instances {
            nakit += i.cashAmount
            if i.capitalized { stokAlimi += i.amount; continue }
            guard i.expenseAmount != 0 else { continue }
            if let ch = i.scope.channelId {
                channelByCat[ch, default: [:]][i.category, default: 0] += i.expenseAmount
            } else {
                ortakByCat[i.category, default: 0] += i.expenseAmount
            }
        }

        var results: [ChannelMonthResult] = []
        for ch in state.channels {
            let rows = salesOfMonth.filter { $0.channelId == ch.id }
            let catBucket = channelByCat[ch.id] ?? [:]
            guard !rows.isEmpty || !catBucket.isEmpty || state.channelMonth(month: month, channelId: ch.id) != nil else {
                continue
            }
            results.append(computeChannel(ch, month: month, asOf: asOf, rows: rows, channelExpenses: catBucket))
        }
        // Satışı olmayan ama tanımlı kanallar da boş kartla görünsün
        for ch in state.activeChannels where !results.contains(where: { $0.channelId == ch.id }) {
            results.append(.empty(channelId: ch.id, channelName: ch.name, month: month))
        }
        results.sort { a, b in
            let ia = state.channels.firstIndex { $0.id == a.channelId } ?? 99
            let ib = state.channels.firstIndex { $0.id == b.channelId } ?? 99
            return ia < ib
        }

        // Platformun kestiği tutarlar da nakit çıkışıdır
        nakit += results.reduce(0) { $0 + $1.channelFees }

        var breakdown = ortakByCat
        for c in results {
            breakdown[.komisyon, default: 0] += c.commission.amount
            breakdown[.kargo, default: 0] += c.shipping.amount + c.serviceFee.amount
            breakdown[.diger, default: 0] += c.otherDeduction.amount
            breakdown[.reklam, default: 0] += c.ads.amount
            breakdown[.urunUretimi, default: 0] += c.productCost
            breakdown[.ambalaj, default: 0] += c.packagingCost
            for (k, v) in c.otherChannelExpenses { breakdown[k, default: 0] += v }
        }
        breakdown = breakdown.filter { $0.value != 0 }

        return CompanyMonthResult(
            month: month,
            channels: results,
            ortakGider: ortakByCat.values.reduce(0, +),
            stokAlimi: stokAlimi,
            nakitCikisi: nakit,
            expenseBreakdown: breakdown
        )
    }

    private func computeChannel(
        _ ch: Channel,
        month: MonthKey,
        asOf: DateKey,
        rows: [SalesEntry],
        channelExpenses: [ExpenseCategory: Kurus]
    ) -> ChannelMonthResult {
        var r = ChannelMonthResult.empty(channelId: ch.id, channelName: ch.name, month: month)
        let cm = state.channelMonth(month: month, channelId: ch.id)

        for e in rows {
            r.grossSales += e.grossSales
            r.discount += e.discount
            r.returnsAmount += e.returnsAmount
            r.units += e.qty
            r.returnedUnits += e.returnsQty
            let b = cost(of: e.productId, asOf: asOf)
            r.productCost += Money.roundHalfAwayFromZero(Double(b.intrinsic) * e.netQty)
            // Ambalaj brüt adet üzerinden gider: iade edilen siparişin kolisi geri gelmez
            r.packagingCost += Money.roundHalfAwayFromZero(Double(b.packaging) * e.qty)
        }
        r.netSales = r.grossSales - r.discount - r.returnsAmount

        if let oc = cm?.orderCount, oc > 0 {
            r.orders = oc
            r.ordersIsEstimate = false
        } else {
            r.orders = Int(max(r.units - r.returnedUnits, 0).rounded())
            r.ordersIsEstimate = true
        }

        let net = Double(max(r.netSales, 0))
        r.commission = figure(cm?.commissionActual, auto: net * ch.commissionPct / 100 + net * ch.paymentPct / 100)
        r.shipping = figure(cm?.shippingActual, auto: Double(ch.shippingPerOrder) * Double(r.orders))
        r.serviceFee = figure(cm?.serviceFeeActual, auto: Double(ch.serviceFeePerOrder) * Double(r.orders))
        r.otherDeduction = figure(
            cm?.otherDeductionActual,
            auto: net * ch.otherDeductionPct / 100 + Double(ch.platformFeeMonthly) + Double(ch.otherDeductionMonthly)
        )
        // Aylık sabit kesintiler sipariş adedinden bağımsızdır; başa baş hesabı
        // için değişken kısımdan ayrı tutulur.
        r.fixedDeduction = min(ch.platformFeeMonthly + ch.otherDeductionMonthly, r.otherDeduction.amount)
        r.ads = figure(cm?.adsActual, auto: Double(channelExpenses[.reklam] ?? 0))

        var others = channelExpenses
        others[.reklam] = nil
        r.otherChannelExpenses = others.filter { $0.value != 0 }
        return r
    }

    private func figure(_ manual: Kurus?, auto: Double) -> Figure {
        if let m = manual { return Figure(m, manual: true) }
        return Figure(Money.roundHalfAwayFromZero(auto))
    }

    // MARK: - Yıl ve trend

    public func year(_ y: Int) -> YearResult {
        YearResult(year: y, months: (1...12).map { companyMonth(Dates.monthKey(y, $0)) })
    }

    public func trend(endingAt month: MonthKey, months n: Int = 6) -> [TrendPoint] {
        let start = Dates.addMonths(month, -(n - 1))
        return Dates.monthRange(from: start, to: month).map {
            let r = companyMonth($0)
            return TrendPoint(month: $0, gelir: r.gercekCiro, gider: r.toplamGider, kar: r.gercekKar)
        }
    }

    public func channelTotals(from: MonthKey, to: MonthKey, channelId: Id) -> ChannelMonthResult {
        let name = state.channel(channelId)?.name ?? "Kanal"
        let list = Dates.monthRange(from: from, to: to).compactMap { m in
            companyMonth(m).channels.first { $0.channelId == channelId }
        }
        return list.aggregated(channelId: channelId, channelName: name, label: to)
    }

    public func companyTotals(from: MonthKey, to: MonthKey) -> CompanyMonthResult {
        let months = Dates.monthRange(from: from, to: to).map { companyMonth($0) }
        var out = CompanyMonthResult.empty(to)
        var byChannel: [Id: [ChannelMonthResult]] = [:]
        for m in months {
            out.ortakGider += m.ortakGider
            out.stokAlimi += m.stokAlimi
            out.nakitCikisi += m.nakitCikisi
            for (k, v) in m.expenseBreakdown { out.expenseBreakdown[k, default: 0] += v }
            for c in m.channels { byChannel[c.channelId, default: []].append(c) }
        }
        out.channels = state.channels.compactMap { ch in
            guard let list = byChannel[ch.id], !list.isEmpty else { return nil }
            return list.aggregated(channelId: ch.id, channelName: ch.name, label: to)
        }
        return out
    }
}
