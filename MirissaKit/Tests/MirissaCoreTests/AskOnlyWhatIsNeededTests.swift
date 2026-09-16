import Testing
import Foundation
@testable import MirissaCore

/// Sistem yalnızca gerçekten gereken bilgiyi sormalı.
/// Satılmayan ürün-kanal ikilileri için fiyat sorulmaz, setin maliyeti sorulmaz.
@Suite("Yalnızca gerekeni sor")
struct AskOnlyWhatIsNeededTests {

    private typealias G = Golden.G

    /// Kurulumdan çıkmış tipik durum: fiyatların çoğu henüz girilmemiş
    private func yeniKurulum() -> AppState {
        var s = SeedData.initialState()
        s.settings.setupCompleted = true
        for i in s.products.indices where !s.products[i].isBundle {
            s.products[i].costLines = [CostLine(label: "Üretim", amount: tl(100))]
        }
        s.expenses.append(Expense(date: "2026-09-01", name: "Muhasebeci",
                                  amount: tl(10_000), category: .sabit, recurrence: .aylik))
        return s
    }

    /// Her ürünü her kanalda satılıyor varsaymaz
    @Test func satilmayanIkiliIcinFiyatSorulmaz() {
        var s = yeniKurulum()
        // Kullanıcı yalnızca Trendyol'da Şampuan sattığını söyledi
        let i = s.channels.firstIndex { $0.id == ChannelIds.trendyol }!
        s.channels[i].soldProductIds = [SeedData.P.sampuan]
        s.channels.removeAll { $0.id != ChannelIds.trendyol }
        s.settings.salesMix = SalesMix(channelShares: [ChannelIds.trendyol: 100],
                                       productShares: [SeedData.P.sampuan: 100],
                                       confirmed: true)
        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        // Yalnızca Şampuan'ın Trendyol fiyatı sorulur
        #expect(eksikler.filter { $0.kind == .fiyat }.count == 1)
        #expect(eksikler.contains { $0.title.contains("Şampuan") })
        #expect(!eksikler.contains { $0.title.contains("Set") })
        #expect(!eksikler.contains { $0.title.contains("Serum") })
    }

    /// Kanalda ne satıldığı bilinmiyorsa 9 ayrı fiyat sormak yerine tek soru sorar
    @Test func kanalUrunleriBilinmiyorsaTekSoru() {
        let s = yeniKurulum()
        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        // Her kanal için tek "hangi ürünleri satıyorsun" sorusu
        #expect(eksikler.filter { $0.kind == .kanalUrunleri }.count == s.activeChannels.count)
        // Ürün × kanal çarpımı kadar fiyat sorusu YOK
        #expect(eksikler.filter { $0.kind == .fiyat }.isEmpty)
        #expect(eksikler.count < 6)
    }

    /// Setin maliyeti elle sorulmaz; eksikse bileşeni gösterilir
    @Test func setinMaliyetiSorulmazBileseniSorulur() {
        var s = Golden.senaryo()
        s.sales = []
        // Şampuan'ın maliyeti silinsin
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].costLines = []
        let j = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[j].soldProductIds = [G.set]
        s.channels.removeAll { $0.id != G.trendyol }
        s.products[s.products.firstIndex { $0.id == G.set }!]
            .setPrice(tl(1_500), channelId: G.trendyol, from: "2026-01-01")
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.set: 100], confirmed: true)

        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        // "Set maliyeti girilmemiş" DEĞİL, "Şampuan maliyeti girilmemiş"
        #expect(eksikler.contains { $0.kind == .urunMaliyeti && $0.title.contains("Şampuan") })
        #expect(!eksikler.contains { $0.kind == .urunMaliyeti && $0.title.contains("Set") })
    }

    /// Setin bileşenlerinin maliyeti tamsa set için maliyet sorulmaz
    @Test func bilesenMaliyetiTamsaSetSorulmaz() {
        var s = Golden.senaryo()
        s.sales = []
        let j = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[j].soldProductIds = [G.set]
        s.channels.removeAll { $0.id != G.trendyol }
        s.products[s.products.firstIndex { $0.id == G.set }!]
            .setPrice(tl(1_500), channelId: G.trendyol, from: "2026-01-01")
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.set: 100], confirmed: true)
        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        #expect(!eksikler.contains { $0.kind == .urunMaliyeti })
    }

    /// Aynı ürünün maliyeti iki kez sorulmaz
    @Test func ayniUrunTekKezSorulur() {
        var s = Golden.senaryo()
        s.sales = []
        for i in s.products.indices { s.products[i].costLines = [] }
        let j = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[j].soldProductIds = [G.sampuan, G.set, G.ikili]
        s.channels.removeAll { $0.id != G.trendyol }
        for id in [G.sampuan, G.set, G.ikili] {
            s.products[s.products.firstIndex { $0.id == id }!]
                .setPrice(tl(1_000), channelId: G.trendyol, from: "2026-01-01")
        }
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 50, G.set: 30, G.ikili: 20],
                                       confirmed: true)
        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        let sampuanSorulari = eksikler.filter {
            $0.kind == .urunMaliyeti && $0.title.contains("Şampuan")
        }
        #expect(sampuanSorulari.count == 1)
    }

    /// Dağılımda yer alan ama fiyatı olmayan SKU yine de sorulur
    @Test func dagilimdakiSkuFiyatiSorulur() {
        var s = Golden.senaryo()
        s.sales = []
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].setPrice(tl(1_200), channelId: G.trendyol, from: "2026-01-01")
        s.channels.removeAll { $0.id != G.trendyol }
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 50, G.serum: 50],
                                       confirmed: true)
        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        #expect(eksikler.contains { $0.kind == .fiyat && $0.title.contains("Serum") })
    }

    /// Kanal listesi kaydedildiyse "bir satış ne bırakıyor" da onunla sınırlı
    @Test func katkiListesiSatilanlarlaSinirli() {
        var s = Golden.senaryo()
        for id in [G.sampuan, G.serum, G.set, G.ikili] {
            s.products[s.products.firstIndex { $0.id == id }!]
                .setPrice(tl(1_200), channelId: G.trendyol, from: "2026-01-01")
        }
        let j = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[j].soldProductIds = [G.sampuan, G.set]
        s.channels.removeAll { $0.id != G.trendyol }
        let liste = Engine(s).unitContributions(on: "2026-09-16")
        #expect(liste.count == 2)
        #expect(liste.allSatisfy { [G.sampuan, G.set].contains($0.productId) })
    }
}

