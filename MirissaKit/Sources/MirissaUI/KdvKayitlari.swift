import SwiftUI
import MirissaCore

/// KDV'nin hangi kayıtlardan geldiği; indirilen ve indirilemeyen ayrı
struct KdvKayitlariKarti: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey

    var body: some View {
        let kayitlar = store.engine.kdvKayitlari(month)
        if !kayitlar.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("KDV KAYITLARI")
                        .font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Palette.inkFaint)
                    grup("Hesaplanan KDV", kayitlar.filter { $0.tur == .hesaplanan })
                    grup("İndirilen KDV", kayitlar.filter { $0.tur == .indirilecek })
                    grup("İndirilmeyen KDV (gidere eklendi)", kayitlar.filter { $0.tur == .indirilemeyen })
                    Text("Devreden KDV nakit alacak değildir: yalnızca sonraki ayların hesaplanan KDV'sinden düşülür.")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func grup(_ baslik: String, _ liste: [KdvKaydi]) -> some View {
        if !liste.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Divider().overlay(Palette.separator)
                LabeledRow(baslik, liste.reduce(0) { $0 + $1.tutar }.tl, strong: true)
                ForEach(liste) { k in
                    VStack(alignment: .leading, spacing: 1) {
                        LabeledRow(k.tarih.map { "\(k.ad) · \(Dates.displayDateShort($0))" } ?? k.ad, k.tutar.tl,
                                   tone: Palette.inkSoft)
                        Text(k.neden).font(.caption2).foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
