import Testing
import Foundation
@testable import MirissaCore

@Suite("Rapor içe aktarma")
struct ReportImportTests {

    let shopify = """
    Name,Email,Financial Status,Created at,Lineitem quantity,Lineitem name,Lineitem price,Lineitem sku,Discount Amount
    #1001,a@x.com,paid,2026-08-03 10:22:33 +0300,2,Mirissa Şampuan 250ml,699.00,SMP-250,0.00
    #1001,,,,1,Mirissa Serum 30ml,890.00,SRM-30,
    #1002,b@x.com,paid,2026-08-05 09:00:00 +0300,1,Mirissa Şampuan 250ml,699.00,SMP-250,50.00
    #1003,c@x.com,voided,2026-08-06 09:00:00 +0300,1,Mirissa Serum 30ml,890.00,SRM-30,0.00
    #1004,d@x.com,paid,2026-09-01 12:00:00 +0300,1,Mirissa Serum 30ml,890.00,SRM-30,0.00
    """

    let trendyol = """
    Sipariş Numarası;Sipariş Tarihi;Ürün Adı;Barkod;Adet;Faturalanacak Tutar;Sipariş Statüsü
    TY1;01.08.2026 10:22;Şampuan 250 ml;8690001;1;"1.049,90";Teslim Edildi
    TY2;02.08.2026 11:00;Şampuan 250 ml;8690001;3;"3.149,70";Teslim Edildi
    TY3;03.08.2026 12:00;Şampuan 250 ml;8690001;1;"1.049,90";İptal Edildi
    """

    private func urunler() -> [Product] {
        var s = Product(id: "s", name: "Şampuan"); s.sku = "SMP-250"
        return [s, Product(id: "r", name: "Serum")]
    }

    @Test func sayiVeTarihOkuma() {
        #expect(RaporIceAktarma.tutar("1.049,90") == 104_990)
        #expect(RaporIceAktarma.tutar("699.00") == 69_900)
        #expect(RaporIceAktarma.tutar("12.500") == 1_250_000)
        #expect(RaporIceAktarma.tutar("1,234.56") == 123_456)
        #expect(RaporIceAktarma.tutar("₺99") == 9_900)
        #expect(RaporIceAktarma.tarih("2026-08-03 10:22:33 +0300") == "2026-08-03")
        #expect(RaporIceAktarma.tarih("01.08.2026 10:22") == "2026-08-01")
        #expect(RaporIceAktarma.tarih("1/9/2026") == "2026-09-01")
    }

    @Test func shopifyRaporu() {
        let t = RaporIceAktarma.oku(shopify)
        let sutun = RaporIceAktarma.sutunlariBul(t.basliklar)
        #expect(sutun[.siparisNo] == 0)
        #expect(sutun[.adet] == 4)
        #expect(sutun[.sku] == 7)
        let (kalemler, hatalar) = RaporIceAktarma.kalemler(t, sutun: sutun)
        #expect(hatalar.isEmpty)
        #expect(kalemler.count == 5)
        let u = urunler()
        var eslesme: [String: Id] = [:]
        for k in kalemler { eslesme[k.urunAnahtari] = RaporIceAktarma.eslestirmeOnerisi(k.urunAnahtari, ad: k.urunAdi, urunler: u) }
        #expect(eslesme["SMP-250"] == "s")
        #expect(eslesme["SRM-30"] == "r")
        let r = RaporIceAktarma.donustur(kalemler, kanalId: "shopify", eslesme: eslesme, mevcutAylar: [], kdvOrani: .yirmi)
        #expect(r.iptalSiparis == 1)
        let agustosSampuan = r.satislar.first { $0.month == "2026-08" && $0.productId == "s" }!
        #expect(agustosSampuan.qty == 3)                     // 2 + 1
        #expect(agustosSampuan.grossSales == tl(699 * 3))
        #expect(agustosSampuan.discount == tl(50))
        let agustos = r.aylar.first { $0.month == "2026-08" }!
        #expect(agustos.orderCount == 2)                     // #1001, #1002 (#1003 iptal)
        #expect(agustos.bigOrderCount == 1)                  // #1001: 3 ürün → 2 koli
        #expect(r.aylar.first { $0.month == "2026-09" }?.orderCount == 1)
    }

    @Test func trendyolRaporuNoktaliVirgulVeTurkceSayi() {
        let t = RaporIceAktarma.oku(trendyol)
        let sutun = RaporIceAktarma.sutunlariBul(t.basliklar)
        let (kalemler, _) = RaporIceAktarma.kalemler(t, sutun: sutun)
        let r = RaporIceAktarma.donustur(kalemler, kanalId: "ty", eslesme: ["8690001": "s"],
                                         mevcutAylar: [], kdvOrani: .yirmi)
        let s = r.satislar.first!
        #expect(s.qty == 4)
        #expect(s.grossSales == tl(4_199.60))
        #expect(r.aylar.first?.orderCount == 2)
        #expect(r.aylar.first?.bigOrderCount == 1)
        #expect(r.iptalSiparis == 1)
    }

    @Test @MainActor func ikiKezAktarmakSatislariIkiyeKatlamaz() {
        var s = Fx.base()
        s.products[0].sku = "8690001"
        let st = AppStore.inMemory(s)
        let t = RaporIceAktarma.oku(trendyol)
        let (kalemler, _) = RaporIceAktarma.kalemler(t, sutun: RaporIceAktarma.sutunlariBul(t.basliklar))
        let r = RaporIceAktarma.donustur(kalemler, kanalId: ChannelIds.trendyol,
                                         eslesme: ["8690001": Fx.sampuanId], mevcutAylar: [], kdvOrani: .yirmi)
        st.raporuKaydet(r, kanalId: ChannelIds.trendyol)
        st.raporuKaydet(r, kanalId: ChannelIds.trendyol)
        #expect(st.state.sales.filter { $0.channelId == ChannelIds.trendyol }.count == 1)
        #expect(st.state.channelMonth(month: "2026-08", channelId: ChannelIds.trendyol)?.orderCount == 2)
    }
}
