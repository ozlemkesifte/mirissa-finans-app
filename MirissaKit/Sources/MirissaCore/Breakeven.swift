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

    /// Ana sayfada rakamın altına yazılan kısa etiket
    public var label: String {
        switch self {
        case let .gecmisAy(m):
            return "Yaklaşık · \(Dates.displayMonth(m)) karışımına göre"
        case .beklenenDagilim:
            return "Yaklaşık · girdiğin dağılıma göre"
        case .ayinKendisi:
            return "Bu ayın gerçek satışlarına göre"
        case .yok:
            return ""
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
    case fiyatGuncel
    case eksikKanalBilgisi
    case gerceklesmeOlagandisi

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
        case .fiyatGuncel:
            return "Hedef, bu ayda geçerli olan güncel fiyat, komisyon ve maliyetlerle hesaplandı. Geçmiş ayların raporu değişmedi."
        case .eksikKanalBilgisi:
            return "Bir satış kanalında girilmemiş kesinti var. Bu hedef, o kalem sıfırmış gibi hesaplandı — gerçekte daha yüksek olabilir."
        case .gerceklesmeOlagandisi:
            return "Gerçekleşme oranı olağandışı. Bu hedef yaklaşık hesaplanamadı. Temel alınan ayın satış tutarını ve adedini kontrol et."
        }
    }

    public var isBlocking: Bool {
        self == .referansYok || self == .katkiNegatif || self == .gerceklesmeOlagandisi
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
    /// Hedef hesaplanamıyorsa neyin eksik olduğu — "0 kargo" yerine bu gösterilir
    public var missing: [MissingSetupInfo] = []

    public var isApproximate: Bool { basis.isApproximate }
    public var blocking: BreakevenIssue? { issues.first { $0.isBlocking } }
    public var notes: [BreakevenIssue] { issues.filter { !$0.isBlocking } }
    public var canCompute: Bool { !targets.isEmpty }
    public var hasProgress: Bool { progressAsOf != nil && progressOrders != nil }
}

public extension Engine {

    /// Kullanıcı kendi kâr hedefini girmedikçe hazır bir tutar gösterilmez:
    /// hedef rakamı kullanıcıya aittir, uygulama uydurmaz.
    static let defaultGoals: [Kurus] = []

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

        guard let temel = targetBasis(before: month, today: today) else {
            // Geçmiş satış yoksa hedef yine de hesaplanmalı: neyin eksik
            // olduğunu söyle, sıfır gösterme.
            // Satış verisi var ama gerçekleşme oranı olağandışıysa "veri yok" denmez; veri hatası söylenir
            if !olagandisiGerceklesmeler(month: month).isEmpty {
                plan.issues.append(.gerceklesmeOlagandisi)
                return plan
            }
            plan.missing = missingForTarget(month: month, today: today)
            plan.issues.append(.referansYok)
            return plan
        }
        plan.basis = temel.basis
        plan.contributionPerOrder = temel.contributionPerOrder
        plan.revenuePerOrder = temel.revenuePerOrder
        plan.unitsPerOrder = temel.unitsPerOrder
        if temel.basis == .beklenenDagilim {
            // Geçmiş aydan gelen katkıda satışa bağlı giderler zaten sipariş
            // başına düşülmüştür; kurulumdan gelen katkıda yoktur.
            plan.fixedCosts += satisaBagliAylikGiderler(month: month)
        }
        if temel.urunMaliyetiEksik { plan.issues.append(.urunMaliyetiYok) }
        if temel.fiyatGuncellendi { plan.issues.append(.fiyatGuncel) }
        if eksikKanalKesintisiVar(month: month) { plan.issues.append(.eksikKanalBilgisi) }

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

