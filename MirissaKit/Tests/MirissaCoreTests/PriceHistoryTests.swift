import Testing
import Foundation
@testable import MirissaCore

/// Fiyat değişikliği geçmişi silmez: her fiyat kendi tarih aralığında geçerlidir.
@Suite("Fiyat geçmişi")
struct PriceHistoryTests {

    @Test func tarihinegoreGecerliFiyatSecilir() {
        var p = Fx.sampuan()
        p.setPrice(tl(699), channelId: ChannelIds.trendyol, from: "2026-09-01")
        p.setPrice(tl(749), channelId: ChannelIds.trendyol, from: "2026-09-20")

        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-01") == tl(699))
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-19") == tl(699))
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-20") == tl(749))
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-12-31") == tl(749))
        // Fiyat başlamadan önce fiyat yoktur
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-08-31") == nil)
    }

    @Test func yeniFiyatEskisiniSilmez() {
        var p = Fx.sampuan()
        p.setPrice(tl(699), channelId: ChannelIds.trendyol, from: "2026-09-01")
        p.setPrice(tl(749), channelId: ChannelIds.trendyol, from: "2026-09-20")
        let gecmis = p.priceTimeline(for: ChannelIds.trendyol)
        #expect(gecmis.count == 2)
        #expect(gecmis.first?.amount == tl(699))
        #expect(gecmis.last?.amount == tl(749))
    }

    @Test func gelecekteBaslayanFiyatTanimlanabilir() {
        var p = Fx.sampuan()
        p.setPrice(tl(699), channelId: ChannelIds.trendyol, from: "2026-09-01")
        p.setPrice(tl(799), channelId: ChannelIds.trendyol, from: "2026-11-01")
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-15") == tl(699))
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-10-31") == tl(699))
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-11-01") == tl(799))
    }

    @Test func ayniGuneIkinciGirisEskisiniGunceller() {
        var p = Fx.sampuan()
        p.setPrice(tl(699), channelId: ChannelIds.trendyol, from: "2026-09-20")
        p.setPrice(tl(729), channelId: ChannelIds.trendyol, from: "2026-09-20")
        #expect(p.priceTimeline(for: ChannelIds.trendyol).count == 1)
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-20") == tl(729))
    }

    @Test func kanalFiyatiYoksaEtiketFiyatinaDuser() {
        var p = Fx.sampuan()
        p.setPrice(tl(650), channelId: nil, from: "2026-09-01")
        p.setPrice(tl(699), channelId: ChannelIds.trendyol, from: "2026-09-01")
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-10") == tl(699))
        #expect(p.price(for: ChannelIds.shopify, on: "2026-09-10") == tl(650))
    }

    @Test func bitisTarihiVerilenFiyatSonrasindaGecerliDegil() {
        var p = Fx.sampuan()
        p.priceHistory = [PricePoint(channelId: ChannelIds.trendyol, amount: tl(699),
                                     from: "2026-09-01", to: "2026-09-30")]
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-30") == tl(699))
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-10-01") == nil)
    }

    // MARK: Geçmiş raporlar bozulmamalı

    /// Eylül ayının kârlılığı, ekimde yapılan zamla değişmemeli
    @Test func fiyatZammiGecmisAyiDegistirmez() {
        var s = Fx.base()
        s.addPurchase("p1", "2026-08-01", .product(Fx.sampuanId), qty: 500, paid: tl(50_000))
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(69_900))
        let once = Fx.engine(s).companyMonth("2026-09")

        if let i = s.products.firstIndex(where: { $0.id == Fx.sampuanId }) {
            s.products[i].setPrice(tl(699), channelId: ChannelIds.trendyol, from: "2026-09-01")
            s.products[i].setPrice(tl(799), channelId: ChannelIds.trendyol, from: "2026-10-01")
        }
        let sonra = Fx.engine(s).companyMonth("2026-09")

