import SwiftUI
import MirissaCore

/// KDV kartında: beyanname verilen ayı kilitle / kilidi aç
struct AyKilidiSatiri: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    @State private var sor = false

    private var kilitli: Bool { store.state.settings.ek.kilitli.contains(month) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if kilitli {
                Label("Bu ay kilitli: kayıtları değiştirilemez", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                Button("Kilidi aç") { sor = true }
                    .font(.caption.weight(.semibold))
            } else if month < Dates.currentMonth() {
                Button {
                    sor = true
                } label: {
                    Label("Beyannameyi verdim, ayı kilitle", systemImage: "lock")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(kilitli
                            ? "Kilidi açarsan bu ayın kayıtları yeniden değiştirilebilir; beyan ettiğin rakamlar değişebilir."
                            : "Bu ayın satış, gider, alım ve stok kayıtları kilitlenir. Yanlışlıkla yapılan bir değişiklik beyan ettiğin rakamları bozamaz.",
                            isPresented: $sor, titleVisibility: .visible) {
            Button(kilitli ? "Kilidi aç" : "Kilitle") { store.ayKilidi(month, kilitli: !kilitli) }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}

/// Ayarlar → Değişiklik geçmişi
struct DegisiklikGecmisi: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            if store.state.changeLog.isEmpty {
                Text("Henüz kayıtlı değişiklik yok.").foregroundStyle(Palette.inkFaint)
            }
            ForEach(store.state.changeLog.reversed()) { k in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(k.alan).font(.subheadline.weight(.semibold))
                        Text(etiket(k.tur)).font(.caption).foregroundStyle(renk(k.tur))
                        Spacer()
                        Text(zaman(k.zaman)).font(.caption2).foregroundStyle(Palette.inkFaint)
                    }
                    Text(k.aciklama).font(.footnote).foregroundStyle(Palette.inkSoft)
                }
            }
        }
        .navigationTitle("Değişiklik geçmişi")
        .inlineTitle()
    }

    private func etiket(_ t: ChangeLogEntry.Tur) -> String {
        switch t {
        case .eklendi: return "eklendi"
        case .degisti: return "değişti"
        case .silindi: return "silindi"
        case .geriYuklendi: return "geri yüklendi"
        }
    }

    private func renk(_ t: ChangeLogEntry.Tur) -> Color {
        switch t {
        case .eklendi: return Palette.kar
        case .degisti: return Palette.uyari
        case .silindi: return Palette.zarar
        case .geriYuklendi: return Palette.accent
        }
    }

    private func zaman(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: d)
    }
}
