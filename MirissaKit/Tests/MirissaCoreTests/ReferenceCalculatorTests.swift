import Testing
import Foundation
@testable import MirissaCore

/// BAĞIMSIZ HESAPLAYICI
///
/// Motorun kâr-zarar hesabını motor kodunu kullanmadan, sıfırdan yeniden yazar
/// ve yüzlerce rastgele senaryoda iki sonucu kuruşu kuruşuna karşılaştırır.
/// İki ayrı yazılmış hesap aynı sonucu vermiyorsa biri yanlıştır.
///
/// Not: Ürün birim maliyeti (ağırlıklı ortalama) motordan okunur; o katman
/// altın senaryo ve stok testleriyle ayrıca doğrulanmıştır. Burada doğrulanan
/// kanal ve şirket kâr-zarar katmanıdır.
@Suite("Bağımsız hesaplayıcıyla karşılaştırma")
struct ReferenceCalculatorTests {

    private typealias G = Golden.G

    // MARK: - Bağımsız hesap

    /// Kendi KDV bölmemiz — Vat.split kullanılmaz
    private func net(_ tutar: Kurus, _ oran: VatRate?, _ dahil: Bool?) -> Kurus {
        let r = oran ?? .yok
        guard r != .yok, tutar != 0 else { return tutar }
        if dahil ?? true {
            return yuvarla(Double(tutar) / (1 + Double(r.rawValue) / 100))
        }
        return tutar
    }

    private func yuvarla(_ v: Double) -> Kurus {
        guard v.isFinite else { return 0 }
        return v < 0 ? -Int((-v).rounded(.toNearestOrAwayFromZero))
                     : Int(v.rounded(.toNearestOrAwayFromZero))
    }

    struct KanalBeklenen {
        var netSatis: Kurus = 0
        var komisyon: Kurus = 0
        var kargo: Kurus = 0
        var hizmet: Kurus = 0
        var diger: Kurus = 0
        var urunMaliyeti: Kurus = 0
        var ambalaj: Kurus = 0
        var reklam: Kurus = 0
        var digerKanalGideri: Kurus = 0
        var siparis: Int = 0
        var kanaldaKalan: Kurus {
            netSatis - (komisyon + kargo + hizmet + diger + reklam
                        + digerKanalGideri + urunMaliyeti + ambalaj)
        }
    }

