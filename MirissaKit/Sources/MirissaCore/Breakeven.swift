import Foundation

/// Kartın hangi soruyu cevapladığı.
public enum BreakevenMode: String, Sendable, Hashable {
    /// Ay başı: "bu ay kaç sipariş gerekiyor?"
    case hedef
    /// Ay sonu: "bu ay ne oldu?"
    case gerceklesen
}

/// Hedefin hangi varsayıma dayandığı.
public enum TargetBasis: Hashable, Sendable {
    /// Son tamamlanmış ayın gerçek kanal ve ürün dağılımı
    case gecmisAy(MonthKey)
    /// Kullanıcının girdiği beklenen sipariş profili
    case beklenenDagilim
    /// Ayın kendi gerçek verisi (ay sonu sonucu)
    case ayinKendisi
    case yok

    public var isApproximate: Bool {
        switch self {
        case .gecmisAy, .beklenenDagilim: return true
        case .ayinKendisi, .yok: return false
        }
    }

    public var explanation: String {
        switch self {
        case let .gecmisAy(m):
            return "\(Dates.displayMonth(m)) ayının gerçek kanal ve ürün dağılımına göre hesaplandı. Bu ayın karışımı farklı olursa rakam da değişir."
        case .beklenenDagilim:
            return "Senin girdiğin beklenen sipariş profiline göre hesaplandı. İlk gerçek ay tamamlanınca bu rakam kendiliğinden gerçek verinle güncellenir."
        case .ayinKendisi:
            return "Bu ayın kendi gerçek satışlarına göre hesaplandı."
        case .yok:
            return "Hesaplanamadı."
        }
    }
}

public enum BreakevenIssue: String, Sendable, Hashable, Identifiable {
    case referansYok
    case katkiNegatif
    case sabitGiderYok
    case urunMaliyetiYok
    case ayHenuzBitmedi
    case araDurumIsaretli

    public var id: String { rawValue }

    public var message: String {
        switch self {
        case .referansYok:
            return "Hedef hesaplamak için henüz veri yok. Ya bir ayı tamamla ya da aşağıdan beklenen sipariş profilini gir."
        case .katkiNegatif:
            return "Sipariş başına kazanç eksi görünüyor. Bu fiyat ve maliyetlerle satış arttıkça zarar da artar — fiyat, kargo veya ürün maliyetine bakmak gerekiyor."
        case .sabitGiderYok:
            return "Sabit gider girilmemiş. Muhasebeci, ajans gibi aylık giderleri ekleyince hedef gerçekçi olur."
        case .urunMaliyetiYok:
            return "Ürün maliyetleri girilmemiş. Ürün & Stok ekranından üretim maliyetini girersen hesap doğru olur."
        case .ayHenuzBitmedi:
            return "Bu ay henüz bitmedi. Rakamlar şu ana kadar girdiğin satışları gösteriyor."
        case .araDurumIsaretli:
            return "Girilen satışlar ayın tamamı değil, ara durum olarak işaretlendi."
        }
    }

    public var isBlocking: Bool {
        self == .referansYok || self == .katkiNegatif
    }
}

/// Bir aylık hedef: kaç sipariş, günde ortalama kaç sipariş.
public struct MonthlyTarget: Hashable, Sendable, Identifiable {
    public var label: String
    public var targetProfit: Kurus
    public var isBreakeven: Bool
    public var isCustom: Bool

    /// Ayın tamamında gereken sipariş
    public var orders: Int
    /// Ayın gün sayısına bölünmüş günlük ortalama
    public var dailyOrders: Int
    public var products: Double
    public var revenue: Kurus

    /// Ara durum girilmişse: kalan sipariş ve kalan günlerde günlük ortalama
    public var remainingOrders: Int?
    public var remainingDailyOrders: Int?

    public var id: String { "\(targetProfit)-\(isCustom)" }
}

/// Ay sonunda gerçekleşen sonuç.
public struct ActualResult: Hashable, Sendable {
    public var orders: Int
    public var units: Double
    public var revenue: Kurus
    public var expenses: Kurus
    public var profit: Kurus
    public var marginPct: Double
    public var cashOut: Kurus
    /// Bu ayın gerçek verisine göre başa baş noktası
    public var breakevenOrders: Int?
    /// Başa baş hedefinin ne kadar üzerinde (+) veya altında (−) kalındı
    public var ordersVsBreakeven: Int?
    public var reachedBreakeven: Bool

