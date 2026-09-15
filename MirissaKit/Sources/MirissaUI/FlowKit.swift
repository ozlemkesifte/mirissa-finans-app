import SwiftUI
import MirissaCore

/// Tek soruluk adım ekranı. Bütün rehberli akışlar bunu kullanır.
struct SoruAdimi<Content: View>: View {
    var soru: String
    var aciklama: String?
    /// İlerleme çubuğu için; nil ise gösterilmez
    var adim: Int?
    var toplam: Int?
    var ileriBaslik: String = "Devam"
    var ileriAktif: Bool = true
    /// nil ise geri butonu görünmez
    var geri: (() -> Void)?
    var vazgec: (() -> Void)?
    var ileri: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ust
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.gap) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(soru)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let aciklama {
                            Text(aciklama)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    content
                    Color.clear.frame(height: 8)
                }
                .padding(Metrics.pad)
            }
            .screenBackground()
            if let ileri {
                VStack(spacing: 0) {
                    BigButton(ileriBaslik, tone: ileriAktif ? Palette.accent : Palette.inkFaint) {
                        if ileriAktif { ileri() }
                    }
                    .disabled(!ileriAktif)
                    .padding(Metrics.pad)
                }
                .background(Palette.card)
            }
        }
        .background(Palette.bg)
    }

    private var ust: some View {
        VStack(spacing: 10) {
            HStack {
                if let geri {
                    Button {
                        geri()
                    } label: {
                        Label("Geri", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
                }
                Spacer()
                if let adim, let toplam {
                    Text("\(adim) / \(toplam)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
                if let vazgec {
                    Button("Vazgeç") { vazgec() }
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.leading, 10)
                }
            }
            if let adim, let toplam, toplam > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.inset)
                        Capsule().fill(Palette.accent)
                            .frame(width: geo.size.width * CGFloat(adim) / CGFloat(toplam))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Palette.card)
    }
}

/// Büyük, dokunması kolay seçenek satırı.
struct SecenekButonu: View {
    var baslik: String
    var aciklama: String?
    var ikon: String?
    var renk: Color = Palette.accent
    var secili: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let ikon {
                    Image(systemName: ikon)
                        .font(.headline)
                        .foregroundStyle(renk)
                        .frame(width: 38, height: 38)
                        .background(renk.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(baslik)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    if let aciklama {
                        Text(aciklama)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSoft)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: secili ? "checkmark.circle.fill" : "chevron.right")
                    .font(secili ? .title3 : .caption.weight(.bold))
                    .foregroundStyle(secili ? renk : Palette.inkFaint)
            }
            .padding(Metrics.pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .stroke(secili ? renk : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// İki büyük cevap butonu.
struct EvetHayirSorusu: View {
    var evet: String = "Evet"
    var hayir: String = "Hayır"
    var evetAciklama: String?
    var hayirAciklama: String?
    var secim: Bool?
    var onSecim: (Bool) -> Void

    var body: some View {
        VStack(spacing: Metrics.gap) {
            SecenekButonu(baslik: evet, aciklama: evetAciklama,
                          secili: secim == true) { onSecim(true) }
            SecenekButonu(baslik: hayir, aciklama: hayirAciklama,
                          renk: Palette.gider, secili: secim == false) { onSecim(false) }
        }
    }
}

/// Tek satırlık büyük sayı girişi.
struct BuyukSayiAlani: View {
    var baslik: String?
    var birim: String?
    var placeholder: String = "0"
    @Binding var deger: Double
    @State private var metin = ""
    var para = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                if let baslik {
                    Text(baslik).font(.caption).foregroundStyle(Palette.inkFaint)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(placeholder, text: $metin)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .numericKeyboard()
                    if let birim {
                        Text(birim)
                            .font(.title3)
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
            }
        }
        .onAppear { if metin.isEmpty, deger != 0 { metin = NumberInput.display(deger) } }
        .onChange(of: metin) { _, yeni in deger = NumberInput.parse(yeni) ?? 0 }
    }
}

struct BuyukParaAlani: View {
    var baslik: String?
    @Binding var deger: Kurus
    @State private var metin = ""

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                if let baslik {
                    Text(baslik).font(.caption).foregroundStyle(Palette.inkFaint)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0", text: $metin)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .numericKeyboard()
                    Text("TL").font(.title3).foregroundStyle(Palette.inkFaint)
                }
            }
        }
        .onAppear { if metin.isEmpty, deger != 0 { metin = NumberInput.display(deger) } }
        .onChange(of: metin) { _, yeni in deger = NumberInput.kurus(yeni) ?? 0 }
    }
}

/// "Bu işlem sonucunda" özeti — kayıt bundan sonra yapılır.
struct OzetAdimi: View {
    var ozet: SaveSummary
    var sorunlar: [ValidationIssue]
    var kaydetBaslik: String = "Kaydet"
    var geri: (() -> Void)?
    var vazgec: (() -> Void)?
    var kaydet: () -> Void

