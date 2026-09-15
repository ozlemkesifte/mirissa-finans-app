import Testing
import Foundation
@testable import MirissaCore

/// Yeni ürün / malzeme / kanal / kesinti adı girişi
@Suite("Ad girişi")
struct NameCheckTests {

    @Test func bosAdKabulEdilmez() {
        #expect(NameCheck.isBlank(""))
        #expect(NameCheck.isBlank("   "))
        #expect(!NameCheck.isBlank("Şampuan"))
        #expect(NameCheck.issue("  ", among: [])?.severity == .engel)
    }

    @Test func turkceKarakterlerBozulmaz() {
        let ad = "Şampuan Işıltı Güçlendirici Özü"
        #expect(!NameCheck.isBlank(ad))
        #expect(NameCheck.key(ad) == "şampuan ışıltı güçlendirici özü")
    }

    /// "ŞAMPUAN" ile "şampuan" aynı kayıttır — Türkçe küçültme kuralıyla
    @Test func mukerrerAdBuyukKucukHarfDemedenYakalanir() {
        #expect(NameCheck.isDuplicate("şampuan", among: ["Şampuan", "Serum"]))
        #expect(NameCheck.isDuplicate("ŞAMPUAN", among: ["şampuan"]))
        #expect(NameCheck.isDuplicate("  Serum  ", among: ["Serum"]))
        #expect(NameCheck.isDuplicate("Set  Kutusu", among: ["Set Kutusu"]))
    }

    @Test func benzerAmaFarkliAdlarMukerrerSayilmaz() {
        #expect(!NameCheck.isDuplicate("Sampuan", among: ["Şampuan"]))
        #expect(!NameCheck.isDuplicate("Şampuan 250 ml", among: ["Şampuan"]))
        #expect(!NameCheck.isDuplicate("Serum", among: []))
    }

    @Test func mukerrerAdUyarisi() {
        let sorun = NameCheck.issue("Şampuan", among: ["şampuan"])
        #expect(sorun?.title == "Bu kayıt zaten var.")
        #expect(sorun?.severity == .engel)
    }

    @Test func gecerliAdSorunsuz() {
        #expect(NameCheck.issue("Kurdele", among: ["Şampuan", "Serum"]) == nil)
    }
}

/// Maliyet girilirken KDV dahil/hariç sorulmadan kayıt yapılmaz;
/// kâr ve stok hesabında her zaman net tutar kullanılır.
@Suite("Maliyette KDV")
struct CostVatTests {

    /// 120 TL KDV dahil %20 -> net 100 TL
    @Test func kdvDahilTutarNeteCevrilir() {
        #expect(Vat.net(tl(120), rate: .yirmi, included: true) == tl(100))
        #expect(Vat.split(tl(120), rate: .yirmi, included: true).vat == tl(20))
        #expect(Vat.net(tl(100), rate: .yirmi, included: false) == tl(100))
        #expect(Vat.split(tl(100), rate: .yirmi, included: false).vat == tl(20))
        #expect(Vat.net(tl(120), rate: .yok, included: true) == tl(120))
    }

    /// Başlangıç stoğu: net maliyet stoğa girer ama bu ay gider,
    /// nakit çıkışı veya indirilecek KDV oluşturmaz
    @Test func baslangicStoguGiderVeKdvOlusturmaz() {
        var s = Fx.base()
        if let i = s.products.firstIndex(where: { $0.id == Fx.sampuanId }) {
            // "Elimde 500 şampuan var, eski alış maliyetim 120 TL KDV dahil"
            s.products[i].openingQty = 500
            s.products[i].openingUnitCost = Vat.net(tl(120), rate: .yirmi, included: true)
            s.products[i].openingDate = "2026-09-01"
        }
        let e = Fx.engine(s)
        #expect(e.qty(.product(Fx.sampuanId)) == 500)
        #expect(e.unitCost(.product(Fx.sampuanId)) == Double(tl(100)))
        #expect(e.totalStockValue == tl(50_000))          // 500 × 100 TL

        let ay = e.companyMonth("2026-09")
        #expect(ay.toplamGider == 0)                      // bu ayın gideri değil
        #expect(ay.nakitCikisi == 0)                      // kasadan çıkmadı
        #expect(ay.giderKdv == 0)                         // indirilecek KDV doğmaz
        #expect(e.vatStatus("2026-09").indirilecek == 0)
    }

    /// Satış yapılınca net maliyet kâra girer — KDV'li tutar değil
    @Test func karHesabiNetMaliyetiKullanir() {
        var s = Fx.base()
        if let i = s.products.firstIndex(where: { $0.id == Fx.sampuanId }) {
            s.products[i].openingQty = 500
            s.products[i].openingUnitCost = Vat.net(tl(120), rate: .yirmi, included: true)
            s.products[i].openingDate = "2026-09-01"
            s.products[i].costLines = [CostLine(id: "c1", label: "Birim maliyet",
                                                amount: Vat.net(tl(120), rate: .yirmi,
                                                                included: true))]
        }
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 10, gross: tl(2_000))
        let r = Fx.engine(s).companyMonth("2026-09")
        let kanal = r.channels.first { $0.channelId == ChannelIds.trendyol }
        #expect(kanal?.productCost == tl(1_000))          // 10 × 100 TL net
    }

    /// Stok alımında KDV dahil girilen tutar: net maliyete, KDV indirilecek tarafa
    @Test func alimdaKdvAyrilir() {
        var s = Fx.base()
        s.purchases.append(StockPurchase(
            id: "p1", date: "2026-09-05", item: .material(Fx.koliId),
            qty: 100, unit: .adet, totalPaid: tl(1_200),
            vatRate: .yirmi, vatIncluded: true
        ))
        let e = Fx.engine(s)
        // 1.200 TL KDV dahil -> 1.000 TL net -> birim 10 TL
        #expect(e.unitCost(.material(Fx.koliId)) == Double(tl(10)))
        #expect(e.vatStatus("2026-09").indirilecek == tl(200))
        // Kasadan çıkan KDV dahil tutardır
        #expect(e.companyMonth("2026-09").nakitCikisi == tl(1_200))
    }

    /// Giderde KDV dahil girilen tutar net olarak kâra yansır
    @Test func giderdeKdvAyrilir() {
        var s = Fx.base()
        s.expenses.append(Expense(
            id: "exp_1", date: "2026-09-05", name: "Muhasebeci", amount: tl(1_200),
            category: .sabit, recurrence: .tek, vatRate: .yirmi, vatIncluded: true
        ))
        let e = Fx.engine(s)
        #expect(e.companyMonth("2026-09").ortakGider == tl(1_000))
        #expect(e.vatStatus("2026-09").indirilecek == tl(200))
    }

    /// KDV oranı seçilmemişse varsayılanla sessizce kaydedilmez:
    /// kayıtta oran alanı boş kalırsa "KDV yok" sayılır, tutar bozulmaz
    @Test func oranBelirtilmemisEskiKayitBozulmaz() {
        var s = Fx.base()
        s.expenses.append(Expense(id: "exp_1", date: "2026-09-05", name: "Eski kayıt",
                                  amount: tl(1_200), category: .diger, recurrence: .tek))
        let e = Fx.engine(s)
        #expect(e.companyMonth("2026-09").ortakGider == tl(1_200))
        #expect(e.vatStatus("2026-09").indirilecek == 0)
    }
}
