import Testing
import Foundation
@testable import MirissaCore

@Suite("Kayıt, yedek ve başlangıç verisi")
struct PersistenceTests {

    /// Kaydet -> oku turu veriyi bozmadan geri getirir
    @Test func kaydetOkuTuru() throws {
        var s = SeedData.initialState()
        s.addPurchase("pur_1", "2026-09-01", .material(SeedData.M.koli), qty: 500, paid: tl(5000))
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol,
                  product: SeedData.P.sampuan, qty: 80, gross: tl(55_920))
        s.expenses.append(Expense(id: "e1", date: "2026-09-01", name: "Ajans",
                                  amount: tl(20_000), category: .sabit, recurrence: .aylik))

        let data = try Persistence.encode(s)
        let back = try Persistence.decode(data)
        #expect(back == s)
        #expect(Fx.engine(back).qty(.material(SeedData.M.koli)) == 420)
    }

    /// İleri sürümlü yedek, veriyi bozmaktansa reddedilir
    @Test func ileriSurumReddedilir() throws {
        let blob = PersistedBlob(schemaVersion: 99, state: SeedData.initialState())
        let data = try Persistence.encoder().encode(blob)
        #expect(throws: PersistenceError.self) { try Persistence.decode(data) }
    }

    /// Silinmiş kaleme bağlı kayıtlar sessizce ayıklanır, uygulama çökmez
    @Test func bozukSatirlarAyiklanir() throws {
        var s = SeedData.initialState()
        s.addPurchase("pur_x", "2026-09-01", .material("olmayan"), qty: 10, paid: tl(100))
        s.sales.append(SalesEntry(id: "sal_x", month: "2026-09", channelId: "olmayan",
                                  productId: "yok", qty: 1, grossSales: tl(10)))
        let back = try Persistence.decode(try Persistence.encode(s))
        #expect(back.purchases.isEmpty)
        #expect(back.sales.isEmpty)
        #expect(back.materials.count == s.materials.count)
    }

    /// İlk açılış: yapı hazır, bütün finansal göstergeler sıfır
    @Test func ilkAcilisSifirGosterir() {
        let s = SeedData.initialState()
        let e = Engine(s)
        #expect(s.products.count == 3)
        #expect(s.materials.count == 14)
        #expect(s.channels.count == 3)
        #expect(s.sales.isEmpty && s.expenses.isEmpty && s.purchases.isEmpty)

        let r = e.companyMonth(Dates.currentMonth())
        #expect(r.gercekCiro == 0)
        #expect(r.toplamGider == 0)
        #expect(r.gercekKar == 0)
        #expect(e.totalStockValue == 0)
        #expect(e.stockAlerts().isEmpty)          // uyarı yoksa ekran dolmaz
        for p in s.products { #expect(e.cost(of: p.id).total == 0) }
    }

    /// Başlangıç reçeteleri kullanıcının tarif ettiği gibi
    @Test func baslangicReceteleri() {
        let s = SeedData.initialState()
        let sampuan = s.product(SeedData.P.sampuan)!
        #expect(sampuan.recipe.count == 6)
        #expect(sampuan.recipe.contains { $0.materialId == SeedData.M.sampuanKutu && $0.qty == 1 })
        #expect(sampuan.recipe.contains { $0.materialId == SeedData.M.kirilmazEtiket && $0.qty == 2 })
        #expect(sampuan.recipe.contains { $0.materialId == SeedData.M.dolguKirpigi && $0.qty == 20 })

        let set = s.product(SeedData.P.set)!
        #expect(set.isBundle)
        #expect(set.components.count == 2)
        #expect(set.recipe.contains { $0.materialId == SeedData.M.dolguKirpigi && $0.qty == 30 })
    }

    /// Her ekranın boş durumda çökmeden hesaplanması
    @Test func bosDurumdaHerSeyHesaplanir() {
        let e = Engine(AppState.empty)
        #expect(e.companyMonth("2026-09").channels.isEmpty)
        #expect(e.year(2026).gercekCiro == 0)
        #expect(e.trend(endingAt: "2026-09").count == 6)
        #expect(e.stockAlerts().isEmpty)
        #expect(e.totalStockValue == 0)
    }

    /// CSV dışa aktarma her tabloyu üretir
    @Test func csvDisaAktarma() {
        var s = SeedData.initialState()
        s.addPurchase("pur_1", "2026-09-01", .material(SeedData.M.koli), qty: 500, paid: tl(5000))
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol,
                  product: SeedData.P.sampuan, qty: 80, gross: tl(55_920))
        var kdvsiz = s
        kdvsiz.settings.vatEnabled = false
        #expect(CSVExport.all(Engine(kdvsiz), from: "2026-01", to: "2026-12").count == 6)

        // KDV takibi açıkken kdv-ozeti.csv de çıkar
        let files = CSVExport.all(Engine(s), from: "2026-01", to: "2026-12")
        #expect(files.count == 7)
        #expect(files.contains { $0.name == "kdv-ozeti.csv" })
        #expect(files.allSatisfy { !$0.contents.isEmpty })
        let satis = files.first { $0.name == "satislar.csv" }!
        #expect(satis.contents.contains("Şampuan"))
        #expect(satis.contents.contains("55920,00"))
        let stok = files.first { $0.name == "stoklar.csv" }!
        #expect(stok.contents.contains("Kargo kolisi"))
    }
}