    private func kanalBeklenen(_ s: AppState, _ kanalId: Id, _ ay: MonthKey,
                               _ e: Engine) -> KanalBeklenen {
        var b = KanalBeklenen()
        let ch = s.channel(kanalId)!
        let cm = s.channelMonths.first { $0.month == ay && $0.channelId == kanalId }
        let gun = Dates.monthEnd(ay)

        var kdvDahilNet: Kurus = 0
        var adet = 0.0, iadeAdet = 0.0
        for sat in s.sales where sat.month == ay && sat.channelId == kanalId {
            b.netSatis += net(sat.grossSales, sat.vatRate, sat.vatIncluded)
                - net(sat.discount, sat.vatRate, sat.vatIncluded)
                - net(sat.returnsAmount, sat.vatRate, sat.vatIncluded)
            // Kesinti tabanı müşterinin ödediği tutardır: KDV hariç girilmişse KDV eklenir
            let girilen = sat.grossSales - sat.discount - sat.returnsAmount
            let oranYuzde = Double((sat.vatRate ?? .yok).rawValue)
            kdvDahilNet += (sat.vatIncluded ?? true) || oranYuzde == 0
                ? girilen
                : girilen + yuvarla(Double(girilen) * oranYuzde / 100)
            adet += sat.qty
            iadeAdet += sat.returnsQty
            let m = e.cost(of: sat.productId, asOf: gun)
            b.urunMaliyeti += yuvarla(Double(m.intrinsic) * max(sat.qty - sat.returnsQty, 0))
            b.ambalaj += yuvarla(Double(m.packaging) * sat.qty)
        }
        if let oc = cm?.orderCount, oc > 0 { b.siparis = oc }
        else { b.siparis = Int(max(adet - iadeAdet, 0).rounded()) }

        let o = ch.rates(on: gun)
        let taban = Double(max(kdvDahilNet, 0))
        func kesinti(_ elle: Kurus?, _ otomatik: Double) -> Kurus {
            net(elle ?? yuvarla(otomatik), ch.feeVatRate, ch.feesIncludeVat)
        }
        b.komisyon = kesinti(cm?.commissionActual, taban * (o.commissionPct + o.paymentPct) / 100)
        b.kargo = kesinti(cm?.shippingActual, Double(o.shippingPerOrder) * Double(b.siparis))
        b.hizmet = kesinti(cm?.serviceFeeActual, Double(o.serviceFeePerOrder) * Double(b.siparis))
        var ekDegisken = 0.0, ekSabit = 0.0
        for f in o.extras where !f.unknown {
            switch f.basis {
            case .yuzde: ekDegisken += taban * f.value / 100
            case .siparisBasi: ekDegisken += f.value * Double(b.siparis)
            case .aylikSabit: ekSabit += f.value
            case .elleAylik: break
            }
        }
        // Aylık sabit ücret kanal başladığı aydan itibaren işler:
        // ilk satış ayı ya da 1970 sonrası tarihli ilk oran kaydının ayı.
        let ilkSatis = s.sales.filter { $0.channelId == kanalId }.map(\.month).min()
        let ilkKayit = (ch.rateHistory ?? []).map(\.from).filter { $0 > "1970-01-01" }.min()
            .map { String($0.prefix(7)) }
        let baslangic = [ilkSatis, ilkKayit].compactMap { $0 }.min()
        let sabit = (baslangic.map { ay >= $0 } ?? false)
            ? Double(o.platformFeeMonthly) + Double(o.otherDeductionMonthly) + ekSabit
            : 0
        b.diger = kesinti(cm?.otherDeductionActual,
                          taban * o.otherDeductionPct / 100 + sabit + ekDegisken)

        // Kanala ait giderler (KDV hariç)
        for g in s.expenses where g.scope.channelId == kanalId {
            guard gerceklesirMi(g, ay) else { continue }
            let tutar = net(g.overrides[ay]?.amount ?? g.amount, g.vatRate, g.vatIncluded)
            if g.category == .reklam { b.reklam += tutar } else { b.digerKanalGideri += tutar }
        }
        if let elle = cm?.adsActual { b.reklam = elle }
        return b
    }

    /// Bir gider bu ayda gerçekleşiyor mu — bağımsız tekrar kuralı
    private func gerceklesirMi(_ g: Expense, _ ay: MonthKey) -> Bool {
        let baslangic = Dates.month(of: g.date)
        if let o = g.overrides[ay], o.skipped { return false }
        switch g.recurrence {
        case .tek: return baslangic == ay
        case .aylik:
            guard ay >= baslangic else { return false }
            if let bitis = g.endMonth, ay > bitis { return false }
            return true
        case .yillik:
            guard ay >= baslangic else { return false }
            if let bitis = g.endMonth, ay > bitis { return false }
            return Dates.monthNumber(of: ay) == Dates.monthNumber(of: baslangic)
        }
    }

    private func ortakGiderBeklenen(_ s: AppState, _ ay: MonthKey) -> Kurus {
        s.expenses
            .filter { $0.scope.channelId == nil && gerceklesirMi($0, ay) }
            .reduce(0) { $0 + net($1.overrides[ay]?.amount ?? $1.amount, $1.vatRate, $1.vatIncluded) }
    }

    // MARK: - Rastgele senaryo

    struct Rastgele: RandomNumberGenerator {
        var d: UInt64
        init(_ t: UInt64) { d = t &* 2_862_933_555_777_941_757 &+ 3_037_000_493 }
        mutating func next() -> UInt64 { d ^= d << 13; d ^= d >> 7; d ^= d << 17; return d }
    }

