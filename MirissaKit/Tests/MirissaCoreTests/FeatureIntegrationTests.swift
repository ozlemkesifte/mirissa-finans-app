import Testing
import Foundation
@testable import MirissaCore

/// Yeni özellikler mevcut hesapları değiştirmemeli ve birlikte çalışmalı
@Suite("Yeni özellikler: mevcut hesapları bozmaz, birlikte çalışır")
struct FeatureIntegrationTests {

    /// Bütün yeni ayarlar açık — ama kâr, stok, KDV rakamları aynı kalmalı
    private func ozellikliDurum() -> AppState {
        var s = Golden.senaryo()
        s.settings.ek.vergiOrani = 25
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kasaBakiye = tl(150_000)
        s.settings.ek.kasaTarih = "2026-09-15"
        s.settings.ek.hatirlatmalarAcik = true
        s.settings.ek.kilitliAylar = ["2026-07"]
        s.settings.ek.sonYedekPaylasim = "2026-09-01"
        s.settings.ek.aySonuIsaretleri = ["2026-08": ["gider"]]
        s.changeLog = [ChangeLogEntry(zaman: "2026-09-01T10:00:00Z", tur: .eklendi, alan: "Satış", aciklama: "x")]
        for i in s.materials.indices { s.materials[i].tedarikSuresiGun = 14; s.materials[i].minSiparis = 100 }
        for i in s.products.indices { s.products[i].tedarikSuresiGun = 30 }
        for i in s.channelMonths.indices { s.channelMonths[i].payoutActual = tl(1_000) }
        return s
    }

    @Test func mevcutRakamlarDegismez() {
        let eski = Engine(Golden.senaryo())
        let yeni = Engine(ozellikliDurum())
        for ay in ["2026-07", "2026-08", "2026-09", "2026-10"] {
            let a = eski.companyMonth(ay), b = yeni.companyMonth(ay)
            #expect(a.gercekKar == b.gercekKar)
            #expect(a.toplamGider == b.toplamGider)
            #expect(a.nakitCikisi == b.nakitCikisi)
            #expect(eski.vatStatus(ay) == yeni.vatStatus(ay))
            #expect(eski.plan(month: ay, today: "2026-09-15").targets == yeni.plan(month: ay, today: "2026-09-15").targets)
        }
        for m in Golden.senaryo().materials {
            #expect(eski.balance(.material(m.id)) == yeni.balance(.material(m.id)))
        }
    }

    @Test func yeniAlanlarYedektenGeriGelir() throws {
        var s = ozellikliDurum()
        var p = s.purchases[0]
        p.odeme = OdemePlani.esit(toplam: tl(6_000), pesinat: tl(1_000), taksitSayisi: 2, ilkVade: "2026-10-15")
        s.purchases[0] = p
        let o = try Backup.oku(try Backup.paket(s, ekURL: { URL(fileURLWithPath: "/yok/\($0)") }))
        #expect(o.state.settings.ek == s.settings.ek)
        #expect(o.state.purchases[0].odeme == p.odeme)
        #expect(o.state.channelMonths.map(\.payoutActual) == s.channelMonths.map(\.payoutActual))
        #expect(o.state.materials.map(\.tedarikSuresiGun) == s.materials.map(\.tedarikSuresiGun))
        #expect(o.state.changeLog == s.changeLog)
    }

    @Test func ozelliklerBirbirineBaglanir() {
        var s = ozellikliDurum()
        // Vadeli alım → nakit tahminindeki bilinen ödemelere ve hatırlatmalara girer
        var p = StockPurchase(id: "vade", date: "2026-09-10", item: .material(s.materials[0].id), qty: 100,
                              unit: .adet, totalPaid: tl(5_000))
        p.odeme = OdemePlani(pesinat: 0, taksitler: [Taksit(id: "t", vade: "2026-10-20", tutar: tl(5_000))])
        s.purchases.append(p)
        let e = Engine(s)
        let nakit = e.nakitTahmini(bugun: "2026-09-15")!
        #expect(nakit.bilinenKalemler.contains { $0.id.contains("taksit:vade") && $0.tutar == -tl(5_000) })
        #expect(e.hatirlatmalar(bugun: "2026-09-15").contains { $0.id == "taksit-vade#t" })
        // Vergi karşılığı nakit tahminine geçici vergi olarak girer (çeyrekte kâr varsa)
        #expect(e.vergiKarsiligi(month: "2026-09", today: "2026-09-15") != nil)
        // Ürün kârlılığı kanal toplamlarını tutar
        let l = e.urunKanalKarliligi(month: "2026-09")
        for c in e.companyMonth("2026-09").channels where l.contains(where: { $0.channelId == c.channelId }) {
            #expect(l.filter { $0.channelId == c.channelId }.reduce(0) { $0 + $1.kalan } == c.kanaldaKalan)
        }
    }
}
