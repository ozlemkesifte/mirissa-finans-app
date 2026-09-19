import Testing
import Foundation
@testable import MirissaCore

/// Rastgele üretilmiş yüzlerce veri kombinasyonunda motorun bozulmadığını
/// doğrular. Tohum sabittir: bir test kırılırsa aynı veriyle tekrar üretilir.
@Suite("Rastgele veri — değişmezler")
struct PropertyTests {

    /// Sabit tohumlu üreteç (deterministik)
    struct Rastgele: RandomNumberGenerator {
        var durum: UInt64
        init(_ tohum: UInt64) { durum = tohum &* 6_364_136_223_846_793_005 &+ 1 }
        mutating func next() -> UInt64 {
            durum ^= durum << 13
            durum ^= durum >> 7
            durum ^= durum << 17
            return durum
        }
    }

    private typealias G = GoldenScenarioTests.G

    /// Altın senaryoyu temel alıp rastgele rakamlarla bozar
    private func rastgeleDurum(_ g: inout Rastgele) -> AppState {
        var s = GoldenScenarioTests.senaryo()

        for i in s.products.indices where !s.products[i].isBundle {
            s.products[i].openingQty = Double(Int.random(in: 0...2000, using: &g))
            s.products[i].openingUnitCost = Kurus(Int.random(in: 0...50_000, using: &g))
            s.products[i].costLines = [CostLine(label: "Üretim",
                                                amount: Kurus(Int.random(in: 0...40_000, using: &g)))]
        }
        for i in s.materials.indices {
            s.materials[i].openingQty = Double(Int.random(in: 0...5000, using: &g))
            s.materials[i].openingUnitCost = Kurus(Int.random(in: 0...5_000, using: &g))
        }
        for i in s.channels.indices {
            s.channels[i].commissionPct = Double(Int.random(in: 0...45, using: &g))
            s.channels[i].paymentPct = Double(Int.random(in: 0...10, using: &g))
            s.channels[i].shippingPerOrder = Kurus(Int.random(in: 0...30_000, using: &g))
            s.channels[i].serviceFeePerOrder = Kurus(Int.random(in: 0...5_000, using: &g))
            s.channels[i].otherDeductionPct = Double(Int.random(in: 0...15, using: &g))
        }
        let oranlar: [VatRate] = [.yok, .bir, .on, .yirmi]
        for i in s.sales.indices {
            let adet = Double(Int.random(in: 0...500, using: &g))
            s.sales[i].qty = adet
            s.sales[i].grossSales = Kurus(Int.random(in: 0...5_000_000, using: &g))
            s.sales[i].discount = Kurus(Int.random(in: 0...200_000, using: &g))
            s.sales[i].returnsQty = adet > 0 ? Double(Int.random(in: 0...Int(adet), using: &g)) : 0
            s.sales[i].returnsAmount = Kurus(Int.random(in: 0...300_000, using: &g))
            s.sales[i].returnsRestock = Bool.random(using: &g)
            s.sales[i].vatRate = oranlar[Int.random(in: 0..<oranlar.count, using: &g)]
            s.sales[i].vatIncluded = Bool.random(using: &g)
        }
        for i in s.expenses.indices {
            s.expenses[i].amount = Kurus(Int.random(in: 0...500_000, using: &g))
            s.expenses[i].vatRate = oranlar[Int.random(in: 0..<oranlar.count, using: &g)]
        }
        for i in s.purchases.indices {
            s.purchases[i].qty = Double(Int.random(in: 0...1000, using: &g))
            s.purchases[i].totalPaid = Kurus(Int.random(in: 0...1_000_000, using: &g))
        }
        return s
    }

    // MARK: Temel değişmezler

