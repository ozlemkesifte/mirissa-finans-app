import SwiftUI
import MirissaCore

/// Tedarikçi borçları: vadeli alımların ödenmemiş taksitleri
struct TedarikciBorclariKarti: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let borclar = store.engine.acikBorclar()
        if !borclar.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Tedarikçi borçları", systemImage: "calendar.badge.clock")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(store.engine.acikBorcToplami.tl).font(.headline).foregroundStyle(Palette.ink)
                    }
                    ForEach(borclar) { b in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.kalem + (b.tedarikci.map { " · \($0)" } ?? ""))
                                    .font(.footnote).foregroundStyle(Palette.ink)
                                Text((b.gecikti ? "Vadesi geçti: " : "Vade: ") + Dates.displayDateShort(b.taksit.vade))
                                    .font(.caption2)
                                    .foregroundStyle(b.gecikti ? Palette.zarar : Palette.inkFaint)
                            }
                            Spacer()
                            Text(b.taksit.tutar.tl).font(.footnote.weight(.semibold))
                            Button("Ödendi") {
                                store.taksitOdendi(purchaseId: b.purchaseId, taksitId: b.taksit.id,
                                                   tarih: Dates.today())
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                        }
                    }
                    Text("Maliyet ve KDV alım günü yazıldı; buradaki tutarlar yalnızca kasadan çıkacak para. "
                         + "\"Ödendi\" deyince bugün kasadan çıkmış sayılır.")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