    private func senaryo(_ g: inout Rastgele) -> AppState {
        var s = Golden.senaryo()
        let oranlar: [VatRate?] = [nil, .yok, .bir, .on, .yirmi]
        let feeOranlar: [VatRate?] = [nil, .yok, .yirmi]

        for i in s.channels.indices {
            s.channels[i].commissionPct = Double(Int.random(in: 0...30, using: &g))
            s.channels[i].paymentPct = Double(Int.random(in: 0...5, using: &g))
            s.channels[i].shippingPerOrder = Kurus(Int.random(in: 0...20_000, using: &g))
            s.channels[i].serviceFeePerOrder = Kurus(Int.random(in: 0...3_000, using: &g))
            s.channels[i].otherDeductionPct = Double(Int.random(in: 0...5, using: &g))
            s.channels[i].platformFeeMonthly = Kurus(Int.random(in: 0...100_000, using: &g))
            s.channels[i].feeVatRate = feeOranlar[Int.random(in: 0..<feeOranlar.count, using: &g)]
            s.channels[i].feesIncludeVat = Bool.random(using: &g)
            if Bool.random(using: &g) {
                s.channels[i].setRates(ChannelRates(
                    from: "2026-01-01",
                    commissionPct: Double(Int.random(in: 0...25, using: &g)),
                    shippingPerOrder: Kurus(Int.random(in: 0...15_000, using: &g)),
                    extras: [
                        ChannelExtraFee(label: "Kampanya", basis: .yuzde,
                                        value: Double(Int.random(in: 0...8, using: &g))),
                        ChannelExtraFee(label: "İşlem", basis: .siparisBasi,
                                        value: Double(Int.random(in: 0...1_000, using: &g))),
                        ChannelExtraFee(label: "Abonelik", basis: .aylikSabit,
                                        value: Double(Int.random(in: 0...50_000, using: &g))),
                        ChannelExtraFee(label: "Bilinmeyen", basis: .yuzde, value: 99,
                                        unknown: true),
                    ]))
            }
        }
        for i in s.sales.indices {
            let adet = Double(Int.random(in: 1...300, using: &g))
            s.sales[i].qty = adet
            s.sales[i].returnsQty = Double(Int.random(in: 0...Int(adet), using: &g))
            let brut = Kurus(Int.random(in: 100_000...9_000_000, using: &g))
            s.sales[i].grossSales = brut
            s.sales[i].discount = Kurus(Int.random(in: 0...(brut / 4), using: &g))
            s.sales[i].returnsAmount = Kurus(Int.random(in: 0...(brut / 4), using: &g))
            s.sales[i].vatRate = oranlar[Int.random(in: 0..<oranlar.count, using: &g)]
            s.sales[i].vatIncluded = Bool.random(using: &g)
        }
        for i in s.expenses.indices {
            s.expenses[i].amount = Kurus(Int.random(in: 0...3_000_000, using: &g))
            s.expenses[i].vatRate = oranlar[Int.random(in: 0..<oranlar.count, using: &g)]
            s.expenses[i].vatIncluded = Bool.random(using: &g)
        }
        // Bazen elle girilmiş gerçek kesintiler
        if Bool.random(using: &g) {
            s.channelMonths = [ChannelMonth(
                id: "chm_r", month: "2026-09", channelId: G.trendyol,
                orderCount: Bool.random(using: &g) ? Int.random(in: 1...400, using: &g) : nil,
                commissionActual: Bool.random(using: &g)
                    ? Kurus(Int.random(in: 0...2_000_000, using: &g)) : nil,
                shippingActual: Bool.random(using: &g)
                    ? Kurus(Int.random(in: 0...500_000, using: &g)) : nil,
                adsActual: Bool.random(using: &g)
                    ? Kurus(Int.random(in: 0...500_000, using: &g)) : nil
            )]
        }
        // Bazen ek bir ortak ve kanal gideri
        if Bool.random(using: &g) {
            s.expenses.append(Expense(
                id: "exp_r1", date: "2026-09-12", name: "Kargo firması",
                amount: Kurus(Int.random(in: 0...400_000, using: &g)),
                category: .kargo, recurrence: .tek, vatRate: .yirmi, vatIncluded: true))
        }
        if Bool.random(using: &g) {
            s.expenses.append(Expense(
                id: "exp_r2", date: "2026-09-12", name: "Shopify influencer",
                amount: Kurus(Int.random(in: 0...400_000, using: &g)),
                category: .influencer, scope: .channel(G.shopify), recurrence: .tek))
        }
        return s
    }

