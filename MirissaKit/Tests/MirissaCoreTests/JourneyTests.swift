import Testing
import Foundation
@testable import MirissaCore

/// Uçtan uca yolculuk: altı ay boyunca gerçekçi bir kullanım.
/// Her adımdan sonra bütün tutarlılık kuralları kontrol edilir ve
/// kapanmış ayların rakamlarının sonradan değişmediği doğrulanır.
@Suite("Altı aylık kullanım yolculuğu", .serialized)
@MainActor
struct JourneyTests {

    private typealias G = Golden.G

    private struct AyIzi: Equatable {
        var ciro: Kurus, gider: Kurus, kar: Kurus, nakit: Kurus
        var kdvHesaplanan: Kurus, kdvIndirilecek: Kurus
    }

    private func iz(_ e: Engine, _ ay: MonthKey) -> AyIzi {
        let r = e.companyMonth(ay)
        let v = e.vatStatus(ay)
        return AyIzi(ciro: r.gercekCiro, gider: r.toplamGider, kar: r.gercekKar,
                     nakit: r.nakitCikisi, kdvHesaplanan: v.hesaplanan,
                     kdvIndirilecek: v.indirilecek)
    }

    /// Her adımda geçerli olması gereken kurallar
    private func kurallar(_ st: AppStore, _ adim: String) {
        let s = st.state
        let e = st.engine
        #expect(Integrity.blocking(s).isEmpty, "\(adim): bozuk veri")
        for ay in Dates.monthRange(from: "2026-07", to: "2026-12") {
            let r = e.companyMonth(ay)
            #expect(r.gercekCiro - r.toplamGider == r.gercekKar, "\(adim) \(ay): ciro-gider≠kâr")
            #expect(r.karMarjiPct.isFinite, "\(adim) \(ay): marj")
            for c in r.channels {
                #expect(c.contribution == c.netSales - c.variableCost, "\(adim) \(ay)")
            }
        }
        for m in s.materials { #expect(e.unitCost(.material(m.id)).isFinite, "\(adim)") }
        let plan = e.plan(month: "2026-12", today: "2026-12-01")
        for t in plan.targets {
            #expect(t.orders >= 0 && t.orders < 5_000_000, "\(adim): hedef")
        }
    }

    @Test func altiAylikYolculuk() throws {
        let dosya = FileStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mirissa-journey-\(UUID().uuidString).json"))
        var st = AppStore(file: dosya, saveDelay: .zero)

        // --- Temmuz: kurulum, fiyatlar, dağılım, ilk alım ---
        var s = Golden.senaryo()
        s.sales = []
        s.purchases = []
        s.expenses = s.expenses.filter { $0.id == "exp_g1" }   // muhasebeci aylık
        for (id, tr, sh) in [(G.sampuan, 749, 699), (G.serum, 899, 849), (G.set, 1_499, 1_399)] {
            let i = s.products.firstIndex { $0.id == id }!
            s.products[i].setPrice(tl(Double(tr)), channelId: G.trendyol, from: "2026-07-01")
            s.products[i].setPrice(tl(Double(sh)), channelId: G.shopify, from: "2026-07-01")
        }
        for i in s.channels.indices {
            s.channels[i].soldProductIds = [G.sampuan, G.serum, G.set]
        }
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 70, G.shopify: 30],
                                       productShares: [G.sampuan: 50, G.serum: 30, G.set: 20],
                                       confirmed: true)
        st.replace(s)
        st.addPurchase(StockPurchase(id: "p_tem", date: "2026-07-03",
                                     item: .material(G.koli), qty: 1000, unit: .adet,
                                     totalPaid: tl(12_000), vatRate: .yirmi, vatIncluded: true))
        kurallar(st, "Temmuz kurulum")
        // Satış yokken hedef kurulumdan hesaplanabiliyor
        #expect(!st.engine.plan(month: "2026-07", today: "2026-07-05").targets.isEmpty)

        // --- Temmuz sonu satışlar ---
        func sat(_ id: String, _ ay: MonthKey, _ kanal: Id, _ urun: Id, _ adet: Double,
                 _ tutar: Double, iade: Double = 0) {
            st.addSale(SalesEntry(id: id, month: ay, channelId: kanal, productId: urun,
                                  qty: adet, grossSales: tl(tutar),
                                  returnsAmount: tl(tutar / adet * iade), returnsQty: iade,
                                  vatRate: .yirmi, vatIncluded: true))
        }
        sat("t1", "2026-07", G.trendyol, G.sampuan, 60, 44_940, iade: 3)
        sat("t2", "2026-07", G.shopify, G.serum, 20, 16_980)
        kurallar(st, "Temmuz satış")
        let temmuz = iz(st.engine, "2026-07")

