import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MirissaCore

/// Ek testleri `AttachmentStore.overrideDirectory` ortak ayarını değiştirir.
/// Tüm alt gruplar bu tek sıralı grup içinde çalışır; aksi halde iki grup aynı
/// anda ayarı değiştirip birbirinin dosyasını kaybettirir.
@Suite("Ek testleri", .serialized)
enum EkTestleri {}

extension EkTestleri {
@Suite("Fatura ekleri", .serialized)
struct AttachmentTests {

    private func geciciKlasor() -> URL {
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirissa-ek-test-\(UUID().uuidString)")
        AttachmentStore.overrideDirectory = u
        return u
    }

    /// 600×600 kırmızı PNG üretir
    private func ornekGorsel(_ boyut: Int = 600) -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: boyut, height: boyut, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: cs, components: [1, 0, 0, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: boyut, height: boyut))
        let img = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    @Test func gorselKaydedilirVeKuculur() throws {
        let dir = geciciKlasor()
        defer { try? FileManager.default.removeItem(at: dir); AttachmentStore.overrideDirectory = nil }

        let buyuk = ornekGorsel(4000)
        let ad = try AttachmentStore.save(data: buyuk, suggestedExtension: "png")
        #expect(ad.hasSuffix(".jpg"))          // fotoğraflar JPEG'e çevrilir
        #expect(AttachmentStore.exists(ad))
        let kayitli = try Data(contentsOf: AttachmentStore.url(ad))
        #expect(kayitli.count < buyuk.count)   // küçültüldü

        let src = CGImageSourceCreateWithData(kayitli as CFData, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        #expect((props[kCGImagePropertyPixelWidth] as! Int) <= 2000)
    }

    @Test func pdfOldugunuGibiSaklanir() throws {
        let dir = geciciKlasor()
        defer { try? FileManager.default.removeItem(at: dir); AttachmentStore.overrideDirectory = nil }

        let veri = Data("%PDF-1.4 sahte".utf8)
        let ad = try AttachmentStore.save(data: veri, suggestedExtension: "pdf")
        #expect(ad.hasSuffix(".pdf"))
        #expect(AttachmentStore.isPDF(ad))
        #expect(try Data(contentsOf: AttachmentStore.url(ad)) == veri)
    }

    @Test func yetimDosyalarTemizlenir() throws {
        let dir = geciciKlasor()
        defer { try? FileManager.default.removeItem(at: dir); AttachmentStore.overrideDirectory = nil }

        let a = try AttachmentStore.save(data: ornekGorsel(), suggestedExtension: "png")
        let b = try AttachmentStore.save(data: ornekGorsel(), suggestedExtension: "png")
        AttachmentStore.prune(keeping: [a])
        #expect(AttachmentStore.exists(a))
        #expect(!AttachmentStore.exists(b))
    }

    /// Şablon faturası, aya özel fatura ve alım faturası birlikte toplanır
    @Test func butunFaturalarBulunur() {
        var s = SeedData.initialState()
        var duzenli = Expense(id: "e1", date: "2026-09-01", name: "Ajans", amount: tl(20_000),
                              category: .sabit, recurrence: .aylik, attachment: "sablon.jpg")
        duzenli.overrides["2026-10"] = ExpenseOverride(attachment: "ekim.jpg")
        s.expenses.append(duzenli)
        s.purchases.append(StockPurchase(id: "p1", date: "2026-09-02",
                                         item: .material(SeedData.M.koli), qty: 100, unit: .adet,
                                         totalPaid: tl(1000), attachment: "alim.pdf"))
        #expect(s.attachmentNames == ["sablon.jpg", "ekim.jpg", "alim.pdf"])
    }

    /// Aya özel tutar değişikliği o ayın faturasını silmez
    @Test func ayaOzelTutarFaturayiSilmez() {
        var s = SeedData.initialState()
        var e = Expense(id: "e1", date: "2026-09-01", name: "Ajans", amount: tl(20_000),
                        category: .sabit, recurrence: .aylik)
        e.overrides["2026-10"] = ExpenseOverride(attachment: "ekim.jpg")
        s.expenses.append(e)

        // Store.overrideExpense'in yaptığı işlem
        var ov = s.expenses[0].overrides["2026-10"] ?? ExpenseOverride()
        ov.amount = tl(25_000)
        s.expenses[0].overrides["2026-10"] = ov.isEmpty ? nil : ov

        #expect(s.expenses[0].overrides["2026-10"]?.attachment == "ekim.jpg")
        #expect(s.expenses[0].overrides["2026-10"]?.amount == tl(25_000))
        #expect(Engine(s).expenseInstances(month: "2026-10").first?.attachment == "ekim.jpg")
        #expect(Engine(s).expenseInstances(month: "2026-09").first?.attachment == nil)
    }

    /// Eski yedekte fatura alanı yoksa okuma bozulmaz
    @Test func eskiYedekteFaturaAlaniYok() throws {
        var s = SeedData.initialState()
        s.expenses.append(Expense(id: "e1", date: "2026-09-01", name: "Ajans",
                                  amount: tl(20_000), category: .sabit))
        let geri = try Persistence.decode(try Persistence.encode(s))
        #expect(geri.expenses.first?.attachment == nil)
        #expect(geri.attachmentNames.isEmpty)
    }
}

}

extension EkTestleri {
/// Bir deponun temizliği başka bir deponun fatura dosyasını silmemeli.
/// (CI'da paralel çalışan testlerin birbirinin dosyasını sildiği bulundu.)
@Suite("Ek klasörü yalıtımı", .serialized)
@MainActor
struct AttachmentIsolationTests {

    @Test func baskaDepoTemizligiDosyayiSilmez() throws {
        let ortak = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirissa-ortak-\(UUID().uuidString)")
        AttachmentStore.overrideDirectory = ortak
        defer {
            try? FileManager.default.removeItem(at: ortak)
            AttachmentStore.overrideDirectory = nil
        }
        // Birinci taraf ortak klasöre bir fatura kaydediyor
        let dosya = try AttachmentStore.save(data: Data("%PDF-1.4 x".utf8),
                                             suggestedExtension: "pdf")
        #expect(AttachmentStore.exists(dosya))

        // Aynı anda başka bir test deposu kayıt silip temizlik yapıyor
        let baska = AppStore.inMemory(Golden.senaryo())
        baska.deletePurchase("pur_g1")
        baska.deleteExpense("exp_g2")
        baska.pruneAttachments()

        // Ortak klasördeki dosya yerinde kalmalı
        #expect(AttachmentStore.exists(dosya))
    }

    @Test func depoKendiKlasorundekiYetimiTemizler() throws {
        let kok = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirissa-kendi-\(UUID().uuidString)")
        let ekler = kok.appendingPathComponent("ekler", isDirectory: true)
        try FileManager.default.createDirectory(at: ekler, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: kok) }
        let yetim = ekler.appendingPathComponent("yetim.pdf")
        try Data("x".utf8).write(to: yetim)

        let st = AppStore(file: FileStore(url: kok.appendingPathComponent("veri.json")),
                          saveDelay: .zero, attachmentsDirectory: kok)
        st.pruneAttachments()
        #expect(!FileManager.default.fileExists(atPath: yetim.path))
    }
}
}