    public static let bos = ActualResult(
        orders: 0, units: 0, revenue: 0, expenses: 0, profit: 0, marginPct: 0,
        cashOut: 0, breakevenOrders: nil, ordersVsBreakeven: nil, reachedBreakeven: false
    )

    public var summarySentence: String {
        if profit < 0 {
            return "Bu ay yaklaşık \(Money.format(-profit)) zarar edildi."
        }
        return "Bu ay yaklaşık \(Money.format(profit)) kâr edildi."
    }

    public var breakevenSentence: String? {
        guard let fark = ordersVsBreakeven else { return nil }
        if fark == 0 { return "Tam başa baş noktasında kalındı." }
        return fark > 0
            ? "Başa baş hedefinin \(fark) sipariş üzerinde kalındı."
            : "Başa baş hedefinin \(-fark) sipariş altında kalındı."
    }
}

public struct BreakevenPlan: Hashable, Sendable {
    public var month: MonthKey
    public var mode: BreakevenMode
    public var daysInMonth: Int

    public var basis: TargetBasis
    /// Sipariş başına ortalama katkı (kuruş)
    public var contributionPerOrder: Double
    public var revenuePerOrder: Double
    public var unitsPerOrder: Double
    public var fixedCosts: Kurus

    public var targets: [MonthlyTarget]

    /// Ara durum işaretliyse doldurulur
    public var progressAsOf: DateKey?
    public var progressOrders: Int?
    public var remainingDays: Int?

    public var actual: ActualResult?
    public var issues: [BreakevenIssue]

    public var isApproximate: Bool { basis.isApproximate }
    public var blocking: BreakevenIssue? { issues.first { $0.isBlocking } }
    public var notes: [BreakevenIssue] { issues.filter { !$0.isBlocking } }
    public var canCompute: Bool { !targets.isEmpty }
    public var hasProgress: Bool { progressAsOf != nil && progressOrders != nil }
}

public extension Engine {

    static let defaultGoals: [Kurus] = [
        Money.fromTL(25_000), Money.fromTL(50_000), Money.fromTL(100_000),
    ]

    /// Aylık hedef ve ay sonu sonucu.
    ///
    /// Kullanıcıdan günlük satış girişi beklenmez. Ay başında hedef gösterilir;
    /// satışlar girildiğinde gerçekleşen sonuca döner. Hedefler, satış
    /// gerçekleşmesinden bağımsız olarak **son tamamlanmış ayın** gerçek kanal
    /// ve ürün dağılımından hesaplanır ve "yaklaşık" olarak sunulur.
    func plan(month: MonthKey, today: DateKey = Dates.today()) -> BreakevenPlan {
        let thisMonth = Dates.month(of: today)
        let days = Dates.daysInMonth(year: Dates.year(of: month), month: Dates.monthNumber(of: month))
        let r = companyMonth(month)
        let araDurum = state.settings.progressAsOf[month]
        let satisVar = r.orders > 0 || r.gercekCiro != 0

        // Ayın satışları girilmişse ve ara durum işaretlenmemişse: sonuç göster
        let gerceklesen = month < thisMonth || (satisVar && araDurum == nil)

        var plan = BreakevenPlan(
            month: month,
            mode: gerceklesen ? .gerceklesen : .hedef,
            daysInMonth: days,
            basis: .yok,
            contributionPerOrder: 0,
            revenuePerOrder: 0,
            unitsPerOrder: 1,
            fixedCosts: 0,
            targets: [],
            progressAsOf: nil,
            progressOrders: nil,
            remainingDays: nil,
            actual: nil,
            issues: []
        )

        if gerceklesen {
            fillActual(&plan, month: month, result: r, today: today, thisMonth: thisMonth, days: days)
            return plan
        }

        // --- Hedef modu ---
        plan.fixedCosts = plannedFixedCosts(month: month)
        if plan.fixedCosts == 0 { plan.issues.append(.sabitGiderYok) }

        guard let temel = targetBasis(before: month) else {
            plan.issues.append(.referansYok)
            return plan
        }
        plan.basis = temel.basis
        plan.contributionPerOrder = temel.contributionPerOrder
        plan.revenuePerOrder = temel.revenuePerOrder
        plan.unitsPerOrder = temel.unitsPerOrder
        if temel.urunMaliyetiEksik { plan.issues.append(.urunMaliyetiYok) }

        guard temel.contributionPerOrder > 0 else {
            plan.issues.append(.katkiNegatif)
            return plan
        }

        if let d = araDurum {
            plan.progressAsOf = d
            plan.progressOrders = r.orders
            let gecen = min(max(Dates.day(of: d), 0), days)
            plan.remainingDays = max(days - gecen, 0)
            plan.issues.append(.araDurumIsaretli)
        }

        plan.targets = buildTargets(plan: plan, month: month, days: days)
        return plan
    }