/// Kanalın satış listesi veriyle tutarlı kalmalı
@Suite("Kanal satış listesi")
struct ChannelCatalogTests {

    private typealias G = Golden.G

    @Test func silinenUrunListedenDuser() throws {
        var s = Golden.senaryo()
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].soldProductIds = [G.sampuan, G.serum, G.set]
        s.products.removeAll { $0.id == G.serum }
        let geri = try Persistence.decode(try Persistence.encode(s))
        let liste = geri.channel(G.trendyol)?.soldProductIds ?? []
        #expect(!liste.contains(G.serum))
        #expect(liste.contains(G.sampuan))
        #expect(Integrity.blocking(geri).isEmpty)
    }

    @Test func olmayanUrunuIsaretEdenListeYakalanir() {
        var s = Golden.senaryo()
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].soldProductIds = ["yok_boyle_urun"]
        #expect(Integrity.blocking(s).contains { $0.message.contains("satış listesinde") })
    }

    @Test func listeYoksaEskiDavranisKorunur() {
        var s = Golden.senaryo()
        for i in s.channels.indices { s.channels[i].soldProductIds = nil }
        // Fiyatı olan ürünler "satılıyor" sayılır
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].setPrice(tl(1_200), channelId: G.trendyol, from: "2026-01-01")
        let ch = s.channel(G.trendyol)!
        #expect(ch.soldProducts(in: s, on: "2026-09-16") == [G.sampuan])
    }

    @Test func listeVarsaFiyatiOlmayanDaSayilir() {
        var s = Golden.senaryo()
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].soldProductIds = [G.sampuan, G.serum]
        let ch = s.channel(G.trendyol)!
        let satilan = ch.soldProducts(in: s, on: "2026-09-16")
        #expect(satilan.count == 2)
        #expect(satilan.contains(G.serum))      // fiyatı yok ama satılıyor deniyor
    }

    /// Ambalaj maliyeti olan bir ürünün üretim maliyeti eksikse yakalanır
    @Test func ambalajVarkenUretimMaliyetiEksigiGorulur() {
        var s = Golden.senaryo()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].costLines = []          // üretim maliyeti yok, reçete duruyor
        let e = Engine(s)
        // Toplam maliyet sıfır değil (ambalaj var) ama üretim maliyeti sıfır
        #expect(e.cost(of: G.sampuan, asOf: "2026-09-30").total > 0)
        #expect(e.cost(of: G.sampuan, asOf: "2026-09-30").intrinsic == 0)
        // Bu durum kullanıcıya bildirilmeli
        #expect(e.plan(month: "2026-10", today: "2026-10-01")
            .issues.contains(BreakevenIssue.urunMaliyetiYok))
    }
}

/// Dağılım sorusu yalnızca gerçekten gerektiğinde çıkmalı
@Suite("Dağılım sorusu ne zaman çıkar")
struct MixQuestionTests {

    private typealias G = Golden.G

    /// Adet girilmemiş eski satışlarda bile dağılım tutardan bulunur
    @Test func adetGirilmemisSatistaTutardanDagilim() {
        var s = Golden.senaryo()
        s.sales = [
            SalesEntry(id: "s1", month: "2026-08", channelId: G.trendyol,
                       productId: G.sampuan, qty: 0, grossSales: tl(60_000)),
            SalesEntry(id: "s2", month: "2026-08", channelId: G.shopify,
                       productId: G.serum, qty: 0, grossSales: tl(40_000)),
        ]
        let e = Engine(s)
        let (agirliklar, gecmisten) = e.targetMix(month: "2026-09")
        #expect(gecmisten)
        #expect(agirliklar.count == 2)
        let t = agirliklar.first { $0.channelId == G.trendyol }?.pay ?? 0
        #expect(abs(t - 0.6) < 0.0001)
        #expect(!e.missingForTarget(month: "2026-09", today: "2026-09-16")
            .contains { $0.kind == .dagilim })
    }

    /// Hiç satış yoksa ve birden çok ihtimal varsa sorulur
    @Test func hicSatisYoksaSorulur() {
        var s = Golden.senaryo()
        s.sales = []
        #expect(Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
            .contains { $0.kind == .dagilim })
    }

    /// Dağılım onaylanınca soru kaybolur
    @Test func onaylanincaSoruKaybolur() {
        var s = Golden.senaryo()
        s.sales = []
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 100], confirmed: true)
        #expect(!Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
            .contains { $0.kind == .dagilim })
    }

    /// Ayın kendi satışı varsa önceki ay aranmaz
    @Test func ayinKendiSatisiYeterli() {
        var s = Golden.senaryo()
        // Eylül satışları duruyor, öncesinde hiç satış yok
        let e = Engine(s)
        let (agirliklar, gecmisten) = e.targetMix(month: "2026-09")
        #expect(gecmisten)
        #expect(agirliklar.count == 3)
        _ = s
    }
}
