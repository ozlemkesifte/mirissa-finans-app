import SwiftUI
import MirissaCore

/// Ana sayfa: geçen ayın ay sonu işleri bitmediyse ayın ilk yarısında görünür
struct AySonuKarti: View {
    @Environment(AppStore.self) private var store
    @Binding var sheet: AppSheet?

    private var gecenAy: MonthKey { Dates.addMonths(Dates.currentMonth(), -1) }

    var body: some View {
        let liste = store.engine.aySonuListesi(month: gecenAy)
        let tamam = liste.filter(\.tamam).count
        if Dates.day(of: Dates.today()) <= 15, tamam < liste.count, veriVar {
            Button { sheet = .aySonu(gecenAy) } label: {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "checklist").foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Dates.displayMonth(gecenAy)) ay sonu").font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Text("\(tamam)/\(liste.count) tamam · \(liste.first { !$0.tamam }?.baslik ?? "")")
                                .font(.caption).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.inkFaint)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var veriVar: Bool { !store.state.sales.isEmpty || !store.state.expenses.isEmpty }
}

/// Ay sonu kontrol listesi
struct AySonuEkrani: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var month: MonthKey
    @State private var sheet: AppSheet?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.engine.aySonuListesi(month: month)) { m in satir(m) }
                } footer: {
                    Text("Çoğu madde girdiğin kayıtlardan kendiliğinden işaretlenir. Hepsi tamamsa bu ayın rakamları "
                         + "gerçeğe en yakın halindedir.")
                }
                if store.state.settings.vatEnabled, !store.state.settings.ek.kilitli.contains(month) {
                    Section { AyKilidiSatiri(month: month) }
                }
            }
            .navigationTitle("\(Dates.displayMonth(month)) ay sonu")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .appSheets($sheet)
        }
    }

    private func satir(_ m: AySonuMaddesi) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: m.tamam ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(m.tamam ? Palette.kar : Palette.inkFaint)
                .font(.title3)
                .onTapGesture {
                    if m.elle || m.eylem == .sayim { store.aySonuIsaretle(month, m.eylem.rawValue, !m.tamam) }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(m.baslik).font(.subheadline.weight(.semibold))
                Text(m.aciklama).font(.caption).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if !m.tamam, let eylem = eylemBasligi(m) {
                    Button(eylem) { calistir(m) }.font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func eylemBasligi(_ m: AySonuMaddesi) -> String? {
        switch m.eylem {
        case .satis: return "Satış gir"
        case .siparis, .hakedis: return m.kanalId.map { _ in "Ay sonu kesintilerini aç" }
        case .sayim: return "Sayım yap"
        case .gider: return "Kontrol ettim"
        case .kilit: return nil
        case .yedek: return nil
        }
    }

    private func calistir(_ m: AySonuMaddesi) {
        switch m.eylem {
        case .satis: sheet = .saleFlow
        case .siparis, .hakedis: if let k = m.kanalId { sheet = .channelMonth(k, month) }
        case .sayim: sheet = .countFlow
        case .gider: store.aySonuIsaretle(month, "gider", true)
        case .kilit, .yedek: break
        }
    }
}
