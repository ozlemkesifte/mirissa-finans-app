import Testing
import Foundation
@testable import MirissaCore
@testable import MirissaUI
import MirissaTestSupport

/// Ölü dokunuş olmasın: listelenen her şeyin gideceği bir ekran olmalı.
@Suite("Dokunulan her şey bir yere gitsin")
struct NavigationTests {

    private typealias G = Golden.G

    /// Eksik listesindeki her tür bir ekrana bağlı
    @Test func herEksikTuruBirEkranaGider() {
        let ornekler: [MissingSetupInfo] = [
            MissingSetupInfo(.fiyat, "Şampuan — Trendyol fiyatı girilmemiş",
                             productId: G.sampuan, channelId: G.trendyol),
            MissingSetupInfo(.urunMaliyeti, "Şampuan maliyeti girilmemiş",
                             productId: G.sampuan),
            MissingSetupInfo(.kanalKesintisi, "Trendyol kargo girilmemiş",
                             channelId: G.trendyol),
            MissingSetupInfo(.kanalUrunleri, "Trendyol ürünleri belli değil",
                             channelId: G.trendyol),
            MissingSetupInfo(.sabitGider, "Aylık sabit giderin girilmemiş"),
            MissingSetupInfo(.dagilim, "Satışların hangi kanal ve üründen geliyor?"),
        ]
        for m in ornekler {
            #expect(EksikleriTamamlaFlow.hedefEkran(m) != nil,
                    "\(m.kind.rawValue) türü hiçbir ekrana gitmiyor")
        }
    }

    /// Her tür için gerçekten üretilen eksikler de bir ekrana bağlı olmalı
    @Test func uretilenEksiklerinHepsiAcilabilir() {
        var s = Golden.senaryo()
        s.sales = []
        s.expenses = []
        for i in s.products.indices { s.products[i].costLines = [] }
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].setRates(ChannelRates(from: "2026-01-01", commissionPct: 20,
                                            unknownFields: ["kargo gideri"]))
        s.channels[i].soldProductIds = [G.sampuan]
        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        #expect(!eksikler.isEmpty)
        for m in eksikler {
            #expect(EksikleriTamamlaFlow.hedefEkran(m) != nil, "açılmıyor: \(m.title)")
        }
    }

    /// Her AppSheet durumunun benzersiz bir kimliği var (aynı id iki ekranı çakıştırır)
    @Test func sheetKimlikleriBenzersiz() {
        let hepsi: [AppSheet] = [
            .yeniIslem, .saleFlow, .purchaseFlow, .expenseFlow, .countFlow,
            .priceUpdate(nil), .priceUpdate("p1"), .channelWizard("c1"), .channelAdd,
            .eksikleriTamamla, .satisDagilimi,
            .editSale("s1"), .editExpense("e1", "2026-09"), .addPurchase(nil), .editPurchase("p1"),
            .adjustStock(nil), .editAdjustment("a1"), .countStock(nil), .editCount("c1"),
            .karHedefi("2026-09"), .yillikKarHedefi(2026), .aySonu("2026-09"),
            .addMaterial, .editMaterial("m1"), .addProduct, .editProduct("p1"),
            .channelSetup("c1"), .channelMonth("c1", "2026-09"),
            .addBalance, .editBalance("b1"), .settings,
        ]
        let idler = hepsi.map(\.id)
        #expect(Set(idler).count == idler.count, "aynı kimliği paylaşan ekran var")
    }

    /// Dağılım sorusu, cevaplanabilecek tek şeyse hedef hesaplanabilir hale gelir
    @Test func dagilimCevaplanincaHedefHesaplanir() {
        var s = Golden.senaryo()
        s.sales = []
        for id in [G.sampuan, G.serum] {
            s.products[s.products.firstIndex { $0.id == id }!]
                .setPrice(tl(1_200), channelId: G.trendyol, from: "2026-01-01")
        }
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].soldProductIds = [G.sampuan, G.serum]
        s.channels.removeAll { $0.id != G.trendyol }

        // Tek eksik: dağılım
        let once = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        #expect(once.count == 1)
        #expect(once.first?.kind == .dagilim)

        // Cevaplanınca hedef çıkar
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 60, G.serum: 40],
                                       confirmed: true)
        let plan = Engine(s).plan(month: "2026-09", today: "2026-09-16")
        #expect(Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16").isEmpty)
        #expect((plan.targets.first { $0.isBreakeven }?.orders ?? 0) > 0)
    }

    /// Satış girilmişse dağılım hiç sorulmaz
    @Test func satisVarsaDagilimSorulmaz() {
        // Ayın kendi satışı
        var s = Golden.senaryo()
        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        #expect(!eksikler.contains { $0.kind == .dagilim })

        // Sonraki ayın hedefi için geçmiş ay kullanılır
        #expect(!Engine(s).missingForTarget(month: "2026-10", today: "2026-10-01")
            .contains { $0.kind == .dagilim })

        // İleri tarihli satış girilmişse de sorulmaz
        s.sales = s.sales.map { var e = $0; e.month = "2026-11"; return e }
        #expect(!Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
            .contains { $0.kind == .dagilim })
    }

    /// Tek kanal ve o kanalda tek ürün varsa dağılım sorusu çıkmaz
    @Test func tekIhtimalVarsaSorulmaz() {
        var s = Golden.senaryo()
        s.sales = []
        s.channels.removeAll { $0.id != G.trendyol }
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].soldProductIds = [G.sampuan]
        s.products[s.products.firstIndex { $0.id == G.sampuan }!]
            .setPrice(tl(1_200), channelId: G.trendyol, from: "2026-01-01")
        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        #expect(!eksikler.contains { $0.kind == .dagilim })
        #expect((Engine(s).plan(month: "2026-09", today: "2026-09-16")
            .targets.first { $0.isBreakeven }?.orders ?? 0) > 0)
    }
}
