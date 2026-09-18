import Testing
import Foundation
@testable import MirissaCore

@Suite("Yedek, ay kilidi ve değişiklik günlüğü", .serialized)
@MainActor
struct BackupLockLogTests {

    private func geciciKok() -> URL {
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirissa-yedek-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func store(_ kok: URL, _ s: AppState) -> AppStore {
        let st = AppStore(file: FileStore(url: kok.appendingPathComponent("veri.json")),
                          saveDelay: .zero, attachmentsDirectory: kok)
        st.replace(s)
        return st
    }

    private func faturaliDurum(_ kok: URL) throws -> AppState {
        var s = Golden.senaryo()
        let ekler = kok.appendingPathComponent("ekler", isDirectory: true)
        try FileManager.default.createDirectory(at: ekler, withIntermediateDirectories: true)
        try Data("%PDF fatura".utf8).write(to: ekler.appendingPathComponent("fatura1.pdf"))
        s.expenses[0].attachment = "fatura1.pdf"
        return s
    }

    @Test func yedekFaturalarlaBirlikteGeriGelir() throws {
        let a = geciciKok(), b = geciciKok()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let kaynak = store(a, try faturaliDurum(a))
        let paket = try kaynak.yedekPaketi()

        let hedef = store(b, SeedData.initialState())
        let onizleme = try hedef.yedegiOku(paket)
        #expect(onizleme.satis == kaynak.state.sales.count)
        #expect(onizleme.fatura == 1)
        #expect(onizleme.atlanan.isEmpty)
        try hedef.geriYukle(onizleme)

        #expect(hedef.state.sales == kaynak.state.sales)
        #expect(hedef.state.expenses == kaynak.state.expenses)
        #expect(hedef.engine.companyMonth("2026-09").gercekKar
                == kaynak.engine.companyMonth("2026-09").gercekKar)
        #expect(FileManager.default.fileExists(atPath:
            b.appendingPathComponent("ekler/fatura1.pdf").path))
        // Geri yüklemeden önceki veri kenara alındı
        #expect(hedef.otomatikYedekler.contains { $0.lastPathComponent.contains("geri-yukleme-oncesi") })
    }

    @Test func eskiDuzJsonYedekKabulEdilirBozukSatirlarSoylenir() throws {
        let k = geciciKok()
        defer { try? FileManager.default.removeItem(at: k) }
        var s = Golden.senaryo()
        s.sales.append(SalesEntry(id: "sahipsiz", month: "2026-09", channelId: "yok",
                                  productId: "yok", qty: 1, grossSales: tl(100)))
        let duz = try Persistence.encode(s)
        let o = try store(k, SeedData.initialState()).yedegiOku(duz)
        #expect(o.atlanan.contains("1 satış kaydı"))
        #expect(o.satis == s.sales.count - 1)
    }

    @Test func otomatikYedekGundeBirKezAlinirVeOnDortTaneSaklanir() throws {
        let k = geciciKok()
        defer { try? FileManager.default.removeItem(at: k) }
        let st = store(k, Golden.senaryo())
        for gun in 1...20 {
            st.otomatikYedekGerekirse(String(format: "2026-08-%02d", gun))
        }
        st.otomatikYedekGerekirse("2026-08-20")   // aynı gün ikinci kez: yeni dosya yok
        let otomatik = st.otomatikYedekler.filter { $0.lastPathComponent.contains("otomatik") }
        #expect(otomatik.count == 14)
        #expect(st.state.settings.ek.sonOtomatikYedek == "2026-08-20")
    }

    @Test func kilitliAyinKayitlariDegismez() {
        let k = geciciKok()
        defer { try? FileManager.default.removeItem(at: k) }
        var s = Golden.senaryo()
        s.settings.ek.kilitliAylar = ["2026-09"]
        let st = store(k, s)
        let once = st.state.sales.count

        st.addSale(SalesEntry(month: "2026-09", channelId: s.channels[0].id,
                              productId: s.products[0].id, qty: 1, grossSales: tl(100)))
        #expect(st.state.sales.count == once)
        #expect(st.sonHata?.contains("kilitli") == true)

        // Kilitli olmayan ay serbest
        st.addSale(SalesEntry(month: "2026-10", channelId: s.channels[0].id,
                              productId: s.products[0].id, qty: 1, grossSales: tl(100)))
        #expect(st.state.sales.count == once + 1)
        #expect(st.sonHata == nil)

        // Düzenli giderin tutarını değiştirmek kilitli ayı da değiştirir → engellenir
        if let g = st.state.expenses.first(where: { $0.isRecurring }) {
            var yeni = g
            yeni.amount += tl(1)
            st.updateExpense(yeni)
            #expect(st.state.expenses.first { $0.id == g.id }?.amount == g.amount)
        }
    }

    @Test func degisiklikGunlugeYazilir() {
        let k = geciciKok()
        defer { try? FileManager.default.removeItem(at: k) }
        let st = store(k, Golden.senaryo())
        st.addSale(SalesEntry(month: "2026-10", channelId: st.state.channels[0].id,
                              productId: st.state.products[0].id, qty: 2, grossSales: tl(500)))
        let son = st.state.changeLog.last
        #expect(son?.tur == .eklendi)
        #expect(son?.alan == "Satış")
        #expect(son?.aciklama.contains("2026-10") == true)
    }

    @Test func eskiDosyaYeniAlanlarOlmadanAcilir() throws {
        let veri = try Persistence.encode(Golden.senaryo())
        var json = try JSONSerialization.jsonObject(with: veri) as! [String: Any]
        var st = json["state"] as! [String: Any]
        st.removeValue(forKey: "changeLog")
        var ayar = st["settings"] as! [String: Any]
        ayar.removeValue(forKey: "ek")
        st["settings"] = ayar
        json["state"] = st
        let eski = try JSONSerialization.data(withJSONObject: json)
        let s = try Persistence.decode(eski)
        #expect(s.changeLog.isEmpty)
        #expect(s.settings.ek == EkAyarlar())
    }
}