    // MARK: - Karşılaştırmalar

    @Test func kanalKariBagimsizHesaplaBirebirAyni() {
        var g = Rastgele(20260916)
        for tur in 0..<400 {
            let s = senaryo(&g)
            let e = Engine(s)
            for kanalId in [G.trendyol, G.shopify] {
                let m = e.channelResult(channelId: kanalId, month: "2026-09")
                let b = kanalBeklenen(s, kanalId, "2026-09", e)
                #expect(m.netSales == b.netSatis, "tur \(tur) \(kanalId): net satış")
                #expect(m.orders == b.siparis, "tur \(tur) \(kanalId): sipariş")
                #expect(m.commission.amount == b.komisyon, "tur \(tur) \(kanalId): komisyon")
                #expect(m.shipping.amount == b.kargo, "tur \(tur) \(kanalId): kargo")
                #expect(m.serviceFee.amount == b.hizmet, "tur \(tur) \(kanalId): hizmet")
                #expect(m.otherDeduction.amount == b.diger, "tur \(tur) \(kanalId): diğer")
                #expect(m.productCost == b.urunMaliyeti, "tur \(tur) \(kanalId): ürün maliyeti")
                #expect(m.packagingCost == b.ambalaj, "tur \(tur) \(kanalId): ambalaj")
                #expect(m.ads.amount == b.reklam, "tur \(tur) \(kanalId): reklam")
                #expect(m.otherChannelExpensesTotal == b.digerKanalGideri,
                        "tur \(tur) \(kanalId): diğer kanal gideri")
                #expect(m.kanaldaKalan == b.kanaldaKalan, "tur \(tur) \(kanalId): kanalda kalan")
            }
        }
    }

    @Test func sirketKariBagimsizHesaplaBirebirAyni() {
        var g = Rastgele(7_7_2026)
        for tur in 0..<400 {
            let s = senaryo(&g)
            let e = Engine(s)
            let r = e.companyMonth("2026-09")
            let kanallar = [G.trendyol, G.shopify].map { kanalBeklenen(s, $0, "2026-09", e) }
            let ortak = ortakGiderBeklenen(s, "2026-09")
            let ciro = kanallar.reduce(0) { $0 + $1.netSatis }
            let kar = kanallar.reduce(0) { $0 + $1.kanaldaKalan } - ortak
            #expect(r.gercekCiro == ciro, "tur \(tur): ciro")
            #expect(r.ortakGider == ortak, "tur \(tur): ortak gider")
            #expect(r.gercekKar == kar, "tur \(tur): kâr")
        }
    }

    /// Satışsız bir ayda (Ekim) şirket kârı: ortak giderler + kanalların
    /// aylık sabit ücretleri — bağımsız hesapla aynı olmalı
    @Test func satissizAyKariBagimsizHesaplaAyni() {
        var g = Rastgele(31_10_2026)
        for tur in 0..<300 {
            let s = senaryo(&g)
            let e = Engine(s)
            let ay = "2026-10"
            let r = e.companyMonth(ay)

            var beklenenKar: Kurus = -ortakGiderBeklenen(s, ay)
            for ch in s.channels where !ch.archived {
                // Bağımsız kanal başlangıcı: ilk satış veya 1970 dışı ilk ayar
                let ilkSatis = s.sales.filter { $0.channelId == ch.id }.map(\.month).min()
                let ilkAyar = (ch.rateHistory ?? []).map(\.from)
                    .filter { $0 > "1970-01-01" }.min().map { String($0.prefix(7)) }
                guard let bas = [ilkSatis, ilkAyar].compactMap({ $0 }).min(), ay >= bas
                else { continue }
                let o = ch.rates(on: Dates.monthEnd(ay))
                let ek = o.extras.filter { $0.basis == .aylikSabit && !$0.unknown }
                    .reduce(0.0) { $0 + $1.value }
                let ham = o.platformFeeMonthly + o.otherDeductionMonthly + yuvarla(ek)
                beklenenKar -= net(ham, ch.feeVatRate, ch.feesIncludeVat)
                // Kanala ait bu ayki giderler
                for gd in s.expenses where gd.scope.channelId == ch.id && gerceklesirMi(gd, ay) {
                    beklenenKar -= net(gd.overrides[ay]?.amount ?? gd.amount,
                                       gd.vatRate, gd.vatIncluded)
                }
            }
            #expect(r.gercekCiro == 0, "tur \(tur): satışsız ayda ciro")
            #expect(r.gercekKar == beklenenKar,
                    "tur \(tur): satışsız ay kârı \(r.gercekKar) ≠ \(beklenenKar)")
        }
    }

    // MARK: - İleriye dönük katkı ile gerçekleşen katkı tutarlı mı

    /// Bir SKU'yu listedeki fiyattan 1 adet satınca motorun "gerçekleşen" katkısı,
    /// kurulumdan hesaplanan "satış başına katkı" ile aynı olmalı.
    /// İki kod yolu ayrı yazıldı; ayrışırlarsa hedef ile sonuç tutmaz.
    @Test func planlananKatkiGerceklesenleAyni() {
        var g = Rastgele(4_2_42)
        for tur in 0..<300 {
            var s = Golden.senaryo()
            s.expenses = []
            s.channelMonths = []
            let kanalId = Bool.random(using: &g) ? G.trendyol : G.shopify
            let urunId = [G.sampuan, G.serum, G.set, G.ikili]
                .randomElement(using: &g)!
            let fiyat = Kurus(Int.random(in: 5_000...300_000, using: &g))
            let i = s.channels.firstIndex { $0.id == kanalId }!
            s.channels[i].commissionPct = Double(Int.random(in: 0...30, using: &g))
            s.channels[i].paymentPct = Double(Int.random(in: 0...5, using: &g))
            s.channels[i].shippingPerOrder = Kurus(Int.random(in: 0...20_000, using: &g))
            s.channels[i].serviceFeePerOrder = Kurus(Int.random(in: 0...3_000, using: &g))
            s.channels[i].otherDeductionPct = Double(Int.random(in: 0...5, using: &g))
            s.channels[i].feeVatRate = [VatRate.yok, .yirmi].randomElement(using: &g)!
            s.channels[i].feesIncludeVat = true
            s.settings.vatEnabled = true
            s.settings.defaultVatRate = [VatRate.yok, .on, .yirmi].randomElement(using: &g)!

            let j = s.products.firstIndex { $0.id == urunId }!
            s.products[j].setPrice(fiyat, channelId: kanalId, from: "2026-01-01")
            // Tam bir satış: listedeki fiyattan 1 adet, KDV ayarı aynı
            s.sales = [SalesEntry(id: "sal_1", month: "2026-09", channelId: kanalId,
                                  productId: urunId, qty: 1, grossSales: fiyat,
                                  vatRate: s.settings.defaultVatRate, vatIncluded: true)]

            let e = Engine(s)
            let gun = Dates.monthEnd("2026-09")
            guard let plan = e.unitContribution(productId: urunId, channelId: kanalId,
                                                on: gun) else {
                Issue.record("tur \(tur): fiyat varken katkı hesaplanamadı"); continue
            }
            let gercek = e.channelResult(channelId: kanalId, month: "2026-09")
            #expect(plan.netRevenue == gercek.netSales, "tur \(tur): net gelir")
            #expect(plan.productCost == gercek.productCost, "tur \(tur): ürün maliyeti")
            #expect(plan.packagingCost == gercek.packagingCost, "tur \(tur): ambalaj")
            // Kesintiler: gerçekleşen hesap her kesintiyi ayrı yuvarlar,
            // planlanan tek seferde — en fazla birkaç kuruş fark olabilir.
            let gercekKesinti = gercek.commission.amount + gercek.shipping.amount
                + gercek.serviceFee.amount + gercek.otherDeduction.amount
            #expect(abs(plan.channelFees - gercekKesinti) <= 3,
                    "tur \(tur): kesinti \(plan.channelFees) ≠ \(gercekKesinti)")
            #expect(abs(plan.contribution - gercek.contribution) <= 3,
                    "tur \(tur): katkı \(plan.contribution) ≠ \(gercek.contribution)")
        }
    }

    // MARK: - Başa baş matematiği

    /// Hedef = ceil((sabit gider + kâr) / sipariş başı katkı), bağımsız hesap
    @Test func basaBasFormuluBagimsizHesaplaAyni() {
        var g = Rastgele(1_000_003)
        for tur in 0..<300 {
            let s = senaryo(&g)
            let e = Engine(s)
            let plan = e.plan(month: "2026-10", today: "2026-10-01")
            guard plan.contributionPerOrder > 0 else { continue }
            for t in plan.targets {
                let gereken = (Double(plan.fixedCosts) + Double(t.targetProfit))
                    / plan.contributionPerOrder
                let beklenen = Int(ceil(max(gereken, 0)))
                #expect(t.orders == beklenen, "tur \(tur): \(t.label)")
                let gun = Dates.daysInMonth(year: 2026, month: 10)
                #expect(t.dailyOrders == Int(ceil(Double(beklenen) / Double(gun))),
                        "tur \(tur): günlük")
                // Bu adetle gerçekten o kâra ulaşılıyor mu?
                let ulasilan = Double(t.orders) * plan.contributionPerOrder
                    - Double(plan.fixedCosts)
                #expect(ulasilan >= Double(t.targetProfit) - 1, "tur \(tur): hedefe ulaşılmıyor")
                // Bir eksik adetle ulaşılmamalı (gereğinden fazla istenmiyor)
                if t.orders > 0 {
                    let birEksik = Double(t.orders - 1) * plan.contributionPerOrder
                        - Double(plan.fixedCosts)
                    #expect(birEksik < Double(t.targetProfit), "tur \(tur): hedef şişirilmiş")
                }
            }
        }
    }

    /// Geçmiş aydan alınan sipariş başı katkı = o ayın toplam katkısı / sipariş
    @Test func gecmisAyKatkisiBagimsizHesaplaAyni() {
        var g = Rastgele(555)
        for tur in 0..<200 {
            let s = senaryo(&g)
            let e = Engine(s)
            let eylul = e.companyMonth("2026-09")
            guard eylul.orders > 0, eylul.gercekCiro > 0 else { continue }
            let plan = e.plan(month: "2026-10", today: "2026-10-01")
            guard plan.basis == .gecmisAy("2026-09") else { continue }
            let beklenen = Double(eylul.toplamKatki) / Double(eylul.orders)
            #expect(abs(plan.contributionPerOrder - beklenen) < 0.001, "tur \(tur)")
        }
    }
}

