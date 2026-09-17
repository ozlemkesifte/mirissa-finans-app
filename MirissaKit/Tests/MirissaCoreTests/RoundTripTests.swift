import Testing
import Foundation
@testable import MirissaCore

/// Kapat/aç ve yedek/geri yükleme sonrası bütün finansal sonuçlar birebir aynı olmalı.
@Suite("Kapat-aç ve yedek", .serialized)
@MainActor
struct RoundTripTests {

    private typealias G = GoldenScenarioTests.G

    /// Bir durumun bütün finansal parmak izi
    private func parmakIzi(_ s: AppState) -> [String: Int] {
        let e = Engine(s)
        let ay = e.companyMonth("2026-09")
        let v = e.vatStatus("2026-09")
        let plan = e.plan(month: "2026-10", today: "2026-10-01")
        let yil = e.yearlyPlan(year: 2026, today: "2026-10-01")
        var out: [String: Int] = [
            "ciro": ay.gercekCiro,
            "gider": ay.toplamGider,
            "kar": ay.gercekKar,
            "nakit": ay.nakitCikisi,
            "stokAlimi": ay.stokAlimi,
            "kdvHesaplanan": v.hesaplanan,
            "kdvIndirilecek": v.indirilecek,
            "kdvOdenecek": v.odenecek,
            "stokDegeri": e.totalStockValue,
            "sampuanStok": Int(e.qty(.product(G.sampuan))),
            "serumStok": Int(e.qty(.product(G.serum))),
            "koliStok": Int(e.qty(.material(G.koli))),
            "koliMaliyet": Int(e.unitCost(.material(G.koli))),
            "setMaliyet": e.cost(of: G.set, asOf: "2026-09-30").total,
            "basaBas": plan.targets.first { $0.isBreakeven }?.orders ?? -1,
            "yillikBasaBas": yil.targets.first { $0.isBreakeven }?.ordersPerYear ?? -1,
        ]
        for c in ay.channels {
            out["\(c.channelId)-net"] = c.netSales
            out["\(c.channelId)-komisyon"] = c.commission.amount
            out["\(c.channelId)-kalan"] = c.kanaldaKalan
        }
        return out
    }