    // MARK: - Gerçekleşen

    private func fillActual(
        _ plan: inout BreakevenPlan,
        month: MonthKey,
        result r: CompanyMonthResult,
        today: DateKey,
        thisMonth: MonthKey,
        days: Int
    ) {
        plan.basis = .ayinKendisi
        plan.fixedCosts = r.toplamSabitGider

        var actual = ActualResult(
            orders: r.orders,
            units: r.units,
            revenue: r.gercekCiro,
            expenses: r.toplamGider,
            profit: r.gercekKar,
            marginPct: r.karMarjiPct,
            cashOut: r.nakitCikisi,
            breakevenOrders: nil,
            ordersVsBreakeven: nil,
            reachedBreakeven: r.gercekKar >= 0
        )

        if r.orders > 0 {
            let cpo = Double(r.toplamKatki) / Double(r.orders)
            plan.contributionPerOrder = cpo
            plan.revenuePerOrder = Double(r.gercekCiro) / Double(r.orders)
            plan.unitsPerOrder = r.units / Double(r.orders)
            if cpo > 0, let be = ordersNeeded(forProfit: 0, fixed: r.toplamSabitGider, perOrder: cpo) {
                actual.breakevenOrders = be
                actual.ordersVsBreakeven = r.orders - be
            } else if cpo <= 0 {
                plan.issues.append(.katkiNegatif)
            }
        }

        if month == thisMonth { plan.issues.append(.ayHenuzBitmedi) }
        if satilanUrunlerinMaliyetiGirilmemis(month: month) { plan.issues.append(.urunMaliyetiYok) }
        plan.actual = actual
    }

    // MARK: - Hedefler

    private func buildTargets(plan: BreakevenPlan, month: MonthKey, days: Int) -> [MonthlyTarget] {
        var hedefler: [(String, Kurus, Bool, Bool)] = [("Başa baş hedefi", 0, true, false)]
        let ozel = state.settings.profitGoal(for: month)
        for g in Engine.defaultGoals where g > 0 {
            hedefler.append(("\(Money.format(g)) kâr hedefi", g, false, false))
        }
        if let ozel, ozel > 0, !Engine.defaultGoals.contains(ozel) {
            hedefler.append(("\(Money.format(ozel)) kâr hedefi", ozel, false, true))
        } else if let ozel, ozel > 0 {
            hedefler = hedefler.map { $0.1 == ozel ? ($0.0, $0.1, $0.2, true) : $0 }
        }
        hedefler.sort { $0.1 < $1.1 }

        return hedefler.compactMap { ad, kar, basaBas, ozelMi in
            guard let need = ordersNeeded(
                forProfit: kar, fixed: plan.fixedCosts, perOrder: plan.contributionPerOrder
            ) else { return nil }

            var t = MonthlyTarget(
                label: ad,
                targetProfit: kar,
                isBreakeven: basaBas,
                isCustom: ozelMi,
                orders: need,
                dailyOrders: days > 0 ? Int(ceil(Double(need) / Double(days))) : need,
                products: Double(need) * plan.unitsPerOrder,
                revenue: BreakevenPlan.yuvarla(plan.revenuePerOrder * Double(need)),
                remainingOrders: nil,
                remainingDailyOrders: nil
            )
            if let girilen = plan.progressOrders, let kalanGun = plan.remainingDays {
                let kalan = max(need - girilen, 0)
                t.remainingOrders = kalan
                t.remainingDailyOrders = kalanGun > 0 ? Int(ceil(Double(kalan) / Double(kalanGun))) : nil
            }
            return t
        }
    }