/// Uçtan uca testte bulunan iki gerçek hatanın regresyon testleri
@Suite("Uçtan uca bulunan hatalar")
struct EndToEndFoundBugsTests {

    private typealias G = Golden.G

    private func satissizTrendyol() -> AppState {
        var s = Golden.senaryo()
        s.sales = []
        s.channels.removeAll { $0.id != G.trendyol }
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].soldProductIds = [G.sampuan]
        s.products[s.products.firstIndex { $0.id == G.sampuan }!]
            .setPrice(tl(1_200), channelId: G.trendyol, from: "2026-01-01")
        s.expenses = s.expenses.filter { $0.id == "exp_g1" }   // yalnızca muhasebeci
        return s
    }

    // MARK: Hata A — satış yokken satışa bağlı gider hedefi hiç etkilemiyordu

    @Test func satisaBagliReklamHedefiYukseltir() {
        var s = satissizTrendyol()
        let once = Engine(s).plan(month: "2026-09", today: "2026-09-16")
        s.expenses.append(Expense(id: "exp_rek", date: "2026-09-05", name: "Reklam",
                                  amount: tl(20_000), category: .reklam,
                                  scope: .channel(G.trendyol), recurrence: .tek))
        let sonra = Engine(s).plan(month: "2026-09", today: "2026-09-16")
        #expect(sonra.fixedCosts == once.fixedCosts + tl(20_000))
        let a = once.targets.first { $0.isBreakeven }!.orders
        let b = sonra.targets.first { $0.isBreakeven }!.orders
        // 10.000 / 545 -> 19 ; 30.000 / 545 -> 56
        #expect(a == 19)
        #expect(b == 56)
    }

    @Test func satisaBagliOrtakGiderHedefiYukseltir() {
        var s = satissizTrendyol()
        s.expenses.append(Expense(id: "exp_kargo", date: "2026-09-05", name: "Kargo firması",
                                  amount: tl(5_450), category: .kargo, recurrence: .tek))
        let plan = Engine(s).plan(month: "2026-09", today: "2026-09-16")
        // 10.000 + 5.450 = 15.450 / 545 = 28,35 -> 29
        #expect(plan.fixedCosts == tl(15_450))
        #expect(plan.targets.first { $0.isBreakeven }?.orders == 29)
    }

    /// Geçmiş satış varsa satışa bağlı giderler katkıda zaten var: iki kez eklenmez
    @Test func gecmisAyVarkenSatisaBagliGiderIkiKezSayilmaz() {
        let e = Engine(Golden.senaryo())
        let plan = e.plan(month: "2026-10", today: "2026-10-01")
        #expect(plan.basis == .gecmisAy("2026-09"))
        // Ekim'in sabit gideri yalnızca muhasebeci; Eylül reklamı katkıda
        #expect(plan.fixedCosts == tl(10_000))
    }

    @Test func yillikHedefteDeSatisaBagliGiderKarsilanir() {
        var s = satissizTrendyol()
        let once = Engine(s).yearlyPlan(year: 2026, today: "2026-09-16")
        s.expenses.append(Expense(id: "exp_rek", date: "2026-09-05", name: "Reklam",
                                  amount: tl(20_000), category: .reklam,
                                  scope: .channel(G.trendyol), recurrence: .tek))
        let sonra = Engine(s).yearlyPlan(year: 2026, today: "2026-09-16")
        #expect(sonra.fixedCosts == once.fixedCosts + tl(20_000))
    }

    // MARK: Hata B — satışı olmayan ayda kanalın aylık ücreti kârdan düşmüyordu

    @Test func satissizAydaKanalUcretiKardanDuser() {
        var s = Golden.senaryo()
        let i = s.channels.firstIndex { $0.id == G.shopify }!
        s.channels[i].platformFeeMonthly = tl(1_000)
        let eylulOnce = Engine(s).companyMonth("2026-09").gercekKar
        // Shopify'ın Ekim'de satışı yok — ama Eylül'de sattığı için kanal var
        let ekim = Engine(s).companyMonth("2026-10")
        let shop = ekim.channels.first { $0.channelId == G.shopify }
        #expect(shop?.otherDeduction.amount == tl(1_000))
        #expect(shop?.kanaldaKalan == -tl(1_000))
        // Ekim kârı: yalnızca muhasebeci (10.000) + Shopify ücreti (1.000)
        #expect(ekim.gercekKar == -tl(11_000))
        // Eylül'ün kârı değişmedi (orada zaten satışla birlikte alınıyordu)
        #expect(Engine(s).companyMonth("2026-09").gercekKar == eylulOnce)
    }

    /// Kanal henüz yokken geçen aylara ücret geriye dönük yazılmaz
    @Test func kanalUcretiGeriyeDonukYazilmaz() {
        var s = Golden.senaryo()
        let i = s.channels.firstIndex { $0.id == G.shopify }!
        s.channels[i].platformFeeMonthly = tl(1_000)
        // Shopify'ın ilk satışı Eylül: Ağustos'ta ücret olmamalı
        let agustos = Engine(s).companyMonth("2026-08")
        let shop = agustos.channels.first { $0.channelId == G.shopify }
        #expect((shop?.otherDeduction.amount ?? 0) == 0)
    }

    /// Hiç izi olmayan kanalın ücreti gerçekleşen kâra yazılmaz ama hedefte vardır
    @Test func izsizKanalUcretiHedefteVarGerceklesendeYok() {
        var s = satissizTrendyol()
        var yeni = Channel(id: "hb", name: "Hepsiburada", kind: .marketplace,
                           platformFeeMonthly: tl(2_000))
        yeni.soldProductIds = [G.sampuan]
        s.channels.append(yeni)
        s.products[s.products.firstIndex { $0.id == G.sampuan }!]
            .setPrice(tl(1_200), channelId: "hb", from: "2026-01-01")
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 50, "hb": 50],
                                       productShares: [G.sampuan: 100], confirmed: true)
        let e = Engine(s)
        // Gerçekleşen: kanalın hiç satışı ya da tarihli ayarı yok -> ücret yazılmaz
        #expect(e.companyMonth("2026-09").channels.first { $0.channelId == "hb" }?
            .otherDeduction.amount ?? 0 == 0)
        // Hedef: kanal kurulu, ücret karşılanmalı
        #expect(e.plan(month: "2026-09", today: "2026-09-16").fixedCosts == tl(12_000))
    }

    /// Tarihli ayar kaydı olan kanalın ücreti o aydan itibaren işler
    @Test func tarihliAyardanItibarenUcretIsler() {
        var s = Golden.senaryo()
        var yeni = Channel(id: "hb", name: "Hepsiburada", kind: .marketplace)
        yeni.setRates(ChannelRates(from: "2026-10-01", platformFeeMonthly: tl(2_000)))
        s.channels.append(yeni)
        let e = Engine(s)
        #expect((e.companyMonth("2026-09").channels.first { $0.channelId == "hb" }?
            .otherDeduction.amount ?? 0) == 0)
        #expect(e.companyMonth("2026-11").channels.first { $0.channelId == "hb" }?
            .otherDeduction.amount == tl(2_000))
    }

    /// Aylık sabit ek kesinti de aynı kurala tabi
    @Test func aylikSabitEkKesintiDeIsler() {
        var s = Golden.senaryo()
        let i = s.channels.firstIndex { $0.id == G.shopify }!
        s.channels[i].setRates(ChannelRates(
            from: "2026-09-01", paymentPct: 3, shippingPerOrder: tl(60),
            extras: [ChannelExtraFee(label: "Tema aboneliği", basis: .aylikSabit,
                                     value: Double(tl(500)))]))
        let ekim = Engine(s).companyMonth("2026-10")
        #expect(ekim.channels.first { $0.channelId == G.shopify }?
            .otherDeduction.amount == tl(500))
    }
}