    private var engeller: [ValidationIssue] { sorunlar.hardBlocking }
    private var onaylanacak: [ValidationIssue] {
        sorunlar.overridable + sorunlar.warnings
    }

    var body: some View {
        SoruAdimi(
            soru: "Bu işlem sonucunda",
            aciklama: engeller.isEmpty ? nil : "Önce aşağıdaki sorunu düzeltmelisin.",
            ileriBaslik: onaylanacak.isEmpty ? kaydetBaslik : "Yine de kaydet",
            ileriAktif: engeller.isEmpty,
            geri: geri,
            vazgec: vazgec,
            ileri: kaydet
        ) {
            if !ozet.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ozet.lines, id: \.self) { satir in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.caption)
                                    .foregroundStyle(Palette.accent)
                                Text(satir)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let not = ozet.note {
                            Divider().overlay(Palette.separator)
                            Text(not)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(engeller + onaylanacak) { sorun in
                Card(background: sorun.severity == .engel ? Palette.zararYumusak : Palette.uyariYumusak) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(sorun.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(sorun.severity == .engel ? Palette.zarar : Palette.uyari)
                        Text(sorun.detail)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Küçük artı/eksi sayacı — "bir pakette kaç adet" gibi sorular için.
struct SayiSayaci: View {
    @Binding var deger: Double
    var adim: Double = 1
    var enAz: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            buton("minus", aktif: deger > enAz) {
                deger = max(enAz, deger - adim)
            }
            Text(Units.formatNumber(deger))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(deger > 0 ? Palette.ink : Palette.inkFaint)
                .frame(minWidth: 44)
                .contentTransition(.numericText())
            buton("plus", aktif: true) { deger += adim }
        }
    }

    private func buton(_ icon: String, aktif: Bool,
                       _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(aktif ? Palette.accent : Palette.inkFaint)
                .frame(width: 36, height: 36)
                .background(Palette.inset)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!aktif)
        .accessibilityLabel(icon == "plus" ? "Artır" : "Azalt")
    }
}

/// "Kaldığın yerden devam etmek ister misin?" — yarım kalmış bir akış
/// yeniden açıldığında çıkar.
struct DevamSorusu: View {
    var baslik: String
    var ilerleme: String
    var devam: () -> Void
    var bastan: () -> Void
    var vazgec: (() -> Void)?

    var body: some View {
        SoruAdimi(
            soru: "Kaldığın yerden devam etmek ister misin?",
            aciklama: "\(baslik) · \(ilerleme)",
            vazgec: vazgec
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Evet, devam et",
                              aciklama: "Verdiğin cevaplar duruyor",
                              ikon: "arrow.forward.circle", action: devam)
                SecenekButonu(baslik: "Hayır, baştan başla",
                              aciklama: "Önceki cevaplar silinir",
                              ikon: "arrow.counterclockwise",
                              renk: Palette.gider, action: bastan)
            }
        }
    }
}

/// Akışların taslak kaydını tek yerden yönetir.
/// Her akış kendi durumunu `Codable` bir yapıda verir; burada diske yazılır.
@MainActor
struct TaslakKaydi {
    var kind: WizardKind
    var subjectId: Id?
    var baslik: String
    var toplamAdim: Int

    func kaydet<S: Encodable>(_ store: AppStore, adim: Int, durum: S) {
        guard adim > 0 else { return }
        guard let d = WizardDraft.make(kind: kind, subjectId: subjectId, title: baslik,
                                       step: adim, totalSteps: toplamAdim, state: durum)
        else { return }
        store.saveDraft(d)
    }

    func oku<S: Decodable>(_ store: AppStore, _ type: S.Type) -> S? {
        store.draft(kind, subjectId: subjectId)?.decode(type)
    }

    func mevcut(_ store: AppStore) -> WizardDraft? {
        store.draft(kind, subjectId: subjectId)
    }

    func sil(_ store: AppStore) {
        store.clearDraft(kind, subjectId: subjectId)
    }
}

// MARK: - Ad girişi

/// Ad soran adım. Metin alanı kendi durumunu tutar: her harfte üst ekran
/// yeniden kurulmaz, klavye kapanmaz, yazılan kaybolmaz.
/// Geri dönülüp gelindiğinde yazılan metin korunur.
struct AdSorusu: View {
    var soru: String
    var aciklama: String?
    var placeholder: String = "Adı yaz"
    /// Daha önce yazılmışsa alan bununla açılır
    var baslangic: String = ""
    var adim: Int?
    var toplam: Int?
    var ileriBaslik: String = "Devam"
    /// Zaten kayıtlı adlar — aynısı yazılırsa uyarılır
    var mevcutAdlar: [String] = []
    var geri: (() -> Void)?
    var vazgec: (() -> Void)?
    /// "Bu ürünü eklemeyeceğim" gibi ikincil seçenek
    var ekSecenek: (baslik: String, ikon: String, aksiyon: () -> Void)?
    var onDevam: (String) -> Void

