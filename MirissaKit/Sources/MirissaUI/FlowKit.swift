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