        // Satış girilmiş olsa bile "kaç kargo gerekiyor" sorusunun cevabı görünmeli.
        // Bu ayın kendi gerçek karışımı kullanılır.
        plan.fixedCosts = r.toplamSabitGider
        if plan.contributionPerOrder > 0 {
            plan.basis = .ayinKendisi
            plan.targets = buildTargets(plan: plan, month: month, days: days)
        } else if r.orders == 0 {
            // Ayın satışı yoksa ileriye dönük hedef kurulum verisinden gelir
            plan.fixedCosts = plannedFixedCosts(month: month)
            if let temel = targetBasis(before: month, today: today),
               temel.contributionPerOrder > 0 {
                plan.basis = temel.basis
                plan.contributionPerOrder = temel.contributionPerOrder
                plan.revenuePerOrder = temel.revenuePerOrder
                plan.unitsPerOrder = temel.unitsPerOrder
                if temel.basis == .beklenenDagilim {
                    plan.fixedCosts += satisaBagliAylikGiderler(month: month)
                }
                plan.targets = buildTargets(plan: plan, month: month, days: days)
            } else if !olagandisiGerceklesmeler(month: month).isEmpty {
                plan.issues.append(.gerceklesmeOlagandisi)
            } else {
                plan.missing = missingForTarget(month: month, today: today)
            }
        }
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
        /// Temel ay, hedef ayın fiyatlarıyla yeniden değerlendi mi
        var fiyatGuncellendi: Bool = false
    }

    /// Verilen aydan önceki son tamamlanmış ayın gerçek dağılımı;
    /// yoksa kullanıcının girdiği beklenen profil.
    ///
    /// Geçmiş ay, hedef ayda geçerli fiyatlarla yeniden değerlenir:
    /// fiyat zammı hedefi düşürür, indirim yükseltir. Geçmiş ayın kendi
    /// raporu bundan etkilenmez — orada hâlâ o günün fiyatı geçerlidir.
    func targetBasis(before month: MonthKey,
                     today: DateKey = Dates.today()) -> TargetBasisResult? {
        // Bitmemiş bu ay (yarım veri) yalnızca tamamlanmış bir satış ayı yoksa temel alınır
        let buAy = Dates.month(of: today)
        var bitmemis: TargetBasisResult?
        for geri in 1...12 {
            let m = Dates.addMonths(month, -geri)
            let ham = companyMonth(m)
            guard ham.orders > 0, ham.gercekCiro > 0 else { continue }
            let guncel = fiyatlarlaYenidenDegerle(basisMonth: m, hedefAy: month,
                                                  gun: hedefGunu(month: month, today: today))
            let r = guncel ?? ham
            guard r.orders > 0 else { continue }
            let sonuc = TargetBasisResult(
                basis: .gecmisAy(m),
                contributionPerOrder: Double(r.toplamKatki) / Double(r.orders),
                revenuePerOrder: Double(r.gercekCiro) / Double(r.orders),
                unitsPerOrder: r.units / Double(r.orders),
                urunMaliyetiEksik: satilanUrunlerinMaliyetiGirilmemis(month: m),
                fiyatGuncellendi: guncel != nil
            )
            if m >= buAy {
                if bitmemis == nil { bitmemis = sonuc }
                continue
            }
            return sonuc
        }
        if let bitmemis { return bitmemis }
        // Geçmiş satış yok: kurulum bilgilerinden (fiyat, maliyet, komisyon,
        // kargo) ve onaylanmış yaklaşık dağılımdan hesapla.
        if let p = plannedContributionPerOrder(month: month, today: today), p.katki != 0 {
            return TargetBasisResult(
                basis: .beklenenDagilim,
                contributionPerOrder: p.katki,
                revenuePerOrder: p.ciro,
                unitsPerOrder: p.adet,
                urunMaliyetiEksik: false
            )
        }
        // Satış verisi var ama gerçekleşme oranı olağandışıysa başka bir temele sessizce geçilmez
        if !olagandisiGerceklesmeler(month: month).isEmpty { return nil }
        return expectedMixBasis(month: month, today: today)
    }

    /// Temel alınan ayın satışlarını, hedef ayda geçerli fiyatlarla yeniden hesaplar.
    /// Fiyatı tanımlı olmayan veya değişmemiş satırlar olduğu gibi kalır.
    /// Hiçbir fiyat değişmemişse `nil` döner ve hiçbir şey yeniden hesaplanmaz.
    /// Fiyatla birlikte hedef günde geçerli kanal oranları, kesinti KDV'si, ürün maliyetleri ve
    /// reçeteler de kullanılır; yoksa hedef, bu ay değişen komisyon veya maliyeti görmezdi.
    func fiyatlarlaYenidenDegerle(basisMonth: MonthKey, hedefAy: MonthKey,
                                  gun: DateKey? = nil) -> CompanyMonthResult? {
        let eskiGun = Dates.monthEnd(basisMonth)
        let yeniGun = gun ?? Dates.monthEnd(hedefAy)
        let anahtar = "\(basisMonth)|\(yeniGun)"
        if let onbellek = fiyatGuncelCache[anahtar] { return onbellek }

        var kopya = state
        var degisti = false
        var oraniDegisenKanallar = Set<Id>()
        // Kanal oranları ve kesinti ayarları hedef günün haliyle
        for i in kopya.channels.indices {
            let ch = kopya.channels[i]
            var yeni = ch.rates(on: yeniGun)
            var eski = ch.rates(on: eskiGun)
            let yk = ch.kesintiKdv(on: yeniGun), ek = ch.kesintiKdv(on: eskiGun)
            yeni.id = ""; yeni.from = ""; eski.id = ""; eski.from = ""
            yeni.komisyonKdvHaric = ch.komisyonKdvHaric(on: yeniGun)
            eski.komisyonKdvHaric = ch.komisyonKdvHaric(on: eskiGun)
            yeni.feeVatRate = yk.oran; yeni.feesIncludeVat = yk.dahil
            eski.feeVatRate = ek.oran; eski.feesIncludeVat = ek.dahil
            guard yeni != eski else { continue }
            yeni.id = "\(ch.id)_hedef"; yeni.from = "1970-01-01"
            kopya.channels[i].rateHistory = [yeni]
            oraniDegisenKanallar.insert(ch.id)
            degisti = true
        }
        // Ürün maliyeti ve reçete hedef günün haliyle
        for i in kopya.products.indices {
            let p = kopya.products[i]
            let yeniMaliyet = p.costLines(on: yeniGun), eskiMaliyet = p.costLines(on: eskiGun)
            let yeniRecete = p.tarihli(yeniGun), eskiRecete = p.tarihli(eskiGun)
            guard yeniMaliyet != eskiMaliyet || yeniRecete.recipe != eskiRecete.recipe
                    || yeniRecete.components != eskiRecete.components else { continue }
            kopya.products[i].costLines = yeniMaliyet.map {
                var l = $0; l.validFrom = nil; l.validTo = nil; return l
            }
            kopya.products[i].recipe = yeniRecete.recipe
            kopya.products[i].components = yeniRecete.components
            kopya.products[i].eskiReceteler = nil
            degisti = true
        }
        // Kanal başına eski ve yeni satış tutarı: elle girilen komisyon da fiyatla birlikte ölçeklenir
        var eskiTutar: [Id: Double] = [:], yeniTutar: [Id: Double] = [:]
        for i in kopya.sales.indices where kopya.sales[i].month == basisMonth {
            let satir = kopya.sales[i]
            eskiTutar[satir.channelId, default: 0] += Double(satir.netSales)
            guard let p = kopya.product(satir.productId),
                  let eski = p.price(for: satir.channelId, on: eskiGun),
                  let yeni = p.price(for: satir.channelId, on: yeniGun),
                  eski > 0, yeni != eski else { continue }
            let oran = Double(yeni) / Double(eski)
            func olcekle(_ v: Kurus) -> Kurus {
                Money.roundHalfAwayFromZero(Double(v) * oran)
            }
            kopya.sales[i].grossSales = olcekle(satir.grossSales)
            kopya.sales[i].discount = olcekle(satir.discount)
            kopya.sales[i].returnsAmount = olcekle(satir.returnsAmount)
            degisti = true
        }
        for e in kopya.sales where e.month == basisMonth { yeniTutar[e.channelId, default: 0] += Double(e.netSales) }
        // Elle girilen ay komisyonu yeni fiyata göre ölçeklenir; kanalın oranı değiştiyse eski tutar
        // yeni oranı yansıtmaz, otomatik hesaba bırakılır. Yoksa hedef gerçekte olduğundan kolay çıkardı.
        for i in kopya.channelMonths.indices where kopya.channelMonths[i].month == basisMonth {
            let kanal = kopya.channelMonths[i].channelId
            guard let k = kopya.channelMonths[i].commissionActual else { continue }
            if oraniDegisenKanallar.contains(kanal) {
                kopya.channelMonths[i].commissionActual = nil
            } else if let e = eskiTutar[kanal], e > 0, let y = yeniTutar[kanal], y != e {
                kopya.channelMonths[i].commissionActual = Money.roundHalfAwayFromZero(Double(k) * y / e)
            }
        }
        guard degisti else {
            fiyatGuncelCache[anahtar] = CompanyMonthResult?.none
            return nil
        }
        // Oransal kesintiler yeni ciro üzerinden kendiliğinden yeniden hesaplanır
        let sonuc = Engine(kopya).companyMonth(basisMonth)
        fiyatGuncelCache[anahtar] = sonuc
        return sonuc
    }

    /// Kullanıcının girdiği beklenen sipariş profilinden katkı hesaplar.
    /// Geçmiş ay için o ayın sonundaki fiyat, KDV ve maliyetle (bugünkü değişiklik geçmiş hedefi oynatmasın)
    func expectedMixBasis(month: MonthKey = Dates.currentMonth(), today: DateKey = Dates.today()) -> TargetBasisResult? {
        guard let mix = state.settings.expectedMix,
              let ch = state.channel(mix.channelId),
              state.product(mix.productId) != nil,
              mix.averageOrderValue > 0 else { return nil }

        // Ortalama sepet müşterinin ödediği tutardır: KDV dahil.
        let gun = hedefGunu(month: month, today: today)
        let fiyat = mix.averageOrderValue
        let oran = satisKdvOrani(productId: mix.productId, channelId: mix.channelId, on: gun)
        let net = Double(Vat.net(fiyat, rate: oran, included: true))
        let kesinti = Double(kanalKesintisi(ch, siparisDegeri: fiyat, on: gun, satisKdv: oran).0.toplam)
        let b = cost(of: mix.productId, asOf: gun)
        let urun = birimUrunMaliyeti(mix.productId, asOf: gun) * mix.unitsPerOrder
        let koli = mix.unitsPerOrder >= Double(OrderPackaging.ikinciKoliUrunSayisi) ? 2.0 : 1.0
        let ambalaj = Double(b.packaging) * mix.unitsPerOrder + Double(b.orderPackaging) * koli
        let katki = net - kesinti - urun - ambalaj

        return TargetBasisResult(
            basis: .beklenenDagilim,
            contributionPerOrder: katki,
            revenuePerOrder: net,
            unitsPerOrder: mix.unitsPerOrder,
            urunMaliyetiEksik: !maliyetiEksikUrunler(mix.productId, asOf: gun).isEmpty
        )
    }

    /// Kurulumda "bilmiyorum" denen bir kanal kesintisi var mı.
    /// Varsa hedef kesin değil, yaklaşıktır — kullanıcıya açıkça söylenir.
    func eksikKanalKesintisiVar(month: MonthKey) -> Bool {
        let gun = Dates.monthEnd(month)
        return state.activeChannels.contains { ch in
            if !ch.rates(on: gun).eksikler.isEmpty { return true }
            // Aylık girilecek denip hiç tutarı olmayan kesinti hesaba giremez.
            // (Geçmiş aydan tahmin edilenler hesapta var; "girilmemiş" denmez.)
            return !elleAylikTahmin(ch, on: gun).eksik.isEmpty
        }
    }

    /// Hedef ayın sabit giderleri. Satış girilmemiş aylarda bile
    /// kanalların aylık sabit ücretleri hesaba katılır.
    func plannedFixedCosts(month: MonthKey) -> Kurus {
        let r = companyMonth(month)
        var toplam = r.toplamSabitGider
        // Ay sonucunda henüz yer almayan kanal ücretleri (kanal hiç iz
        // bırakmamışsa gerçekleşen hesapta yoktur ama hedefte olmalıdır).
        // Tarihçedeki güncel oran ve aylık sabit ek kesintiler de dahil.
        for ch in state.activeChannels {
            // Ücret bu ay işliyorsa ay sonucunda zaten var (elle 0 girildiyse de
            // gerçek tutar odur; geri eklenmez).
            guard aylikSabitKanalUcreti(ch, month: month) == 0 else { continue }
            // Kanal daha sonraki bir ayda başladıysa bu ay ücreti yoktur.
            guard kanalBaslangicAyi(ch) == nil else { continue }
            // Hiç iz bırakmamış kanal: planlanan ücret, gerçekleşen hesaptaki gibi KDV'siz.
            let o = ch.rates(on: Dates.monthEnd(month))
            let ek = o.extras.filter { $0.basis == .aylikSabit && !$0.unknown }
                .reduce(0.0) { $0 + $1.value }
            let ham = o.platformFeeMonthly + o.otherDeductionMonthly + Money.roundHalfAwayFromZero(ek)
            toplam += ch.kesintiSplit(ham, on: Dates.monthEnd(month)).net
        }
        return toplam
    }

    /// Ayın "satışa bağlı" işaretli giderleri. Geçmiş satış yokken sipariş
    /// başına dağıtılacak bir oran olmadığı için hedefte aylık tutar olarak
    /// karşılanmaları gerekir — yoksa hedef bu giderleri hiç görmez.
    func satisaBagliAylikGiderler(month: MonthKey) -> Kurus {
        let r = companyMonth(month)
        return r.ortakGiderDegisken
            + r.channels.reduce(0) { $0 + $1.adsVariable + $1.otherChannelExpensesVariable }
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
        // Ambalaj maliyeti değil, ürünün kendi üretim maliyeti aranıyor
        return satilan.contains { cost(of: $0, asOf: Dates.monthEnd(month)).intrinsic == 0 }
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

// MARK: - Yıllık başa baş

/// Yılın tamamı için hedef: kaç kargo, ayda kaç, günde kaç.
/// Her ayın hedefi o ayın kendi katkısıyla hesaplanır; yıllık hedef ayların toplamıdır.
public struct YearlyTarget: Hashable, Sendable, Identifiable {
    public var label: String
    public var targetProfit: Kurus
    public var isBreakeven: Bool
    public var isCustom: Bool
    public var ordersPerYear: Int
    /// Yıl geneli aylık ortalama: yıllık hedef ÷ 12, yukarı yuvarlanır
    public var ordersPerMonth: Int
    /// Yıl geneli günlük ortalama: yıllık hedef ÷ 365 (artık yılda 366), yukarı yuvarlanır
    public var ordersPerDay: Int
    public var revenue: Kurus
    /// Ay ay gereken sipariş (yalnızca faaliyetteki aylar); yıllık hedef bunların toplamıdır
    public var aylik: [MonthKey: Int] = [:]

    /// Sipariş gereken aylarda en az ve en çok aylık sipariş (0 gereken aylar aralığa girmez)
    public var aylikAralik: ClosedRange<Int>? {
        let v = aylik.values.filter { $0 > 0 }
        guard let a = v.min(), let b = v.max() else { return nil }
        return a...b
    }

    /// Faaliyetteki ay sayısı (sabit gideri ya da satışı olan aylar)
    public var aktifAySayisi: Int { aylik.count }

    /// Yalnızca yılın bir kısmında faaliyet varsa: yıllık hedef ÷ faaliyetteki ay sayısı, yukarı yuvarlanır
    public var aktifAyOrtalamasi: Int? {
        guard aktifAySayisi > 0, aktifAySayisi < 12 else { return nil }
        return Int(ceil(Double(ordersPerYear) / Double(aktifAySayisi)))
    }

    /// Operasyon bilgisi (ortalama değildir): en yoğun ayın hedefi
    public var enYogunAy: (ay: MonthKey, siparis: Int, gunluk: Int)? {
        guard let (ay, n) = aylik.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), n > 0 else { return nil }
        let gun = Dates.daysInMonth(year: Dates.year(of: ay), month: Dates.monthNumber(of: ay))
        return (ay, n, Int(ceil(Double(n) / Double(gun))))
    }

    public var id: String { "\(targetProfit)-\(isCustom)" }
}

