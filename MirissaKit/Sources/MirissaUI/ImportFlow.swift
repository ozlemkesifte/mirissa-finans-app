import SwiftUI
import UniformTypeIdentifiers
import MirissaCore

/// Trendyol / Shopify sipariş raporunu içe aktarma: dosya → kanal → sütunlar → ürünler → özet
struct RaporIceAktarmaAkisi: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Adim { case dosya, sutunlar, urunler, ozet }
    @State private var adim: Adim = .dosya
    @State private var dosyaSec = false
    @State private var kanalId: Id = ""
    @State private var tablo: RaporIceAktarma.Tablo?
    @State private var sutun: [RaporIceAktarma.Alan: Int] = [:]
    @State private var eslesme: [String: Id] = [:]
    @State private var hata: String?

    private var cozum: (kalemler: [RaporIceAktarma.Kalem], hatalar: [RaporIceAktarma.Hata]) {
        tablo.map { RaporIceAktarma.kalemler($0, sutun: sutun) } ?? ([], [])
    }

    /// Rapordaki farklı ürünler: anahtar, ad, toplam adet
    private var raporUrunleri: [(anahtar: String, ad: String, adet: Double)] {
        var sira: [String] = []
        var bilgi: [String: (String, Double)] = [:]
        for k in cozum.kalemler where !k.iptal {
            if bilgi[k.urunAnahtari] == nil { sira.append(k.urunAnahtari); bilgi[k.urunAnahtari] = (k.urunAdi, 0) }
            bilgi[k.urunAnahtari]!.1 += k.adet
        }
        return sira.map { ($0, bilgi[$0]!.0, bilgi[$0]!.1) }
    }

    private var sonuc: RaporIceAktarma.Sonuc {
        RaporIceAktarma.donustur(cozum.kalemler, kanalId: kanalId, eslesme: eslesme,
                                 mevcutAylar: store.state.channelMonths,
                                 kdvOrani: store.state.settings.vatEnabled ? store.state.settings.defaultVatRate : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch adim {
                case .dosya: dosyaAdimi
                case .sutunlar: sutunAdimi
                case .urunler: urunAdimi
                case .ozet: ozetAdimi
                }
                if let hata { Section { Text(hata).foregroundStyle(Palette.zarar) } }
            }
            .navigationTitle("Rapordan içe aktar")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
            }
            .fileImporter(isPresented: $dosyaSec,
                          allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { r in
                guard case let .success(url) = r else { return }
                let erisim = url.startAccessingSecurityScopedResource()
                defer { if erisim { url.stopAccessingSecurityScopedResource() } }
                guard let veri = try? Data(contentsOf: url) else { hata = "Dosya okunamadı."; return }
                let metin = String(data: veri, encoding: .utf8)
                    ?? String(data: veri, encoding: .windowsCP1254)
                    ?? String(decoding: veri, as: UTF8.self)
                let t = RaporIceAktarma.oku(metin)
                guard !t.basliklar.isEmpty, !t.satirlar.isEmpty else { hata = "Dosyada satır bulunamadı."; return }
                tablo = t
                sutun = RaporIceAktarma.sutunlariBul(t.basliklar)
                hata = nil
                adim = .sutunlar
            }
            .onAppear { if kanalId.isEmpty { kanalId = store.state.activeChannels.first?.id ?? "" } }
        }
    }

    // MARK: 1 — Kanal ve dosya

    private var dosyaAdimi: some View {
        Group {
            Section {
                Picker("Kanal", selection: $kanalId) {
                    ForEach(store.state.activeChannels) { Text($0.name).tag($0.id) }
                }
                Button { dosyaSec = true } label: { Label("Rapor dosyasını seç (CSV)", systemImage: "doc.badge.plus") }
            } footer: {
                Text("Shopify: Siparişler → Dışa aktar → CSV. Trendyol: Siparişler → Excel'e aktar; dosyayı Excel ya da "
                     + "Numbers'ta açıp \"CSV olarak kaydet\". Her satır bir sipariş kalemi olmalı. "
                     + "Aynı kanalın aynı aylarındaki eski satış kayıtları bu raporla değiştirilir.")
            }
        }
    }

    // MARK: 2 — Sütunlar

    private var sutunAdimi: some View {
        Group {
            Section {
                ForEach(RaporIceAktarma.Alan.allCases, id: \.self) { alan in
                    Picker(alan.ad, selection: Binding(
                        get: { sutun[alan] ?? -1 },
                        set: { sutun[alan] = $0 < 0 ? nil : $0 })) {
                        Text("Yok").tag(-1)
                        ForEach(Array((tablo?.basliklar ?? []).enumerated()), id: \.offset) { i, b in
                            Text(b).tag(i)
                        }
                    }
                }
            } header: { Text("Sütunlar") } footer: {
                Text("\(tablo?.satirlar.count ?? 0) satır okundu. Otomatik bulunan sütunları kontrol et; "
                     + "sipariş numarası, tarih, ürün ve adet ile birim fiyat ya da satır tutarı gerekli.")
            }
            let (k, h) = cozum
            Section {
                LabeledRow("Okunan kalem", "\(k.count)")
                if !h.isEmpty { LabeledRow("Okunamayan satır", "\(h.count)", tone: Palette.uyari) }
                Button("Devam") {
                    eslesme = [:]
                    for u in raporUrunleri {
                        if let p = RaporIceAktarma.eslestirmeOnerisi(u.anahtar, ad: u.ad, urunler: store.state.activeProducts) {
                            eslesme[u.anahtar] = p
                        }
                    }
                    adim = .urunler
                }
                .disabled(k.isEmpty || sutun[.tarih] == nil || (sutun[.urun] == nil && sutun[.sku] == nil))
            }
        }
    }

    // MARK: 3 — Ürün eşleştirme

    private var urunAdimi: some View {
        Group {
            Section {
                ForEach(raporUrunleri, id: \.anahtar) { u in
                    Picker(selection: Binding(get: { eslesme[u.anahtar] ?? "" },
                                              set: { eslesme[u.anahtar] = $0.isEmpty ? nil : $0 })) {
                        Text("Atla").tag("")
                        ForEach(store.state.activeProducts) { Text($0.name).tag($0.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.ad).font(.footnote)
                            Text("\(Int(u.adet)) adet" + (u.ad != u.anahtar ? " · \(u.anahtar)" : ""))
                                .font(.caption2).foregroundStyle(Palette.inkFaint)
                        }
                    }
                }
            } header: { Text("Ürünleri eşleştir") } footer: {
                Text("Rapordaki her ürünün hangi ürünün olduğunu seç. Setleri de set olarak eşleştir. "
                     + "\"Atla\" dediklerin kaydedilmez. Barkod eşleşmeleri ürüne kaydedilir; bir dahaki sefere kendiliğinden bulunur.")
            }
            Section {
                Button("Özete geç") { adim = .ozet }.disabled(eslesme.isEmpty)
                Button("Geri") { adim = .sutunlar }
            }
        }
    }

    // MARK: 4 — Özet ve kayıt

    private var ozetAdimi: some View {
        let r = sonuc
        let degisecek = store.state.sales.filter { $0.channelId == kanalId && r.aylarListesi.contains($0.month) }.count
        return Group {
            ForEach(r.aylarListesi, id: \.self) { ay in
                let s = r.satislar.filter { $0.month == ay }
                let cm = r.aylar.first { $0.month == ay }
                Section(Dates.displayMonth(ay)) {
                    LabeledRow("Satış (KDV dahil)", s.reduce(0) { $0 + $1.netSales }.tl, strong: true)
                    LabeledRow("Ürün", "\(Int(s.reduce(0) { $0 + $1.qty })) adet")
                    LabeledRow("Sipariş", "\(cm?.orderCount ?? 0)")
                    LabeledRow("3+ ürünlü sipariş (2 koli)", "\(cm?.bigOrderCount ?? 0)")
                }
            }
            Section {
                if r.iptalSiparis > 0 { LabeledRow("İptal edilen sipariş (alınmadı)", "\(r.iptalSiparis)") }
                if r.atlananKalem > 0 { LabeledRow("Eşleşmediği için atlanan kalem", "\(r.atlananKalem)", tone: Palette.uyari) }
                if degisecek > 0 {
                    Text("Bu aylardaki \(degisecek) eski satış kaydı raporla değiştirilecek.")
                        .font(.footnote).foregroundStyle(Palette.uyari)
                }
                Text("İadeler raporda ayrı gelmez; iade varsa satış kaydını açıp ekle.")
                    .font(.caption).foregroundStyle(Palette.inkFaint)
                Button("Kaydet") { kaydet(r) }.font(.body.weight(.semibold))
                Button("Geri") { adim = .urunler }
            }
        }
    }

    private func kaydet(_ r: RaporIceAktarma.Sonuc) {
        // Barkod sütunu varsa eşleşmeyi ürüne kaydet: bir dahaki sefere kendiliğinden bulunur
        if sutun[.sku] != nil {
            for (anahtar, urunId) in eslesme {
                if var p = store.state.product(urunId), (p.sku ?? "").isEmpty {
                    p.sku = anahtar
                    store.updateProduct(p)
                }
            }
        }
        store.raporuKaydet(r, kanalId: kanalId)
        if store.sonHata == nil { dismiss() }
    }
}
