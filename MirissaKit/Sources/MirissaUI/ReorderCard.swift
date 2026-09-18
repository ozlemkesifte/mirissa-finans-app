import SwiftUI
import MirissaCore

/// Ana sayfa: sipariş zamanı gelen kalemler
struct SiparisZamaniKarti: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let oneriler = store.engine.siparisOnerileri()
        if !oneriler.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Sipariş zamanı", systemImage: "cart.badge.plus")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    ForEach(oneriler) { o in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(o.ad).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(Units.formatQty(o.miktar, baseUnit: o.birim))
                                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
                            }
                            Text(o.acil
                                 ? "Bugün sipariş ver: elde \(o.kalanGun) günlük var, gelmesi \(o.tedarikSuresiGun) gün sürüyor."
                                 : "En geç \(Dates.displayDateShort(o.sonSiparisGunu)) sipariş ver · elde \(o.kalanGun) günlük var.")
                                .font(.caption)
                                .foregroundStyle(o.acil ? Palette.zarar : Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Son ayların tüketim hızına göre; tedarik süresi + 7 gün pay. Önerilen miktar, geldikten sonra "
                         + "30 gün yetecek kadar (en az sipariş miktarından az değil).")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