        #expect(once.gercekCiro == sonra.gercekCiro)
        #expect(once.gercekKar == sonra.gercekKar)
    }

    /// Ekim hedefi, ekimde geçerli fiyatla hesaplanır — eylülün fiyatıyla değil
    @Test func hedefGuncelFiyatlaHesaplanir() {
        var s = Fx.base()
        s.addPurchase("p1", "2026-08-01", .product(Fx.sampuanId), qty: 1000, paid: tl(100_000))
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(69_900))
        s.expenses.append(Expense(id: "exp_1", date: "2026-09-01", name: "Muhasebeci",
                                  amount: tl(10_000), category: .sabit, recurrence: .aylik))

        let zamsiz = Fx.engine(s).plan(month: "2026-10", today: "2026-10-05")
        if let i = s.products.firstIndex(where: { $0.id == Fx.sampuanId }) {
            s.products[i].setPrice(tl(699), channelId: ChannelIds.trendyol, from: "2026-09-01")
            s.products[i].setPrice(tl(899), channelId: ChannelIds.trendyol, from: "2026-10-01")
        }
        let zamli = Fx.engine(s).plan(month: "2026-10", today: "2026-10-05")

        // Sipariş başına katkı arttı -> başa baş için daha az sipariş gerekiyor
        #expect(zamli.contributionPerOrder > zamsiz.contributionPerOrder)
        let eskiHedef = zamsiz.targets.first { $0.isBreakeven }?.orders
        let yeniHedef = zamli.targets.first { $0.isBreakeven }?.orders
        #expect(eskiHedef != nil && yeniHedef != nil)
        #expect(yeniHedef! < eskiHedef!)
        #expect(zamli.issues.contains(BreakevenIssue.fiyatGuncel))
        // Eylülün kendi raporu değişmedi
        #expect(Fx.engine(s).companyMonth("2026-09").gercekCiro == tl(69_900))
    }

    /// Fiyat tanımlı değilse hiçbir şey yeniden değerlenmez
    @Test func fiyatYoksaHedefDegismez() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(69_900))
        let e = Fx.engine(s)
        #expect(e.fiyatlarlaYenidenDegerle(basisMonth: "2026-09", hedefAy: "2026-10") == nil)
        #expect(!e.plan(month: "2026-10", today: "2026-10-05")
            .issues.contains(.fiyatGuncel))
    }

    // MARK: Tarih aritmetiği

    @Test func gunFarkiDogruHesaplanir() {
        #expect(Dates.daysBetween("2026-09-01", "2026-09-08") == 7)
        #expect(Dates.daysBetween("2026-09-20", "2026-09-01") == -19)
        #expect(Dates.daysBetween("2026-02-28", "2026-03-01") == 1)   // 2026 artık yıl değil
        #expect(Dates.daysBetween("2024-02-28", "2024-03-01") == 2)   // 2024 artık yıl
        #expect(Dates.daysBetween("2025-12-31", "2026-01-01") == 1)
        #expect(Dates.addDays("2026-09-25", 10) == "2026-10-05")
        #expect(Dates.addDays("2026-01-01", -1) == "2025-12-31")
    }

    // MARK: Fiyat kontrol hatırlatıcısı

    @Test func hatirlaticiSuresiDolunca() {
        var a = AppSettings(priceCheckInterval: .haftalik, lastPriceCheck: "2026-09-01")
        #expect(!a.priceCheckDue(on: "2026-09-07"))
        #expect(a.priceCheckDue(on: "2026-09-08"))
        a.priceCheckInterval = .aylik
        #expect(!a.priceCheckDue(on: "2026-09-25"))
        #expect(a.priceCheckDue(on: "2026-10-01"))
        a.priceCheckInterval = .kapali
        #expect(!a.priceCheckDue(on: "2027-01-01"))
    }

    @Test func hicKontrolEdilmedigindeHatirlatir() {
        let a = AppSettings(priceCheckInterval: .aylik)
        #expect(a.priceCheckDue(on: "2026-09-15"))
        // İlk kullanım tarihi biliniyorsa süre oradan sayılır
        #expect(!a.priceCheckDue(on: "2026-09-15", since: "2026-09-10"))
    }

    // MARK: Eski yedek

    @Test func eskiTekFiyatGecmiseTasinir() throws {
        var s = Fx.base()
        if let i = s.products.firstIndex(where: { $0.id == Fx.sampuanId }) {
            s.products[i].listPrice = tl(650)
            s.products[i].channelPrices = [ChannelIds.trendyol: tl(699)]
        }
        let geri = try Persistence.decode(try Persistence.encode(s))
        let p = try #require(geri.product(Fx.sampuanId))
        #expect(p.listPrice == nil)
        #expect(p.channelPrices == nil)
        // Eski fiyat "başından beri geçerliydi" sayılır: geçmiş raporlar bozulmaz
        #expect(p.price(for: ChannelIds.trendyol, on: "2020-01-01") == tl(699))
        #expect(p.price(for: ChannelIds.shopify, on: "2026-09-01") == tl(650))
    }
}

/// Form ve kurulumdan gelen "şu anki fiyat" girişinin geçmişi bozmaması
@Suite("Fiyat girişi geçmişi korur")
struct PriceEntryTests {

    @Test func ilkGirisBastanGecerliSayilir() {
        var p = Fx.sampuan()
        p.applyCurrentPrice(tl(699), channelId: ChannelIds.trendyol, today: "2026-09-15")
        // Geçmiş aylar da fiyatsız kalmasın
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-01-01") == tl(699))
        #expect(p.priceTimeline(for: ChannelIds.trendyol).count == 1)
    }

    @Test func degisiklikBugundenBaslar() {
        var p = Fx.sampuan()
        p.applyCurrentPrice(tl(699), channelId: ChannelIds.trendyol, today: "2026-09-01")
        p.applyCurrentPrice(tl(749), channelId: ChannelIds.trendyol, today: "2026-09-20")
        #expect(p.priceTimeline(for: ChannelIds.trendyol).count == 2)
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-19") == tl(699))
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-20") == tl(749))
    }

