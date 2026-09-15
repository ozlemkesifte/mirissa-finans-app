import Testing
import Foundation
@testable import MirissaCore

/// Yarıda bırakılan soru-cevap akışı kaybolmaz: cevaplar diske yazılır,
/// uygulama tamamen kapansa bile kaldığı adımdan devam eder.
@Suite("Yarım kalan akışlar", .serialized)
@MainActor
struct WizardDraftTests {

    /// Bir akışın kendi durumu — gerçek akışlar da böyle saklar
    struct KanalTaslak: Codable, Hashable {
        var adim: String
        var seciliUrunler: [Id]
        var fiyatlar: [Id: Kurus]
        var komisyon: Double
    }

    private static func store() -> AppStore { AppStore.inMemory(SeedData.initialState()) }

    // MARK: İstenen senaryo

    /// 1) Akış 5. adımda kapanır 2) uygulama yeniden açılır
    /// 3) "Devam et" 4) aynı cevaplarla 6. adımdan devam eder
    @Test func besinciAdimdaKapanipAltincidanDevamEder() throws {
        let dosya = FileStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mirissa-draft-\(UUID().uuidString).json"))

        // --- 1. oturum: 5. adıma kadar cevaplanır, sonra uygulama kapanır ---
        do {
            let store = AppStore(file: dosya, saveDelay: .zero)
            let taslak = KanalTaslak(
                adim: "kargoVarMi",
                seciliUrunler: [SeedData.P.sampuan, SeedData.P.serum],
                fiyatlar: [SeedData.P.sampuan: Money.fromTL(749)],
                komisyon: 4
            )
            let d = try #require(WizardDraft.make(
                kind: .kanalKurulumu, subjectId: ChannelIds.trendyol,
                title: "Trendyol kurulumu", step: 5, totalSteps: 12,
                updatedAt: "2026-09-15", state: taslak
            ))
            store.saveDraft(d)
            store.flush()
        }

        // --- 2. oturum: uygulama sıfırdan açılıyor ---
        let yeni = AppStore(file: dosya)
        let geri = try #require(yeni.draft(.kanalKurulumu, subjectId: ChannelIds.trendyol))
        #expect(geri.step == 5)
        #expect(geri.totalSteps == 12)
        #expect(geri.title == "Trendyol kurulumu")
        #expect(geri.progressLabel == "5/12 adım tamamlandı")

        // --- 3-4. "Devam et": cevaplar korunmuş, 6. adıma geçilir ---
        var durum = try #require(geri.decode(KanalTaslak.self))
        #expect(durum.adim == "kargoVarMi")
        #expect(durum.seciliUrunler == [SeedData.P.sampuan, SeedData.P.serum])
        #expect(durum.fiyatlar[SeedData.P.sampuan] == Money.fromTL(749))
        #expect(durum.komisyon == 4)

        durum.adim = "kargoDeger"
        let ilerleyen = try #require(WizardDraft.make(
            kind: .kanalKurulumu, subjectId: ChannelIds.trendyol,
            title: "Trendyol kurulumu", step: 6, totalSteps: 12, state: durum
        ))
        yeni.saveDraft(ilerleyen)
        #expect(yeni.draft(.kanalKurulumu, subjectId: ChannelIds.trendyol)?.step == 6)
        #expect(yeni.state.drafts.count == 1)   // yeni kayıt değil, aynısı güncellendi
    }

    // MARK: Akışlar birbirini ezmez

    @Test func farkliAkislarAyriSaklanir() throws {
        let store = Self.store()
        store.saveDraft(try #require(WizardDraft.make(
            kind: .ilkKurulum, title: "İlk kurulum", step: 3, totalSteps: 14,
            state: ["x": 1])))
        store.saveDraft(try #require(WizardDraft.make(
            kind: .fiyatGuncelleme, title: "Fiyat güncelleme", step: 2, totalSteps: 4,
            state: ["y": 2])))
        #expect(store.state.drafts.count == 2)
        #expect(store.draft(.ilkKurulum)?.step == 3)
        #expect(store.draft(.fiyatGuncelleme)?.step == 2)
    }

    /// Aynı akışın iki kanalı ayrı taslak tutar
    @Test func ayniAkisFarkliKonuIcinAyriTaslak() throws {
        let store = Self.store()
        store.saveDraft(try #require(WizardDraft.make(
            kind: .kanalKurulumu, subjectId: "trendyol", title: "Trendyol kurulumu",
            step: 4, totalSteps: 12, state: ["a": 1])))
        store.saveDraft(try #require(WizardDraft.make(
            kind: .kanalKurulumu, subjectId: "hepsiburada", title: "Hepsiburada kurulumu",
            step: 1, totalSteps: 12, state: ["a": 2])))
        #expect(store.state.drafts.count == 2)
        #expect(store.draft(.kanalKurulumu, subjectId: "trendyol")?.step == 4)
        #expect(store.draft(.kanalKurulumu, subjectId: "hepsiburada")?.step == 1)
    }

    // MARK: Temizlenme

    @Test func tamamlanincaTaslakSilinir() throws {
        let store = Self.store()
        store.saveDraft(try #require(WizardDraft.make(
            kind: .yeniIslem, subjectId: "satis", title: "Satış girişi",
            step: 3, totalSteps: 6, state: ["a": 1])))
        #expect(store.draft(.yeniIslem, subjectId: "satis") != nil)
        store.clearDraft(.yeniIslem, subjectId: "satis")
        #expect(store.draft(.yeniIslem, subjectId: "satis") == nil)
        #expect(store.state.drafts.isEmpty)
    }

    @Test func iptalEdilenTaslakDiskteDeKalmaz() throws {
        let dosya = FileStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mirissa-draft-\(UUID().uuidString).json"))
        do {
            let store = AppStore(file: dosya, saveDelay: .zero)
            store.saveDraft(try #require(WizardDraft.make(
                kind: .stokKurulumu, title: "Stok sayımı", step: 2, totalSteps: 3,
                state: ["a": 1])))
            store.clearDraft(.stokKurulumu)
            store.flush()
        }
        #expect(AppStore(file: dosya).state.drafts.isEmpty)
    }

    // MARK: Dayanıklılık

    /// Akışın alanları değişirse taslak okunamaz; uygulama çökmez, akış baştan başlar
    @Test func bozukTaslakCokertmez() throws {
        let d = try #require(WizardDraft.make(kind: .ilkKurulum, title: "İlk kurulum",
                                              step: 1, totalSteps: 5, state: ["a": 1]))
        #expect(d.decode(KanalTaslak.self) == nil)
    }

    /// Taslaklar eski yedeklerde yok — okuma bozulmamalı
    @Test func eskiYedekteTaslakAlaniYok() throws {
        let json = """
        {"materials":[],"products":[],"channels":[],"sales":[],"expenses":[]}
        """
        let s = try JSONDecoder().decode(AppState.self, from: Data(json.utf8))
        #expect(s.drafts.isEmpty)
    }

    @Test func taslakYedekTurundenGecer() throws {
        var s = SeedData.initialState()
        s.drafts = [try #require(WizardDraft.make(
            kind: .kanalKurulumu, subjectId: "n11", title: "N11 kurulumu",
            step: 7, totalSteps: 12, state: ["komisyon": 12]))]
        let geri = try Persistence.decode(try Persistence.encode(s))
        #expect(geri.drafts.first?.step == 7)
        #expect(geri.drafts.first?.decode([String: Int].self)?["komisyon"] == 12)
    }
}
