import Testing
import Foundation
@testable import MirissaCore

@Suite("KDV takibi")
struct VatTests {

    // MARK: Ayrıştırma

    @Test func tutarNetVeKdvOlarakAyrilir() {
        // KDV dahil girilmiş
        let dahil = Vat.split(tl(120), rate: .yirmi, included: true)
        #expect(dahil.net == tl(100))
        #expect(dahil.vat == tl(20))
        #expect(dahil.total == tl(120))

        // KDV hariç girilmiş
        let haric = Vat.split(tl(100), rate: .yirmi, included: false)
        #expect(haric.net == tl(100))
        #expect(haric.vat == tl(20))

        // Diğer oranlar
        #expect(Vat.split(tl(110), rate: .on, included: true).net == tl(100))
        #expect(Vat.split(tl(101), rate: .bir, included: true).net == tl(100))

        // KDV yok
        let yok = Vat.split(tl(100), rate: .yok, included: true)
        #expect(yok.net == tl(100))
        #expect(yok.vat == 0)

        // Yuvarlama kuruşu kaybetmez
        let tek = Vat.split(tl(99.99), rate: .yirmi, included: true)
        #expect(tek.net + tek.vat == tl(99.99))
    }

    // MARK: Kârlılık KDV hariç

    /// 100 koli 1.200 TL (KDV dahil), satış 12.000 TL (KDV dahil), sabit gider 1.200 TL (KDV dahil)
    private func kurulum() -> AppState {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: 0)
        s.products[0].recipe = []
        s.purchases.append(StockPurchase(
            id: "pur", date: "2026-09-01", item: .material(Fx.koliId),
            qty: 100, unit: .adet, totalPaid: tl(1200),
            vatRate: .yirmi, vatIncluded: true
        ))
        s.sales.append(SalesEntry(
            id: "sal", month: "2026-09", channelId: ChannelIds.other,
            productId: Fx.sampuanId, qty: 100, grossSales: tl(12_000),
            vatRate: .yirmi, vatIncluded: true
        ))
        s.expenses.append(Expense(
            id: "e", date: "2026-09-02", name: "Ajans", amount: tl(1200),
            category: .sabit, vatRate: .yirmi, vatIncluded: true
        ))
        return s
    }

    @Test func ciroVeGiderKdvHaricGosterilir() {
        let r = Engine(kurulum()).companyMonth("2026-09")
        #expect(r.gercekCiro == tl(10_000))      // 12.000 KDV dahil -> 10.000 net
        #expect(r.ortakGider == tl(1000))        // 1.200 KDV dahil -> 1.000 net
        #expect(r.gercekKar == tl(9000))         // KDV kâra hiç karışmaz
    }

    /// Stok maliyeti KDV hariç tutulur — yoksa ürün maliyeti şişer
    @Test func stokMaliyetiKdvHaric() {
        let e = Engine(kurulum())
        #expect(approx(e.unitCost(.material(Fx.koliId)), Double(tl(10))))  // 1.000 / 100
        #expect(e.balance(.material(Fx.koliId)).value == tl(1000))
    }

    /// Nakit çıkışı KDV dahil kalır — cepten çıkan gerçekten o kadar
    @Test func nakitCikisiKdvDahil() {
        let r = Engine(kurulum()).companyMonth("2026-09")
        #expect(r.nakitCikisi == tl(1200) + tl(1200))   // gider + alım, ikisi de KDV dahil
        #expect(r.stokAlimi == tl(1200))
    }

    // MARK: KDV durumu

    @Test func hesaplananVeIndirilecekKdv() {
        let r = Engine(kurulum()).companyMonth("2026-09")
        #expect(r.hesaplananKdv == tl(2000))     // satıştan
        #expect(r.indirilecekKdv == tl(400))     // 200 alım + 200 gider

        let kdv = Engine(kurulum()).vatStatus("2026-09")
        #expect(kdv.odenecek == tl(1600))
        #expect(kdv.devreden == 0)
        #expect(kdv.summary == "Tahmini ödenecek KDV: 1.600 TL")
    }

    /// İndirilecek KDV fazlaysa sonraki aya devreder ve orada mahsup edilir
    @Test func devredenKdvSonrakiAyaTasinir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: 0)
        s.products[0].recipe = []
        // Ocak: sadece büyük alım, satış yok
        s.purchases.append(StockPurchase(
            id: "pur", date: "2026-01-10", item: .material(Fx.koliId),
            qty: 1000, unit: .adet, totalPaid: tl(30_000),
            vatRate: .yirmi, vatIncluded: true
        ))
        // Şubat: küçük satış
        s.sales.append(SalesEntry(
            id: "s2", month: "2026-02", channelId: ChannelIds.other,
            productId: Fx.sampuanId, qty: 10, grossSales: tl(12_000),
            vatRate: .yirmi, vatIncluded: true
        ))
        // Mart: büyük satış
        s.sales.append(SalesEntry(
            id: "s3", month: "2026-03", channelId: ChannelIds.other,
            productId: Fx.sampuanId, qty: 50, grossSales: tl(36_000),
            vatRate: .yirmi, vatIncluded: true
        ))
        let e = Engine(s)

        let ocak = e.vatStatus("2026-01")
        #expect(ocak.indirilecek == tl(5000))    // 30.000 KDV dahil -> 5.000 KDV
        #expect(ocak.odenecek == 0)
        #expect(ocak.devreden == tl(5000))

        let subat = e.vatStatus("2026-02")
        #expect(subat.hesaplanan == tl(2000))
        #expect(subat.oncekiDevreden == tl(5000))
        #expect(subat.odenecek == 0)
        #expect(subat.devreden == tl(3000))      // 5.000 − 2.000
        #expect(subat.summary == "Sonraki aya devreden KDV: 3.000 TL")

        let mart = e.vatStatus("2026-03")
        #expect(mart.hesaplanan == tl(6000))
        #expect(mart.oncekiDevreden == tl(3000))
        #expect(mart.odenecek == tl(3000))       // 6.000 − 3.000
        #expect(mart.devreden == 0)
    }

    // MARK: Kanal kesintileri

    /// Komisyon KDV dahil satış üzerinden alınır; net kısmı gidere, KDV'si indirilecek KDV'ye
    @Test func kanalKesintisininKdvsiAyrilir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: 0)
        s.products[0].recipe = []
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = true
        s.sales.append(SalesEntry(
            id: "sal", month: "2026-09", channelId: ChannelIds.trendyol,
            productId: Fx.sampuanId, qty: 100, grossSales: tl(12_000),
            vatRate: .yirmi, vatIncluded: true
        ))
        let ty = Engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")

        #expect(ty.netSales == tl(10_000))        // KDV hariç
        #expect(ty.netSalesIncVat == tl(12_000))  // kesinti tabanı
        #expect(ty.outputVat == tl(2000))
        // 12.000 × %20 = 2.400 KDV dahil komisyon -> net 2.000, KDV 400
        #expect(ty.commission.amount == tl(2000))
        #expect(ty.feeVat == tl(400))
        #expect(ty.kanaldaKalan == tl(8000))      // 10.000 − 2.000, KDV karışmadan
    }

    /// Kanal kesintisinin KDV'si de indirilecek KDV'ye girer
    @Test func kanalKdvsiIndirilecegeEklenir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: 0)
        s.products[0].recipe = []
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = true
        s.sales.append(SalesEntry(
            id: "sal", month: "2026-09", channelId: ChannelIds.trendyol,
            productId: Fx.sampuanId, qty: 100, grossSales: tl(12_000),
            vatRate: .yirmi, vatIncluded: true
        ))
        let kdv = Engine(s).vatStatus("2026-09")
        #expect(kdv.hesaplanan == tl(2000))
        #expect(kdv.indirilecek == tl(400))       // komisyon KDV'si
        #expect(kdv.odenecek == tl(1600))
    }

    // MARK: Geriye dönük uyum

    /// KDV girilmemiş kayıtlar "KDV yok" sayılır, hiçbir rakam değişmez
    @Test func kdvsizKayitlarAynenCalisir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.products[0].recipe = []
        s.addSale("sal", "2026-09", channel: ChannelIds.other, product: Fx.sampuanId,
                  qty: 10, gross: tl(10_000))
        let r = Engine(s).companyMonth("2026-09")
        #expect(r.gercekCiro == tl(10_000))
        #expect(r.hesaplananKdv == 0)
        #expect(r.indirilecekKdv == 0)
        #expect(Engine(s).vatStatus("2026-09").hasData == false)
    }

    /// Eski yedekte KDV alanı yoksa okuma bozulmaz
    @Test func eskiYedekOkunur() throws {
        var s = Fx.base()
        s.addSale("sal", "2026-09", channel: ChannelIds.other, product: Fx.sampuanId,
                  qty: 10, gross: tl(10_000))
        let geri = try Persistence.decode(try Persistence.encode(s))
        #expect(geri.sales.first?.vatRate == nil)
        #expect(geri.sales.first?.resolvedVatRate == .yok)
        #expect(geri.balances.isEmpty)
    }

    // MARK: Alacak / Ödenecek

    @Test func alacakOdenecekOzeti() {
        var s = kurulum()
        s.balances = [
            BalanceItem(id: "b1", kind: .alacak, source: .kanal,
                        name: "Trendyol Eylül ödemesi", amount: tl(45_000)),
            BalanceItem(id: "b2", kind: .alacak, source: .kanal,
                        name: "Shopify bekleyen", amount: tl(12_000)),
            BalanceItem(id: "b3", kind: .odenecek, source: .tedarikci,
                        name: "Kutu tedarikçisi", amount: tl(18_000)),
            BalanceItem(id: "b4", kind: .odenecek, source: .diger,
                        name: "Ödendi bu", amount: tl(9000), settled: true),
        ]
        let ozet = Engine(s).balanceSummary(month: "2026-09")

        #expect(ozet.alacaklar.count == 2)
        #expect(ozet.odenecekler.count == 1)          // ödenmiş olan listede yok
        #expect(ozet.toplamAlacak == tl(57_000))
        #expect(ozet.tahminiKdv == tl(1600))          // KDV kartıyla aynı rakam
        #expect(ozet.toplamOdenecek == tl(18_000) + tl(1600))
        #expect(ozet.net == tl(57_000) - tl(19_600))
    }

    /// KDV takibi kapalıyken tahmini KDV alacak/ödenecek listesine girmez
    @Test func kdvKapaliykenOzetteGorunmez() {
        var s = kurulum()
        s.settings.vatEnabled = false
        #expect(Engine(s).balanceSummary(month: "2026-09").tahminiKdv == 0)
    }
}