        // --- Ağustos: satış + reklam ---
        sat("a1", "2026-08", G.trendyol, G.set, 30, 44_970)
        sat("a2", "2026-08", G.trendyol, G.sampuan, 50, 37_450)
        st.addExpense(Expense(id: "e_rek", date: "2026-08-10", name: "Trendyol reklam",
                              amount: tl(6_000), category: .reklam,
                              scope: .channel(G.trendyol), recurrence: .tek,
                              vatRate: .yirmi, vatIncluded: true))
        kurallar(st, "Ağustos")
        #expect(iz(st.engine, "2026-07") == temmuz, "Ağustos girişi Temmuz'u değiştirdi")
        let agustos = iz(st.engine, "2026-08")

        // --- Eylül: fiyat zammı + komisyon artışı (Eylül başından) ---
        var p = st.state.product(G.sampuan)!
        p.setPrice(tl(799), channelId: G.trendyol, from: "2026-09-01")
        st.updateProduct(p)
        st.applyChannelRates(G.trendyol, ChannelRates(from: "2026-09-01", commissionPct: 25,
                                                      shippingPerOrder: tl(110)))
        sat("s1", "2026-09", G.trendyol, G.sampuan, 70, 55_930)
        kurallar(st, "Eylül zam")
        #expect(iz(st.engine, "2026-07") == temmuz, "Eylül zammı Temmuz'u değiştirdi")
        #expect(iz(st.engine, "2026-08") == agustos, "Eylül zammı Ağustos'u değiştirdi")
        // Ağustos Trendyol komisyonu eski oranla, Eylül yeni oranla
        #expect(st.state.channel(G.trendyol)!.rates(on: "2026-08-31").commissionPct == 20)
        #expect(st.state.channel(G.trendyol)!.rates(on: "2026-09-30").commissionPct == 25)
        let eylul = iz(st.engine, "2026-09")

        // --- Ekim: maliyet değişikliği + stok sayımı + fire ---
        var urun = st.state.product(G.serum)!
        urun.applyCostLines([CostLine(id: "cst_g_r", label: "Üretim", amount: tl(160))],
                            today: "2026-10-01")
        st.updateProduct(urun)
        st.addCount(StockCount(id: "c1", date: "2026-10-20", item: .material(G.kutu),
                               countedQty: 700, unit: .adet, reason: .fire))
        st.addAdjustment(StockAdjustment(id: "f1", date: "2026-10-15",
                                         item: .material(G.koli), qty: 12, unit: .adet,
                                         reason: .hasarli))
        sat("k1", "2026-10", G.shopify, G.serum, 15, 12_735)
        kurallar(st, "Ekim")
        #expect(iz(st.engine, "2026-07") == temmuz, "Ekim maliyeti Temmuz'u değiştirdi")
        #expect(iz(st.engine, "2026-08") == agustos, "Ekim maliyeti Ağustos'u değiştirdi")
        #expect(iz(st.engine, "2026-09") == eylul, "Ekim maliyeti Eylül'ü değiştirdi")
        #expect(st.engine.qty(.material(G.kutu)) == 700)

        // --- Kasım: bir Temmuz satışını düzelt (geçmişe bilinçli düzeltme) ---
        var duzelt = st.state.sales.first { $0.id == "t2" }!
        duzelt.qty = 25
        duzelt.grossSales = tl(21_225)
        st.updateSale(duzelt)
        kurallar(st, "Kasım düzeltme")
        // Bilinçli düzeltme Temmuz'u değiştirir, sonraki ayları değiştirmez
        #expect(iz(st.engine, "2026-07") != temmuz)
        #expect(iz(st.engine, "2026-08").ciro == agustos.ciro)
        #expect(iz(st.engine, "2026-09").ciro == eylul.ciro)

        // --- Aralık: yedek al, uygulamayı kapat/aç, geri yükle ---
        let yedek = try Persistence.encode(st.state)
        let onceKapat = (1...12).map { iz(st.engine, Dates.monthKey(2026, $0)) }
        st.flush()
        st = AppStore(file: dosya)
        let sonraAc = (1...12).map { iz(st.engine, Dates.monthKey(2026, $0)) }
        #expect(onceKapat == sonraAc, "kapat/aç rakamları değiştirdi")

        let temiz = AppStore.inMemory(AppState.empty)
        temiz.replace(try Persistence.decode(yedek))
        let geriYuklenen = (1...12).map { iz(temiz.engine, Dates.monthKey(2026, $0)) }
        #expect(onceKapat == geriYuklenen, "yedekten dönüş rakamları değiştirdi")
        kurallar(temiz, "Aralık geri yükleme")

        // Yıllık rapor aylık raporların toplamı
        let yil = temiz.engine.year(2026)
        #expect(yil.gercekKar == geriYuklenen.reduce(0) { $0 + $1.kar })
        #expect(yil.gercekCiro == geriYuklenen.reduce(0) { $0 + $1.ciro })
    }
}