public struct YearlyPlan: Hashable, Sendable {
    public var year: Int
    public var basis: TargetBasis
    public var contributionPerOrder: Double
    public var fixedCosts: Kurus
    public var targets: [YearlyTarget]
    public var issues: [BreakevenIssue]
    public var missing: [MissingSetupInfo] = []

    /// Yılın gerçekleşen tarafı
    public var actualRevenue: Kurus
    public var actualExpenses: Kurus
    public var actualProfit: Kurus
    public var actualMarginPct: Double
    public var actualOrders: Int

    public var isApproximate: Bool { basis.isApproximate }
    public var canCompute: Bool { !targets.isEmpty }
    public var blocking: BreakevenIssue? { issues.first { $0.isBlocking } }
    public var notes: [BreakevenIssue] { issues.filter { !$0.isBlocking } }
}

public extension Engine {

    /// Yıllık kâr hedefi de yalnızca kullanıcının girdiği tutardır
    static let defaultYearlyGoals: [Kurus] = []

    /// Yıllık başa baş ve kâr hedefleri.
    ///
    /// Tek bir sipariş başı katkıyla hesaplanmaz: her ay, o ay geçerli fiyat, maliyet ve kanal
    /// koşullarıyla kendi aylık planından (`plan(month:)`) hesaplanır ve yıllık hedef ayların
    /// toplamıdır. Gelecekte başlayan bir fiyat ya da komisyon değişikliği yalnızca ilgili aylara girer.
    /// Sabit gideri ve satışı olmayan aylar (iş henüz yok) hedefe 0 sipariş ekler; kâr hedefi
    /// faaliyette olan aylara eşit bölünür. Faaliyetteki bir ayın katkısı hesaplanamıyorsa yıllık
    /// hedef uydurulmaz, gösterilmez.
    func yearlyPlan(year y: Int, today: DateKey = Dates.today()) -> YearlyPlan {
        let aylar = (1...12).map { Dates.monthKey(y, $0) }
        let yil = year(y)
        var plan = YearlyPlan(
            year: y,
            basis: .ayinKendisi,
            contributionPerOrder: 0,
            fixedCosts: 0,
            targets: [],
            issues: [],
            actualRevenue: yil.gercekCiro,
            actualExpenses: yil.toplamGider,
            actualProfit: yil.gercekKar,
            actualMarginPct: yil.karMarjiPct,
            actualOrders: yil.months.reduce(0) { $0 + $1.orders }
        )

        let buAy = Dates.month(of: today)
        var planlar = aylar.map { self.plan(month: $0, today: today) }
        // Bitmemiş bu ayın yarım gerçekleşeni hedef temeli değildir: aylık hedefte olduğu gibi
        // önceki ayların karışımı bu ayın koşullarıyla kullanılır
        if let i = aylar.firstIndex(of: buAy), planlar[i].mode == .gerceklesen,
           let t = targetBasis(before: buAy, today: today) {
            planlar[i].basis = t.basis
            planlar[i].contributionPerOrder = t.contributionPerOrder
            planlar[i].revenuePerOrder = t.revenuePerOrder
            planlar[i].fixedCosts = plannedFixedCosts(month: buAy)
                + (t.basis == .beklenenDagilim ? satisaBagliAylikGiderler(month: buAy) : 0)
            planlar[i].issues.removeAll { $0 == .katkiNegatif }
            if t.urunMaliyetiEksik { planlar[i].issues.append(.urunMaliyetiYok) }
            if t.fiyatGuncellendi { planlar[i].issues.append(.fiyatGuncel) }
        }
        // Kendinden önce satış verisi olmayan bir ayın (ör. ilk satıştan önceki giderli aylar) katkısı,
        // bugüne en yakın gerçek satış ayının karışımı o ayın fiyat, oran ve maliyetleriyle
        // yeniden değerlenerek bulunur (yaklaşık)
        let referansAy = min(buAy, Dates.monthKey(y + 1, 1))
        if case let .gecmisAy(l)? = targetBasis(before: referansAy, today: today).map(\.basis) {
            for i in planlar.indices where planlar[i].contributionPerOrder == 0 && (planlar[i].actual?.orders ?? 0) == 0
                && targetBasis(before: aylar[i], today: today) == nil {
                let r = fiyatlarlaYenidenDegerle(basisMonth: l, hedefAy: aylar[i], gun: Dates.monthEnd(aylar[i]))
                    ?? companyMonth(l)
                guard r.orders > 0 else { continue }
                planlar[i].basis = .gecmisAy(l)
                planlar[i].contributionPerOrder = Double(r.toplamKatki) / Double(r.orders)
                planlar[i].revenuePerOrder = Double(r.gercekCiro) / Double(r.orders)
                planlar[i].issues.removeAll { $0 == .referansYok }
                planlar[i].missing = []
                if satilanUrunlerinMaliyetiGirilmemis(month: l) { planlar[i].issues.append(.urunMaliyetiYok) }
            }
        }

        // Faaliyetteki aylar: sabit gideri ya da satışı olan. Geçmiş aylarda bu, ayın gerçek kayıtlarından
        // bakılır (hiç kullanılmamış bir kanalın aylık ücreti işin olmadığı ayları faaliyette göstermesin).
        // Hiçbiri yoksa hesaplanabilen bütün aylar.
        var aktif = planlar.indices.filter { i in
            if aylar[i] < buAy {
                let r = companyMonth(aylar[i])
                return r.toplamSabitGider != 0 || r.orders > 0
            }
            return planlar[i].fixedCosts != 0 || (planlar[i].actual?.orders ?? 0) > 0
        }
        if aktif.isEmpty { aktif = planlar.indices.filter { planlar[$0].contributionPerOrder > 0 } }
        // Yılın sabit giderleri: faaliyetteki ayların, kendi planında kullanılan sabit gideri
        plan.fixedCosts = aktif.reduce(0) { $0 + planlar[$1].fixedCosts }
        if plan.fixedCosts == 0 { plan.issues.append(.sabitGiderYok) }
        guard !aktif.isEmpty else {
            let son = planlar[aylar.firstIndex(of: min(Dates.month(of: today), aylar[11])) ?? 11]
            plan.missing = son.missing
            plan.issues.append(son.blocking ?? .referansYok)
            return plan
        }
        for i in aktif where planlar[i].contributionPerOrder <= 0 {
            // Faaliyetteki bir ayın katkısı yok ya da eksi: yıllık hedef hesaplanamaz
            plan.missing = planlar[i].missing
            plan.issues.append(planlar[i].blocking ?? (planlar[i].basis == .yok ? .referansYok : .katkiNegatif))
            return plan
        }
        let haricTutulan: Set<BreakevenIssue> = [.ayHenuzBitmedi, .araDurumIsaretli, .sabitGiderYok, .referansYok, .katkiNegatif]
        for i in aktif {
            for n in planlar[i].issues where !haricTutulan.contains(n) && !plan.issues.contains(n) {
                plan.issues.append(n)
            }
        }
        if let yaklasik = aktif.map({ planlar[$0].basis }).first(where: \.isApproximate) {
            plan.basis = yaklasik
        }
        plan.contributionPerOrder = aktif.reduce(0.0) { $0 + planlar[$1].contributionPerOrder } / Double(aktif.count)

        func hedef(_ label: String, kar: Kurus, breakeven: Bool, custom: Bool) -> YearlyTarget? {
            let ayKari = Double(kar) / Double(aktif.count)
            var aylik: [MonthKey: Int] = [:]
            var ciro = 0.0
            for i in aktif {
                let p = planlar[i]
                let gereken = (Double(p.fixedCosts) + ayKari) / p.contributionPerOrder
                guard gereken.isFinite, gereken < 1_000_000 else { return nil }
                let n = Int(ceil(max(gereken, 0)))
                aylik[p.month] = n
                ciro += Double(n) * p.revenuePerOrder
            }
            let yillik = aylik.values.reduce(0, +)
            return YearlyTarget(
                label: label, targetProfit: kar,
                isBreakeven: breakeven, isCustom: custom,
                ordersPerYear: yillik,
                ordersPerMonth: Int(ceil(Double(yillik) / 12)),
                ordersPerDay: Int(ceil(Double(yillik) / Double(Dates.isLeap(y) ? 366 : 365))),
                revenue: Money.roundHalfAwayFromZero(ciro),
                aylik: aylik
            )
        }

        var out: [YearlyTarget] = []
        if let be = hedef("Başa baş", kar: 0, breakeven: true, custom: false) { out.append(be) }
        let ozel = state.settings.yearlyProfitGoal(for: y)
        let hedefler = ozel.map { [$0] } ?? Engine.defaultYearlyGoals
        for k in hedefler {
            if let t = hedef("\(Money.format(k)) kâr", kar: k,
                             breakeven: false, custom: ozel != nil) {
                out.append(t)
            }
        }
        plan.targets = out
        return plan
    }
}