    // MARK: - Varsayım kaynağı

    struct TargetBasisResult {
        var basis: TargetBasis
        var contributionPerOrder: Double
        var revenuePerOrder: Double
        var unitsPerOrder: Double
        var urunMaliyetiEksik: Bool
    }

    /// Verilen aydan önceki son tamamlanmış ayın gerçek dağılımı;
    /// yoksa kullanıcının girdiği beklenen profil.
    func targetBasis(before month: MonthKey) -> TargetBasisResult? {
        for geri in 1...12 {
            let m = Dates.addMonths(month, -geri)
            let r = companyMonth(m)
            guard r.orders > 0, r.gercekCiro > 0 else { continue }
            return TargetBasisResult(
                basis: .gecmisAy(m),
                contributionPerOrder: Double(r.toplamKatki) / Double(r.orders),
                revenuePerOrder: Double(r.gercekCiro) / Double(r.orders),
                unitsPerOrder: r.units / Double(r.orders),
                urunMaliyetiEksik: satilanUrunlerinMaliyetiGirilmemis(month: m)
            )
        }
        return expectedMixBasis()
    }

    /// Kullanıcının girdiği beklenen sipariş profilinden katkı hesaplar.
    func expectedMixBasis() -> TargetBasisResult? {
        guard let mix = state.settings.expectedMix,
              let ch = state.channel(mix.channelId),
              state.product(mix.productId) != nil,
              mix.averageOrderValue > 0 else { return nil }

        let net = Double(mix.averageOrderValue)
        let b = cost(of: mix.productId)
        let komisyon = net * (ch.commissionPct + ch.paymentPct) / 100
        let digerOran = net * ch.otherDeductionPct / 100
        let urun = Double(b.intrinsic) * mix.unitsPerOrder
        let ambalaj = Double(b.packaging) * mix.unitsPerOrder
        let katki = net - komisyon - digerOran
            - Double(ch.shippingPerOrder) - Double(ch.serviceFeePerOrder)
            - urun - ambalaj

        return TargetBasisResult(
            basis: .beklenenDagilim,
            contributionPerOrder: katki,
            revenuePerOrder: net,
            unitsPerOrder: mix.unitsPerOrder,
            urunMaliyetiEksik: b.total == 0
        )
    }

    /// Hedef ayın sabit giderleri. Satış girilmemiş aylarda bile
    /// kanalların aylık sabit ücretleri hesaba katılır.
    func plannedFixedCosts(month: MonthKey) -> Kurus {
        let r = companyMonth(month)
        var toplam = r.toplamSabitGider
        for ch in state.activeChannels {
            let sonuc = r.channels.first { $0.channelId == ch.id }
            if sonuc == nil || sonuc!.isEmpty {
                toplam += ch.platformFeeMonthly + ch.otherDeductionMonthly
            }
        }
        return toplam
    }

    private func ordersNeeded(forProfit profit: Kurus, fixed: Kurus, perOrder: Double) -> Int? {
        guard perOrder > 0 else { return nil }
        let needed = (Double(fixed) + Double(profit)) / perOrder
        guard needed.isFinite, needed < 5_000_000 else { return nil }
        return Int(ceil(max(needed, 0)))
    }

    private func satilanUrunlerinMaliyetiGirilmemis(month: MonthKey) -> Bool {
        let satilan = Set(state.sales.filter { $0.month == month }.map(\.productId))
        guard !satilan.isEmpty else { return false }
        return satilan.contains { cost(of: $0, asOf: Dates.monthEnd(month)).total == 0 }
    }
}

public extension BreakevenPlan {
    /// Yaklaşık ciro rakamlarını bine yuvarlar
    static func yuvarla(_ kurus: Double) -> Kurus {
        let tl = kurus / 100
        guard abs(tl) >= 10_000 else { return Money.roundHalfAwayFromZero(kurus) }
        return Money.roundHalfAwayFromZero((tl / 1000).rounded() * 1000) * 100
    }
}