    @State private var metin = ""
    @State private var yuklendi = false
    @FocusState private var odakta: Bool

    private var temiz: String { metin.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var bos: Bool { NameCheck.isBlank(metin) }
    private var mukerrer: Bool { NameCheck.isDuplicate(metin, among: mevcutAdlar) }

    var body: some View {
        SoruAdimi(
            soru: soru,
            aciklama: aciklama,
            adim: adim, toplam: toplam,
            ileriBaslik: ileriBaslik,
            ileriAktif: !bos && !mukerrer,
            geri: geri,
            vazgec: vazgec,
            ileri: { if !bos && !mukerrer { onDevam(temiz) } }
        ) {
            Card {
                TextField(placeholder, text: $metin)
                    .font(.title3)
                    .foregroundStyle(Palette.ink)
                    .focused($odakta)
                    .adKlavyesi()
                    .onSubmit { if !bos && !mukerrer { onDevam(temiz) } }
                    .accessibilityLabel(soru)
            }
            if mukerrer {
                Card(background: Palette.zararYumusak) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.zarar)
                        Text("Bu kayıt zaten var.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.zarar)
                        Spacer(minLength: 0)
                    }
                }
            }
            if let ek = ekSecenek {
                SecenekButonu(baslik: ek.baslik, ikon: ek.ikon,
                              renk: Palette.inkSoft, action: ek.aksiyon)
            }
        }
        .onAppear {
            guard !yuklendi else { return }
            yuklendi = true
            metin = baslangic
            // Klavye kendiliğinden açılsın; kullanıcı ikinci kez dokunmasın
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { odakta = true }
        }
    }
}

// MARK: - KDV soruları

/// "Yazdığın tutar KDV dahil mi?" — tek soru, iki büyük seçenek.
struct KdvDahilSorusu: View {
    var tutar: Kurus
    var oran: VatRate
    var secim: Bool?
    var adim: Int?
    var toplam: Int?
    var geri: (() -> Void)?
    var vazgec: (() -> Void)?
    var onSecim: (Bool) -> Void

    var body: some View {
        SoruAdimi(
            soru: "Yazdığın tutar KDV dahil mi?",
            aciklama: "\(Money.format(tutar)) yazdın. Faturada KDV ayrı gösteriliyorsa "
                + "\"hariç\", toplam tutar buysa \"dahil\" de.",
            adim: adim, toplam: toplam,
            geri: geri, vazgec: vazgec
        ) {
            EvetHayirSorusu(
                evet: "Evet, KDV dahil",
                hayir: "Hayır, KDV hariç",
                evetAciklama: oran == .yok ? nil
                    : "\(Money.format(tutar)) içinde KDV var",
                hayirAciklama: oran == .yok ? nil
                    : "KDV ayrıca eklenecek",
                secim: secim,
                onSecim: onSecim
            )
        }
    }
}

/// "KDV oranı nedir?" — varsayılan gösterilir ama kullanıcı onaylamadan geçilmez.
struct KdvOraniSorusu: View {
    var tutar: Kurus
    var dahil: Bool
    var secim: VatRate?
    var varsayilan: VatRate = .yirmi
    var adim: Int?
    var toplam: Int?
    var geri: (() -> Void)?
    var vazgec: (() -> Void)?
    var onSecim: (VatRate) -> Void

    var body: some View {
        SoruAdimi(
            soru: "KDV oranı nedir?",
            aciklama: "Emin değilsen faturaya bak. Çoğu üründe %20.",
            adim: adim, toplam: toplam,
            geri: geri, vazgec: vazgec
        ) {
            VStack(spacing: Metrics.gap) {
                // En yaygın oran en üstte
                ForEach(VatRate.allCases.reversed()) { r in
                    SecenekButonu(
                        baslik: r == .yok ? "KDV yok" : r.displayName,
                        aciklama: r == .yok ? nil : netAciklama(r),
                        secili: secim == r
                    ) { onSecim(r) }
                }
            }
        }
    }

    private func netAciklama(_ r: VatRate) -> String? {
        guard tutar > 0 else { return nil }
        let b = Vat.split(tutar, rate: r, included: dahil)
        return "Net \(Money.format(b.net)) + KDV \(Money.format(b.vat))"
    }
}

/// "120 TL KDV dahil → 100 TL net + 20 TL KDV" önizlemesi
struct KdvOnizlemeKarti: View {
    var baslik: String = "NET MALİYET"
    var tutar: Kurus
    var oran: VatRate
    var dahil: Bool

    var body: some View {
        let b = Vat.split(tutar, rate: oran, included: dahil)
        Card(background: Palette.inset) {
            VStack(spacing: 9) {
                LabeledRow(baslik, Money.format(b.net), tone: Palette.accent, strong: true)
                if oran != .yok {
                    LabeledRow("KDV (\(oran.displayName))", Money.format(b.vat))
                }
            }
        }
    }
}