@Suite("KDV güvenlik kuralları")
struct VatSafetyTests {

    /// Devreden KDV hiçbir koşulda alacak tarafına geçmez
    @Test func devredenKdvAlacakOlarakGosterilmez() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: 0)
        s.products[0].recipe = []
        // Büyük alım, satış yok -> indirilecek KDV fazlası
        s.purchases.append(StockPurchase(
            id: "pur", date: "2026-09-01", item: .material(Fx.koliId),
            qty: 1000, unit: .adet, totalPaid: tl(60_000),
            vatRate: .yirmi, vatIncluded: true
        ))
        s.balances = [BalanceItem(id: "b", kind: .alacak, name: "Trendyol", amount: tl(10_000))]

        let e = Engine(s)
        let kdv = e.vatStatus("2026-09")
        #expect(kdv.devreden == tl(10_000))
        #expect(kdv.odenecek == 0)

        let ozet = e.balanceSummary(month: "2026-09")
        // Alacak tarafı yalnızca kullanıcının girdiği satırdan ibaret
        #expect(ozet.toplamAlacak == tl(10_000))
        #expect(ozet.tahminiKdv == 0)          // devreden KDV ödenecek listesine de girmez
        #expect(ozet.alacaklar.allSatisfy { $0.name != "KDV" })
    }

    /// Tahmini KDV yalnızca ödenecek tarafında ve yalnızca pozitifken görünür
    @Test func tahminiKdvSadeceOdenecekTarafinda() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: 0)
        s.products[0].recipe = []
        s.sales.append(SalesEntry(
            id: "sal", month: "2026-09", channelId: ChannelIds.other,
            productId: Fx.sampuanId, qty: 10, grossSales: tl(12_000),
            vatRate: .yirmi, vatIncluded: true
        ))
        let ozet = Engine(s).balanceSummary(month: "2026-09")
        #expect(ozet.tahminiKdv == tl(2000))
        #expect(ozet.toplamOdenecek == tl(2000))
        #expect(ozet.toplamAlacak == 0)
        #expect(ozet.net == -tl(2000))
    }

    /// KDV oranı her kayıtta ayrı ayrı seçilebilir; %20 yalnızca varsayılan
    @Test func kdvOraniHerKayittaFarkliOlabilir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: 0)
        s.products[0].recipe = []
        s.sales = [
            SalesEntry(id: "s20", month: "2026-09", channelId: ChannelIds.other,
                       productId: Fx.sampuanId, qty: 1, grossSales: tl(120),
                       vatRate: .yirmi, vatIncluded: true),
            SalesEntry(id: "s10", month: "2026-09", channelId: ChannelIds.other,
                       productId: Fx.sampuanId, qty: 1, grossSales: tl(110),
                       vatRate: .on, vatIncluded: true),
            SalesEntry(id: "s1", month: "2026-09", channelId: ChannelIds.other,
                       productId: Fx.sampuanId, qty: 1, grossSales: tl(101),
                       vatRate: .bir, vatIncluded: true),
            SalesEntry(id: "s0", month: "2026-09", channelId: ChannelIds.other,
                       productId: Fx.sampuanId, qty: 1, grossSales: tl(100),
                       vatRate: .yok, vatIncluded: true),
        ]
        let r = Engine(s).companyMonth("2026-09")
        #expect(r.gercekCiro == tl(400))                      // hepsi net 100 TL
        #expect(r.hesaplananKdv == tl(20) + tl(10) + tl(1))   // oranlar ayrı ayrı uygulandı

        // Varsayılan oran ayarı sadece formu doldurur, kayıtları bağlamaz
        #expect(AppSettings().defaultVatRate == .yirmi)
    }

    /// Kanal kesinti KDV oranı kanala özel ve değiştirilebilir
    @Test func kanalKesintiKdvOraniDegistirilebilir() {
        func kur(_ oran: VatRate) -> ChannelMonthResult {
            var s = Fx.base()
            s.products[0] = Fx.sampuan(cost: 0)
            s.products[0].recipe = []
            s.channels[0].commissionPct = 20
            s.channels[0].feeVatRate = oran
            s.channels[0].feesIncludeVat = true
            s.sales.append(SalesEntry(
                id: "sal", month: "2026-09", channelId: ChannelIds.trendyol,
                productId: Fx.sampuanId, qty: 100, grossSales: tl(12_000),
                vatRate: .yirmi, vatIncluded: true
            ))
            return Engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        }
        // 12.000 × %20 = 2.400 TL brüt komisyon
        #expect(kur(.yirmi).commission.amount == tl(2000))   // KDV %20 ayrılır
        #expect(kur(.yirmi).feeVat == tl(400))
        #expect(kur(.on).commission.amount == Vat.net(tl(2400), rate: .on, included: true))
        #expect(kur(.yok).commission.amount == tl(2400))     // KDV yoksa tamamı gider
        #expect(kur(.yok).feeVat == 0)
    }

    /// İki kanal farklı kesinti KDV oranı taşıyabilir
    @Test func kanallarFarkliKesintiOraniTasiyabilir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: 0)
        s.products[0].recipe = []
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yirmi
        s.channels[1].paymentPct = 10
        s.channels[1].feeVatRate = .yok           // bu kanalda kesinti KDV'si yok
        for (i, ch) in [ChannelIds.trendyol, ChannelIds.shopify].enumerated() {
            s.sales.append(SalesEntry(
                id: "s\(i)", month: "2026-09", channelId: ch,
                productId: Fx.sampuanId, qty: 10, grossSales: tl(12_000),
                vatRate: .yirmi, vatIncluded: true
            ))
        }
        let e = Engine(s)
        #expect(e.channelResult(channelId: ChannelIds.trendyol, month: "2026-09").feeVat > 0)
        #expect(e.channelResult(channelId: ChannelIds.shopify, month: "2026-09").feeVat == 0)
    }

    /// Kesinti KDV oranı girilmemiş kanal uyarı listesine düşer
    @Test func eksikKesintiOraniUyarir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: 0)
        s.products[0].recipe = []
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = nil            // girilmemiş
        s.sales.append(SalesEntry(
            id: "sal", month: "2026-09", channelId: ChannelIds.trendyol,
            productId: Fx.sampuanId, qty: 10, grossSales: tl(12_000),
            vatRate: .yirmi, vatIncluded: true
        ))
        #expect(Engine(s).channelsMissingFeeVat(month: "2026-09") == ["Trendyol"])

        s.channels[0].feeVatRate = .yirmi
        #expect(Engine(s).channelsMissingFeeVat(month: "2026-09").isEmpty)
    }

    /// KDV, nakit çıkışı ile kâr ayrımını bozmaz
    @Test func nakitKarAyrimiKorunur() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: 0)
        s.products[0].recipe = []
        s.purchases.append(StockPurchase(
            id: "pur", date: "2026-09-01", item: .material(Fx.koliId),
            qty: 100, unit: .adet, totalPaid: tl(1200),
            vatRate: .yirmi, vatIncluded: true
        ))
        s.expenses.append(Expense(id: "e", date: "2026-09-02", name: "Ajans",
                                  amount: tl(1200), category: .sabit,
                                  vatRate: .yirmi, vatIncluded: true))
        let r = Engine(s).companyMonth("2026-09")

        #expect(r.ortakGider == tl(1000))          // kâra KDV hariç girer
        #expect(r.stokAlimi == tl(1200))           // stok alımı kâra hiç girmez
        #expect(r.nakitCikisi == tl(2400))         // kasadan KDV dahil çıkar
        #expect(r.gercekKar == -tl(1000))          // sadece gider, KDV yok, alım yok
    }

    /// Başlangıç kanalları kesinti KDV oranıyla gelir ama kilitli değildir
    @Test func baslangicKanallariOranTasirAmaKilitliDegil() {
        var s = SeedData.initialState()
        #expect(s.channels.allSatisfy { $0.resolvedFeeVatRate == .yirmi })
        s.channels[0].feeVatRate = .on
        #expect(Engine(s).state.channel(ChannelIds.trendyol)?.resolvedFeeVatRate == .on)
    }
}