    @Test func yuzlerceKombinasyondaHesaplarTutarli() {
        var g = Rastgele(20260915)
        for tur in 0..<300 {
            let s = rastgeleDurum(&g)
            let e = Engine(s)
            let r = e.companyMonth("2026-09")

            // 1) Ciro − gider = kâr (her zaman)
            #expect(r.gercekCiro - r.toplamGider == r.gercekKar,
                    "tur \(tur): ciro/gider/kâr tutarsız")

            // 2) Marj sonlu ve makul
            #expect(r.karMarjiPct.isFinite, "tur \(tur): marj NaN/sonsuz")

            // 3) Her kanal için katkı = net satış − değişken gider
            for c in r.channels {
                #expect(c.contribution == c.netSales - c.variableCost,
                        "tur \(tur): \(c.channelName) katkı formülü bozuk")
                #expect(c.kanaldaKalan == c.netSales - c.totalCost,
                        "tur \(tur): \(c.channelName) kanalda kalan bozuk")
                #expect(c.marginPct.isFinite, "tur \(tur): kanal marjı sonsuz")
                #expect(c.orders >= 0, "tur \(tur): negatif sipariş")
            }

            // 4) Şirket toplamları kanalların toplamıyla uyumlu
            #expect(r.gercekCiro == r.channels.reduce(0) { $0 + $1.netSales },
                    "tur \(tur): ciro kanal toplamıyla uyuşmuyor")
            #expect(r.toplamKanaldaKalan == r.channels.reduce(0) { $0 + $1.kanaldaKalan },
                    "tur \(tur): kanalda kalan toplamı bozuk")

            // 5) Stok değerleri sayı olarak geçerli
            for ref in [ItemRef.product(G.sampuan), .product(G.serum),
                        .material(G.koli), .material(G.kutu)] {
                #expect(e.qty(ref).isFinite, "tur \(tur): stok NaN")
                #expect(e.unitCost(ref).isFinite, "tur \(tur): birim maliyet NaN")
                #expect(e.unitCost(ref) >= 0, "tur \(tur): negatif birim maliyet")
            }
            #expect(e.totalStockValue == e.totalStockValue)   // taşma/çökme yok
        }
    }

    // MARK: Kanal yalıtımı rastgele veriyle

    @Test func rastgeleVerideKanallarBirbiriniEtkilemez() {
        var g = Rastgele(777)
        for tur in 0..<150 {
            var s = rastgeleDurum(&g)
            let onceShopify = Engine(s).channelResult(channelId: G.shopify, month: "2026-09")

            // Trendyol'un satışını ve oranlarını değiştir
            for i in s.sales.indices where s.sales[i].channelId == G.trendyol {
                s.sales[i].grossSales += Kurus(Int.random(in: 1...100_000, using: &g))
            }
            let i = s.channels.firstIndex { $0.id == G.trendyol }!
            s.channels[i].commissionPct = Double(Int.random(in: 0...40, using: &g))

            let sonraShopify = Engine(s).channelResult(channelId: G.shopify, month: "2026-09")
            #expect(sonraShopify.netSales == onceShopify.netSales, "tur \(tur)")
            #expect(sonraShopify.commission.amount == onceShopify.commission.amount, "tur \(tur)")
            #expect(sonraShopify.kanaldaKalan == onceShopify.kanaldaKalan, "tur \(tur)")
        }
    }

    // MARK: Stok matematiği

    /// Stok = açılış + alım + iade − satış tüketimi − fire, bağımsız hesapla
    @Test func stokMatematigiBagimsizHesaplaUyar() {
        var g = Rastgele(4242)
        for tur in 0..<200 {
            let s = rastgeleDurum(&g)
            let e = Engine(s)
            let urun = s.products.first { $0.id == G.serum }!

            var beklenen = urun.openingQty ?? 0
            for p in s.purchases where p.item == .product(G.serum) { beklenen += p.qty }
            for sale in s.sales {
                let carpanlar = Costing.explodeToLeafProducts(
                    products: Dictionary(uniqueKeysWithValues: s.products.map { ($0.id, $0) }),
                    productId: sale.productId, qty: 1
                )
                guard let mult = carpanlar[G.serum] else { continue }
                beklenen -= sale.qty * mult
                if sale.returnsRestock { beklenen += sale.returnsQty * mult }
            }
            #expect(abs(e.qty(.product(G.serum)) - beklenen) < 0.000001,
                    "tur \(tur): stok bağımsız hesapla uyuşmuyor")
        }
    }

    // MARK: KDV

    @Test func kdvDengesiHerZamanTutar() {
        var g = Rastgele(99)
        for tur in 0..<200 {
            let s = rastgeleDurum(&g)
            let v = Engine(s).vatStatus("2026-09")
            // Ödenecek ve devreden aynı anda pozitif olamaz
            #expect(!(v.odenecek > 0 && v.devreden > 0), "tur \(tur)")
            // Net durum = hesaplanan − indirilecek − önceki devreden
            let net = v.hesaplanan - v.indirilecek - v.oncekiDevreden
            if net >= 0 {
                #expect(v.odenecek == net, "tur \(tur)")
                #expect(v.devreden == 0, "tur \(tur)")
            } else {
                #expect(v.devreden == -net, "tur \(tur)")
                #expect(v.odenecek == 0, "tur \(tur)")
            }
            // KDV motoru ile kâr motoru aynı satışları kullanmalı
            let ay = Engine(s).companyMonth("2026-09")
            #expect(v.hesaplanan == ay.channels.reduce(0) { $0 + $1.outputVat },
                    "tur \(tur): hesaplanan KDV satış KDV'siyle uyuşmuyor")
            #expect(v.indirilecek >= 0, "tur \(tur): indirilecek KDV eksi")
        }
    }

    // MARK: Başa baş

    @Test func basaBasHesabiSonluVeMakul() {
        var g = Rastgele(31337)
        for tur in 0..<200 {
            let s = rastgeleDurum(&g)
            let plan = Engine(s).plan(month: "2026-10", today: "2026-10-01")
            #expect(plan.contributionPerOrder.isFinite, "tur \(tur): katkı NaN")
            for t in plan.targets {
                #expect(t.orders >= 0, "tur \(tur): negatif hedef")
                #expect(t.dailyOrders >= 0, "tur \(tur): negatif günlük hedef")
                #expect(t.orders < 5_000_000, "tur \(tur): anlamsız büyük hedef")
                // Günlük hedef aylık hedeften büyük olamaz
                #expect(t.dailyOrders <= max(t.orders, 1), "tur \(tur)")
            }
            // Katkı negatifse hedef üretilmez
            if plan.contributionPerOrder <= 0 {
                #expect(plan.targets.isEmpty, "tur \(tur): eksi katkıyla hedef üretildi")
            }
        }
    }

    @Test func yillikHedefAylikVeGunlukTutarli() {
        var g = Rastgele(5150)
        for tur in 0..<150 {
            let s = rastgeleDurum(&g)
            let plan = Engine(s).yearlyPlan(year: 2026, today: "2026-10-01")
            for t in plan.targets {
                // Yıllık hedef ayların toplamı; ayda/günde en yoğun ayın hedefi
                #expect(t.ordersPerYear == t.aylik.values.reduce(0, +), "tur \(tur)")
                #expect(t.ordersPerMonth == (t.aylik.values.max() ?? 0), "tur \(tur)")
                #expect(t.ordersPerDay == t.aylik.map { Int(ceil(Double($0.value) / Double(Dates.daysInMonth(year: Dates.year(of: $0.key), month: Dates.monthNumber(of: $0.key))))) }.max() ?? 0, "tur \(tur)")
                #expect(t.ordersPerYear >= 0, "tur \(tur)")
            }
        }
    }

    // MARK: Aynı veriden aynı sonuç

    @Test func ayniVeriHerZamanAyniSonucuVerir() {
        var g = Rastgele(8080)
        for tur in 0..<100 {
            let s = rastgeleDurum(&g)
            let a = Engine(s).companyMonth("2026-09")
            let b = Engine(s).companyMonth("2026-09")
            #expect(a == b, "tur \(tur): aynı veriden farklı sonuç")
            #expect(Engine(s).qty(.material(G.koli)) == Engine(s).qty(.material(G.koli)))
        }
    }
}