    @Test func ayniFiyatTekrarGirilirseYeniKayitAcilmaz() {
        var p = Fx.sampuan()
        p.applyCurrentPrice(tl(699), channelId: nil, today: "2026-09-01")
        p.applyCurrentPrice(tl(699), channelId: nil, today: "2026-09-20")
        #expect(p.priceTimeline(for: nil).count == 1)
    }

    @Test func sifirGirisiFiyatiSilmez() {
        var p = Fx.sampuan()
        p.applyCurrentPrice(tl(699), channelId: nil, today: "2026-09-01")
        p.applyCurrentPrice(0, channelId: nil, today: "2026-09-20")
        #expect(p.price(on: "2026-09-20") == tl(699))
    }
}

/// Maliyet değişikliği de geçmiş raporları bozmamalı
@Suite("Maliyet geçmişi")
struct CostHistoryTests {

    @Test func maliyetDegisincsEskisiKapanir() {
        var p = Fx.sampuan(cost: tl(100))
        let ilk = p.costLines(on: nil)
        #expect(ilk.count == 1)
        p.applyCostLines([CostLine(id: ilk[0].id, label: "Üretim", amount: tl(130))],
                         today: "2026-10-01")
        #expect(p.costLines.count == 2)
        #expect(p.costLines(on: "2026-09-15").reduce(0) { $0 + $1.amount } == tl(100))
        #expect(p.costLines(on: "2026-10-01").reduce(0) { $0 + $1.amount } == tl(130))
        // Tarih verilmezse BUGÜN geçerli olan kalem gelir: yeni maliyet
        // 1 Ekim'de başladığı için bugün hâlâ eskisi geçerlidir
        #expect(p.costLines(on: nil).reduce(0) { $0 + $1.amount } == tl(100))
    }

    @Test func gecmisAyinUrunMaliyetiDegismez() {
        var s = Fx.base()
        s.products = [Fx.sampuan(cost: tl(100)), Fx.serum(), Fx.set()]
        s.addPurchase("p1", "2026-08-01", .product(Fx.sampuanId), qty: 500, paid: tl(50_000))
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(69_900))
        let once = Fx.engine(s).companyMonth("2026-09").gercekKar

        if let i = s.products.firstIndex(where: { $0.id == Fx.sampuanId }) {
            let aktif = s.products[i].costLines(on: nil)
            s.products[i].applyCostLines(
                [CostLine(id: aktif[0].id, label: "Üretim", amount: tl(160))],
                today: "2026-10-01"
            )
        }
        let e = Fx.engine(s)
        #expect(e.companyMonth("2026-09").gercekKar == once)
        // Bugünkü maliyet yeni değerle görünür
        #expect(e.cost(of: Fx.sampuanId, asOf: "2026-10-05").ownLines == tl(160))
        #expect(e.cost(of: Fx.sampuanId, asOf: "2026-09-15").ownLines == tl(100))
    }

    @Test func ilkKezGirilenMaliyetGecmiseDeUygulanir() {
        var p = Fx.sampuan()
        #expect(p.costLines.isEmpty)
        p.applyCostLines([CostLine(label: "Üretim", amount: tl(100))], today: "2026-10-01")
        #expect(p.costLines(on: "2026-01-01").reduce(0) { $0 + $1.amount } == tl(100))
    }

    @Test func kaldirilanKalemGecmisteGecerliKalir() {
        var p = Fx.sampuan(cost: tl(100))
        p.applyCostLines([], today: "2026-10-01")
        #expect(p.costLines(on: "2026-10-01").isEmpty)
        #expect(p.costLines(on: "2026-09-15").reduce(0) { $0 + $1.amount } == tl(100))
    }

    /// Set hem kendi kutusunu hem ürünün kutusunu fiziksel kullanabilir
    @Test func setIkiKutuyuBirdenDusebilir() {
        var s = Fx.base()
        if let i = s.products.firstIndex(where: { $0.id == Fx.setId }) {
            s.products[i].recipe.append(
                RecipeLine(id: "rcp_set_skutu", materialId: Fx.sampuanKutuId, qty: 1, unit: .adet)
            )
        }
        s.addSale("sal_1", "2026-09", channel: ChannelIds.shopify, product: Fx.setId,
                  qty: 30, gross: tl(45_000))
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.setKutuId)) == -30)
        #expect(e.qty(.material(Fx.sampuanKutuId)) == -30)
        #expect(e.qty(.material(Fx.koliId)) == -30)
    }

    /// Satış girilmemişse "kalan sipariş" üretilmez; aylık ve günlük hedef gösterilir
    @Test func satisYokkenKalanSiparisUretilmez() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(69_900))
        s.expenses.append(Expense(id: "exp_1", date: "2026-09-01", name: "Muhasebeci",
                                  amount: tl(10_000), category: .sabit, recurrence: .aylik))
        let plan = Fx.engine(s).plan(month: "2026-10", today: "2026-10-10")
        let hedef = plan.targets.first { $0.isBreakeven }
        #expect(hedef?.orders ?? 0 > 0)
        #expect(hedef?.dailyOrders ?? 0 > 0)
        #expect(hedef?.remainingOrders == nil)
        #expect(hedef?.remainingDailyOrders == nil)
    }
}
