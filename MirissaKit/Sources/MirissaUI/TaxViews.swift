import SwiftUI
import MirissaCore

/// Vergi karşılığı kartı: kârın ne kadarını kenara ayırmalı
struct VergiKarti: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey

    var body: some View {
        if let v = store.engine.vergiKarsiligi(month: month) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Vergi karşılığı (tahmini)", systemImage: "building.columns")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    LabeledRow("\(v.yil) başından bu yana vergi öncesi kâr", v.yilBasindanKar.tl)
                    LabeledRow("Kenara ayırman gereken (%\(Money.formatPercent(v.oranPct).dropFirst()))",
                               v.yilBasindanKarsilik.tl, tone: Palette.uyari, strong: true)
                    if v.ayinPayi > 0 {
                        LabeledRow("Bu ayın payı", v.ayinPayi.tl, tone: Palette.inkSoft)
                    }
                    if v.ceyrekGeciciVergi > 0 {
                        LabeledRow("\(v.ceyrek). çeyrek geçici vergi (son gün \(Dates.displayDateShort(v.ceyrekSonOdeme)))",
                                   v.ceyrekGeciciVergi.tl, tone: Palette.inkSoft)
                    } else if v.ceyrek == 4 {
                        Text("4. çeyrek için geçici vergi yok; yıllık beyanda ödenir.")
                            .font(.caption).foregroundStyle(Palette.inkFaint)
                    }
                    Text("Gerçek kâr vergi öncesidir. Oran senin girdiğin orandır; kesin tutarı muhasebecin hesaplar "
                         + "(şahıs şirketinde dilimli gelir vergisi, indirimler ve istisnalar değiştirir).")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Ayarlar → Vergi
struct VergiAyari: View {
    @Environment(AppStore.self) private var store
    @State private var oran: Double?
    @State private var yuklendi = false

    var body: some View {
        Section {
            Picker("Şirket türü", selection: Binding(
                get: { store.state.settings.ek.vergiTuru ?? "" },
                set: { yeni in store.ekAyarla { $0.vergiTuru = yeni.isEmpty ? nil : yeni } })) {
                Text("Seçilmedi").tag("")
                Text("Şahıs şirketi").tag("sahis")
                Text("Limited / anonim").tag("sirket")
            }
            OptionalQtyField("Yaklaşık vergi oranı", suffix: "%", value: $oran)
                .onChange(of: oran) { _, yeni in
                    store.ekAyarla { $0.vergiOrani = yeni.flatMap { $0 > 0 ? min($0, 60) : nil } }
                }
            if store.state.settings.ek.vergiTuru == "sirket", store.state.settings.ek.vergiOrani == nil {
                Button("Kurumlar vergisi %25 kullan") { oran = 25 }
            }
        } header: {
            Text("Vergi karşılığı")
        } footer: {
            Text("Gerçek kâr vergi öncesidir. Oranı girersen, kârın ne kadarını kenara ayırman gerektiğini ve "
                 + "geçici vergi tahminini gösteririm. Şahıs şirketinde oranı muhasebecine sor. Boş bırakırsan tahmin yapılmaz.")
        }
        .onAppear {
            guard !yuklendi else { return }
            yuklendi = true
            oran = store.state.settings.ek.vergiOrani
        }
    }
}
