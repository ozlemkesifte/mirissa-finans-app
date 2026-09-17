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

    /// Ay → kategori → satış dışında stoktan çıkan malın maliyeti (KDV hariç).
    ///
    /// Alınan mal alım anında gider yazılmaz, stoğa girer; satıldıkça ürün ve
    /// ambalaj maliyeti olarak kâra düşer. Kırılan, kaybolan, numune verilen ya da
    /// sayımda eksik çıkan malın maliyeti de kâra düşmeli — yoksa bu para hiçbir
    /// yerde gider olarak görünmez ve kâr olduğundan yüksek çıkar.
    ///  - Numune, influencer, PR → "Influencer" (pazarlama gideri)
    ///  - Kırık, hasarlı, fire, kayıp, iç kullanım, sayım farkı, diğer → "Fire, kayıp ve sayım farkı"
    ///  - Sayımda fazla çıkan mal bu gideri azaltır.
    ///  - Stok eksideyken yapılan sayım gider/gelir yazmaz: eksi stok kaydı eksik
    ///    bir alım ya da açılış stoğu demektir, gerçek bir kazanç değildir.
    private(set) lazy var stoktanGiderler: [MonthKey: [ExpenseCategory: Kurus]] = {
        var sonDeger: [Id: Kurus] = [:]
        var sonMiktar: [Id: BaseQty] = [:]
        var out: [MonthKey: [ExpenseCategory: Kurus]] = [:]
        for r in ledger.rows {
            let key = r.item.id
            let oncekiDeger = sonDeger[key] ?? 0
            let oncekiMiktar = sonMiktar[key] ?? 0
            sonDeger[key] = r.valueAfter
            sonMiktar[key] = r.balanceAfter
            guard r.kind == .duzeltme || r.kind == .sayim else { continue }
            if r.kind == .sayim, oncekiMiktar < 0 { continue }
            let tutar = oncekiDeger - r.valueAfter
            guard tutar != 0 else { continue }
            let kategori: ExpenseCategory
            switch r.movement.reason {
            case .numune, .influencer, .pr: kategori = .influencer
            default: kategori = .stokKaybi
            }
            out[Dates.month(of: r.date), default: [:]][kategori, default: 0] += tutar
        }
        return out
    }()

    /// Dönemde satış dışında stoktan çıkan malın bir kategoriye düşen maliyeti
    public func stoktanGider(from: MonthKey, to: MonthKey, category: ExpenseCategory) -> Kurus {
        Dates.monthRange(from: from, to: to).reduce(0) { $0 + (stoktanGiderler[$1]?[category] ?? 0) }
    }

    private var costCache: [String: CostBreakdown] = [:]
    private var companyCache: [MonthKey: CompanyMonthResult] = [:]
    private var expenseCache: [MonthKey: [ExpenseInstance]] = [:]
    var consumptionCache: [String: ConsumptionRate] = [:]
    private var vatCache: [MonthKey: VatStatus] = [:]
    var fiyatGuncelCache: [String: CompanyMonthResult?] = [:]

    func vatCacheGet(_ m: MonthKey) -> VatStatus? { vatCache[m] }
    func vatCacheSet(_ m: MonthKey, _ v: VatStatus) { vatCache[m] = v }

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
        let urunAlimi: (Id) -> Double = { [weak self] urunId in
            guard let self else { return 0 }
            let ref = ItemRef.product(urunId)
            return asOf.map { self.unitCost(ref, asOf: $0) } ?? self.unitCost(ref)
        }
        let b = Costing.breakdown(
            products: productsById, materials: materialsById,
            productId: productId, asOf: asOf, unitCostOf: lookup,
            purchasedUnitCostOf: urunAlimi
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

        // Giderleri kapsamlarına göre ayır; sabit/satışa bağlı ayrımı korunur
        var ortakByCat: [ExpenseCategory: Kurus] = [:]
        var ortakDegisken: Kurus = 0
        var channelByCat: [Id: [ExpenseCategory: Kurus]] = [:]
        var channelDegiskenByCat: [Id: [ExpenseCategory: Kurus]] = [:]
        var stokAlimi: Kurus = 0
        var nakit: Kurus = 0
        var giderKdv: Kurus = 0

        for i in instances {
            nakit += i.cashAmount
            giderKdv += i.inputVat
            if i.capitalized { stokAlimi += i.amount; continue }
            guard i.expenseAmount != 0 else { continue }
            if let ch = i.scope.channelId {
                channelByCat[ch, default: [:]][i.category, default: 0] += i.expenseAmount
                if i.behavior == .satisaBagli {
                    channelDegiskenByCat[ch, default: [:]][i.category, default: 0] += i.expenseAmount
                }
            } else {
                ortakByCat[i.category, default: 0] += i.expenseAmount
                if i.behavior == .satisaBagli { ortakDegisken += i.expenseAmount }
            }
        }

        // Satış dışında stoktan çıkan malın maliyeti (nakit çıkışı değildir: parası alımda ödendi)
        for (kategori, tutar) in stoktanGiderler[month] ?? [:] {
            ortakByCat[kategori, default: 0] += tutar
        }

        var results: [ChannelMonthResult] = []
        for ch in state.channels {
            let rows = salesOfMonth.filter { $0.channelId == ch.id }
            let catBucket = channelByCat[ch.id] ?? [:]
            // Satışı olmasa bile aylık sabit ücreti olan kanal o ayın gideridir:
            // mağaza aboneliği satış olmayan ayda da ödenir.
            let ucretVar = !ch.archived && aylikSabitKanalUcreti(ch, month: month) > 0
            guard !rows.isEmpty || !catBucket.isEmpty
                    || state.channelMonth(month: month, channelId: ch.id) != nil
                    || ucretVar else {
                continue
            }
            results.append(computeChannel(
                ch, month: month, asOf: asOf, rows: rows,
                channelExpenses: catBucket,
                channelVariableExpenses: channelDegiskenByCat[ch.id] ?? [:]
            ))
        }
        // Satışı olmayan ama tanımlı kanallar da boş kartla görünsün.
        // Eksik bilgi uyarısı satış olup olmamasından bağımsızdır: kullanıcı
        // "bilmiyorum" dediyse o kanalın hesabı her ay yaklaşıktır.
        for ch in state.activeChannels where !results.contains(where: { $0.channelId == ch.id }) {
            var bos = ChannelMonthResult.empty(channelId: ch.id, channelName: ch.name, month: month)
            bos.eksikBilgiler = ch.rates(on: asOf).eksikler
            results.append(bos)
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
            ortakGiderDegisken: ortakDegisken,
            stokAlimi: stokAlimi,
            nakitCikisi: nakit,
            giderKdv: giderKdv,
            expenseBreakdown: breakdown
        )
    }

    private func computeChannel(
        _ ch: Channel,
        month: MonthKey,
        asOf: DateKey,
        rows: [SalesEntry],
        channelExpenses: [ExpenseCategory: Kurus],
        channelVariableExpenses: [ExpenseCategory: Kurus]
    ) -> ChannelMonthResult {
        var r = ChannelMonthResult.empty(channelId: ch.id, channelName: ch.name, month: month)
        let cm = state.channelMonth(month: month, channelId: ch.id)

        for e in rows {
            // Bütün satış tutarları KDV hariç tutulur: kârlılık net değerler üzerinden.
            let oran = e.resolvedVatRate, dahil = e.resolvedVatIncluded
            r.grossSales += Vat.net(e.grossSales, rate: oran, included: dahil)
            r.discount += Vat.net(e.discount, rate: oran, included: dahil)
            r.returnsAmount += Vat.net(e.returnsAmount, rate: oran, included: dahil)
            // Kesintiler müşterinin ödediği KDV dahil tutar üzerinden alınır.
            // Satış "KDV hariç" girilmişse KDV'si eklenir; aksi halde komisyon eksik çıkar.
            let bolum = e.vatSplit
            r.netSalesIncVat += bolum.net + bolum.vat
            r.outputVat += bolum.vat
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

        // Pazaryeri kesintileri satış fiyatının KDV DAHİL hali üzerinden alınır.
        // Kesinti tutarının kendi KDV'si indirilecek KDV'ye gider, net kısmı gidere.
        let taban = Double(max(r.netSalesIncVat, 0))
        var kesintiKdv: Kurus = 0
        func kesinti(_ manual: Kurus?, auto: Double) -> Figure {
            let ham = manual ?? Money.roundHalfAwayFromZero(auto)
            let bolum = Vat.split(ham, rate: ch.resolvedFeeVatRate, included: ch.resolvedFeesIncludeVat)
            kesintiKdv += bolum.vat
            return Figure(bolum.net, manual: manual != nil)
        }

        // O ayda geçerli oranlar kullanılır: komisyon sonradan değişse bile
        // geçmiş ayın raporu değişmez.
        let oranlar = ch.rates(on: asOf ?? Dates.monthEnd(month))
        r.commission = kesinti(cm?.commissionActual,
                               auto: taban * (oranlar.commissionPct + oranlar.paymentPct) / 100)
        r.shipping = kesinti(cm?.shippingActual,
                             auto: Double(oranlar.shippingPerOrder) * Double(r.orders))
        r.serviceFee = kesinti(cm?.serviceFeeActual,
                               auto: Double(oranlar.serviceFeePerOrder) * Double(r.orders))

        // Kullanıcının kendi eklediği kesintiler. "Bilmiyorum" işaretliler
        // hesaba katılmaz; sonuç yaklaşık olarak işaretlenir.
        var ekDegisken = 0.0
        for f in oranlar.extras where !f.unknown {
            switch f.basis {
            case .yuzde: ekDegisken += taban * f.value / 100
            case .siparisBasi: ekDegisken += f.value * Double(r.orders)
            case .aylikSabit: break   // aylikSabitKanalUcreti içinde
            case .elleAylik: break   // yalnızca elle girilen aylık tutardan gelir
            }
        }
        // Aylık sabit ücret yalnızca kanal başladıktan sonraki aylarda işler.
        // Kanala başlamadan önce girilmiş bir gider (ör. tanıtım reklamı) o aya ücret yazdırmaz.
        let sabitToplam = Double(aylikSabitKanalUcreti(ch, month: month))
        r.otherDeduction = kesinti(
            cm?.otherDeductionActual,
            auto: taban * oranlar.otherDeductionPct / 100 + sabitToplam + ekDegisken
        )
        r.feeVat = kesintiKdv
        r.eksikBilgiler = oranlar.eksikler
        // Aylık sabit kesintiler sipariş adedinden bağımsızdır; başa baş hesabı
        // için değişken kısımdan ayrı tutulur.
        r.fixedDeduction = min(
            Vat.net(Money.roundHalfAwayFromZero(sabitToplam),
                    rate: ch.resolvedFeeVatRate, included: ch.resolvedFeesIncludeVat),
            r.otherDeduction.amount
        )
        let reklamToplam = channelExpenses[.reklam] ?? 0
        let reklamDegisken = channelVariableExpenses[.reklam] ?? 0
        r.ads = figure(cm?.adsActual, auto: Double(reklamToplam))
        // Elle aylık tutar girilmişse, altındaki giderlerin sabit/değişken
        // oranı korunur; hiç gider yoksa aylık rakam sabit sayılır.
        if let manual = cm?.adsActual {
            r.adsFixed = reklamToplam > 0
                ? manual - Money.roundHalfAwayFromZero(Double(manual) * Double(reklamDegisken) / Double(reklamToplam))
                : manual
        } else {
            r.adsFixed = reklamToplam - reklamDegisken
        }

        var others = channelExpenses
        others[.reklam] = nil
        r.otherChannelExpenses = others.filter { $0.value != 0 }
        r.otherChannelExpensesFixed = r.otherChannelExpenses.reduce(0) { acc, kv in
            acc + max(kv.value - (channelVariableExpenses[kv.key] ?? 0), 0)
        }
        return r
    }

    /// Kanalın bu ay için aylık sabit ücreti (abonelik, mağaza ücreti).
    ///
    /// Ücret yalnızca kanalın ilk izinden itibaren işler: ilk satışı ya da
    /// açıkça tarihli ilk ayar kaydı. Böylece sonradan eklenen bir kanalın
    /// ücreti, kanal henüz yokken geçen aylara geriye dönük yazılmaz ve
    /// geçmiş bir ayın kârı zamanla değişmez.
    func aylikSabitKanalUcreti(_ ch: Channel, month: MonthKey) -> Kurus {
        guard let baslangic = kanalBaslangicAyi(ch), month >= baslangic else { return 0 }
        let r = ch.rates(on: Dates.monthEnd(month))
        let ek = r.extras.filter { $0.basis == .aylikSabit && !$0.unknown }
            .reduce(0.0) { $0 + $1.value }
        return r.platformFeeMonthly + r.otherDeductionMonthly + Money.roundHalfAwayFromZero(ek)
    }

    /// Kanalın ilk göründüğü ay: ilk satışı veya tarihli ilk ayar kaydı
    func kanalBaslangicAyi(_ ch: Channel) -> MonthKey? {
        let ilkSatis = state.sales.filter { $0.channelId == ch.id }.map(\.month).min()
        let ilkAyar = (ch.rateHistory ?? [])
            .map(\.from)
            .filter { $0 > "1970-01-01" }
            .min()
            .map { Dates.month(of: $0) }
        return [ilkSatis, ilkAyar].compactMap { $0 }.min()
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
            out.ortakGiderDegisken += m.ortakGiderDegisken
            out.stokAlimi += m.stokAlimi
            out.nakitCikisi += m.nakitCikisi
            out.giderKdv += m.giderKdv
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