    private func zenginDurum() -> AppState {
        var s = GoldenScenarioTests.senaryo()
        // Tarihçeli fiyat ve komisyon, taslak, sayım, fire, iade — hepsi yedeğe girmeli
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].setPrice(tl(699), channelId: G.trendyol, from: "2026-09-01")
        s.products[i].setPrice(tl(749), channelId: G.trendyol, from: "2026-10-01")
        s.products[i].applyCostLines(
            [CostLine(id: "cst_g_s", label: "Üretim", amount: tl(130))], today: "2026-10-01")
        let j = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[j].setRates(ChannelRates(from: "2026-10-01", commissionPct: 25,
                                            shippingPerOrder: tl(110)))
        s.counts.append(StockCount(id: "cnt_1", date: "2026-09-25",
                                   item: .material(G.kutu), countedQty: 855, unit: .adet))
        s.adjustments.append(StockAdjustment(id: "adj_1", date: "2026-09-22",
                                             item: .material(G.koli), qty: 5,
                                             unit: .adet, isIncrease: false, reason: .fire))
        s.balances.append(BalanceItem(id: "bal_1", kind: .alacak, name: "Trendyol hakediş",
                                      amount: tl(50_000), dueDate: "2026-09-30"))
        s.settings.yearlyProfitGoals = ["2026": tl(500_000)]
        s.settings.priceCheckInterval = .ikiHaftalik
        s.settings.lastPriceCheck = "2026-09-10"
        if let d = WizardDraft.make(kind: .kanalKurulumu, subjectId: G.trendyol,
                                    title: "Trendyol kurulumu", step: 7, totalSteps: 12,
                                    state: ["komisyon": 25]) {
            s.drafts.append(d)
        }
        return s
    }

    // MARK: Kapat / aç

    @Test func uygulamaKapanipAcilincaHersyAyniKalir() throws {
        let dosya = FileStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mirissa-rt-\(UUID().uuidString).json"))
        let once = zenginDurum()
        do {
            let store = AppStore(file: dosya, saveDelay: .zero)
            store.replace(once)
            store.flush()
        }
        let sonra = AppStore(file: dosya).state
        #expect(parmakIzi(once) == parmakIzi(sonra))
        #expect(sonra.drafts.first?.step == 7)
        #expect(sonra.settings.yearlyProfitGoals["2026"] == tl(500_000))
        #expect(sonra.settings.priceCheckInterval == .ikiHaftalik)
        #expect(sonra.balances.count == 1)
    }

    /// Her kritik veri tipi tek tek korunur
    @Test func kritikVeriTipleriKorunur() throws {
        let geri = try Persistence.decode(try Persistence.encode(zenginDurum()))
        let p = try #require(geri.product(G.sampuan))
        #expect(p.price(for: G.trendyol, on: "2026-09-15") == tl(699))
        #expect(p.price(for: G.trendyol, on: "2026-10-15") == tl(749))
        #expect(p.costLines(on: "2026-09-15").reduce(0) { $0 + $1.amount } == tl(100))
        #expect(p.costLines(on: "2026-10-15").reduce(0) { $0 + $1.amount } == tl(130))
        let c = try #require(geri.channel(G.trendyol))
        #expect(c.rates(on: "2026-09-15").commissionPct == 20)
        #expect(c.rates(on: "2026-10-15").commissionPct == 25)
        #expect(geri.counts.count == 1)
        #expect(geri.adjustments.count == 1)
        #expect(geri.drafts.count == 1)
    }

    // MARK: Yedek / geri yükleme

    @Test func yedekAlIcerAyniSonucuVerir() throws {
        let once = zenginDurum()
        let yedek = try Persistence.encode(once)
        // Tertemiz bir uygulamaya geri yükle
        let temiz = AppStore.inMemory(AppState.empty)
        temiz.replace(try Persistence.decode(yedek))
        #expect(parmakIzi(once) == parmakIzi(temiz.state))
    }

    @Test func yedekIkiKezIceAktarilirsaVeriKopyalanmaz() throws {
        let yedek = try Persistence.encode(zenginDurum())
        let store = AppStore.inMemory(AppState.empty)
        store.replace(try Persistence.decode(yedek))
        let ilk = parmakIzi(store.state)
        store.replace(try Persistence.decode(yedek))
        #expect(parmakIzi(store.state) == ilk)
        #expect(store.state.sales.count == 3)
        #expect(Integrity.blocking(store.state).isEmpty)
    }

    @Test func geriYuklenenVeriButunlukDenetiminiGecer() throws {
        let geri = try Persistence.decode(try Persistence.encode(zenginDurum()))
        #expect(Integrity.check(geri).isEmpty)
    }

    // MARK: Eski sürüm yedekleri

    /// Alanların hiçbiri olmayan en eski biçim
    @Test func enEskiYedekOkunur() throws {
        let json = """
        {"schemaVersion":1,"savedAt":"2026-01-01T00:00:00Z","state":{
          "materials":[{"id":"m1","name":"Koli","category":"ambalaj","baseUnit":"adet",
                        "packSizesRaw":{},"archived":false}],
          "products":[{"id":"p1","name":"Şampuan","isBundle":false,"components":[],
                       "costLines":[{"id":"c1","label":"Üretim","amount":10000}],
                       "recipe":[],"costIncludesMaterials":[],"archived":false}],
          "channels":[{"id":"ch1","name":"Trendyol","kind":"marketplace","archived":false,
                       "commissionPct":20,"paymentPct":0,"shippingPerOrder":0,
                       "serviceFeePerOrder":0,"platformFeeMonthly":0,
                       "otherDeductionPct":0,"otherDeductionMonthly":0}],
          "sales":[],"expenses":[],"purchases":[],"adjustments":[],"counts":[]}}
        """
        let s = try Persistence.decode(Data(json.utf8))
        #expect(s.products.count == 1)
        #expect(s.products[0].costLines(on: nil).first?.amount == tl(100))
        #expect(s.channels[0].rates(on: "2026-09-01").commissionPct == 20)
        #expect(s.balances.isEmpty)
        #expect(s.drafts.isEmpty)
        #expect(s.settings.setupCompleted)          // kayıtlı dosyası olan kurulumu görmez
        #expect(Integrity.blocking(s).isEmpty)
    }

    /// Eski tek fiyat alanları geçmişe taşınır ve rapora yansımaz
    @Test func eskiFiyatAlanlariGoceder() throws {
        var s = GoldenScenarioTests.senaryo()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].listPrice = tl(650)
        s.products[i].channelPrices = [G.trendyol: tl(699)]
        let onceKar = Engine(s).companyMonth("2026-09").gercekKar

        let geri = try Persistence.decode(try Persistence.encode(s))
        let p = try #require(geri.product(G.sampuan))
        #expect(p.listPrice == nil)
        #expect(p.price(for: G.trendyol, on: "2020-01-01") == tl(699))
        // Göç kâr hesabını değiştirmez
        #expect(Engine(geri).companyMonth("2026-09").gercekKar == onceKar)
    }

    /// Eski "ürün bazlı maliyete dahil" listesi satır bayrağına taşınır
    @Test func eskiMaliyeteDahilListesiGoceder() throws {
        var s = GoldenScenarioTests.senaryo()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].costIncludesMaterials = [G.kutu]
        let geri = try Persistence.decode(try Persistence.encode(s))
        let p = try #require(geri.product(G.sampuan))
        #expect(p.costIncludesMaterials.isEmpty)
        let satir = p.recipe.first { $0.materialId == G.kutu }
        #expect(satir?.resolvedAddsCost == false)
        #expect(satir?.resolvedConsumesStock == true)      // stok tüketimi etkilenmez
        // Kutu artık maliyete girmez: ambalaj 15 yerine 10 (koli; yüklemede sipariş başına işaretlenir)
        let b = Engine(geri).cost(of: G.sampuan, asOf: "2026-09-30")
        #expect(b.packaging + b.orderPackaging == tl(10))
    }

    /// Bozuk satırlar uygulamayı çökertmez, ayıklanır
    @Test func bozukSatirlarAyiklanir() throws {
        var s = GoldenScenarioTests.senaryo()
        s.sales.append(SalesEntry(id: "sal_kotu", month: "2026-09",
                                  channelId: "yok", productId: "yok",
                                  qty: 5, grossSales: tl(1_000)))
        let geri = try Persistence.decode(try Persistence.encode(s))
        #expect(geri.sales.contains { $0.id == "sal_kotu" } == false)
        #expect(parmakIzi(geri)["ciro"] == parmakIzi(GoldenScenarioTests.senaryo())["ciro"])
    }

    // MARK: Motor kararlılığı

    /// Aynı veriden ikinci kez kurulan motor aynı rakamları verir (önbellek kaynaklı sapma yok)
    @Test func ayniVeridenIkinciMotorAyniSonucuVerir() {
        let s = zenginDurum()
        #expect(parmakIzi(s) == parmakIzi(s))
        // Rapor önce yıl, sonra ay okunduğunda da aynı
        let e = Engine(s)
        let yilOnce = e.year(2026).gercekKar
        let ay = e.companyMonth("2026-09").gercekKar
        let e2 = Engine(s)
        let ayOnce = e2.companyMonth("2026-09").gercekKar
        let yil = e2.year(2026).gercekKar
        #expect(yilOnce == yil)
        #expect(ay == ayOnce)
    }
}
