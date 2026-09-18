import SwiftUI
import MirissaCore

/// Tek satışın kalem kalem maliyeti (kutu, koli, poşet, patpat… ayrı ayrı)
struct BirimMaliyetListesi: View {
    var dokum: BirimMaliyetDokumu

    var body: some View {
        VStack(spacing: 6) {
            ForEach(dokum.kalemler) { k in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(k.ad).font(.footnote).foregroundStyle(Palette.ink)
                        Text(k.detay).font(.caption2)
                            .foregroundStyle(k.bilinmiyor ? Palette.uyari : Palette.inkFaint)
                    }
                    Spacer(minLength: 8)
                    Text(k.bilinmiyor ? "bilinmiyor" : k.tutar.tl)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(k.bilinmiyor ? Palette.uyari : Palette.ink)
                }
            }
            Divider().overlay(Palette.separator)
            LabeledRow("Bir satışın toplam maliyeti", dokum.toplam.tl, strong: true)
            if dokum.eksikVar {
                Text("Maliyeti bilinmeyen kalemler toplama girmedi; alımını ya da maliyetini girince tamamlanır.")
                    .font(.caption2).foregroundStyle(Palette.uyari)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Giderler: ürün ürün, bir satışta nelere para gidiyor
struct BirSatisinMaliyetiKarti: View {
    @Environment(AppStore.self) private var store
    @State private var acik: Id?
    @State private var kanal: [Id: Id] = [:]

    var body: some View {
        let urunler = store.state.activeProducts
        if !urunler.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Bir satışın maliyeti (ürün ürün)", systemImage: "shippingbox")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("Bir ürün satıldığında nelere ne kadar para gittiği. Rakamlar senin alımlarından, "
                         + "girdiğin maliyetlerden ve kanal ayarlarından gelir.")
                        .font(.caption).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(urunler) { p in urunSatiri(p) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func urunSatiri(_ p: Product) -> some View {
        let kanallar = store.state.activeChannels.filter { p.price(for: $0.id, on: Dates.today()) != nil }
        let secili = kanal[p.id] ?? kanallar.first?.id
        let dokum = store.engine.birimMaliyetDokumu(productId: p.id, channelId: secili)
        return VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Palette.separator)
            Button {
                withAnimation(.snappy(duration: 0.2)) { acik = acik == p.id ? nil : p.id }
            } label: {
                HStack {
                    Text(p.name).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    if let d = dokum {
                        Text(d.eksikVar ? "\(d.toplam.tl)+" : d.toplam.tl)
                            .font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                    }
                    Image(systemName: acik == p.id ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold)).foregroundStyle(Palette.inkFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if acik == p.id, let d = dokum {
                if kanallar.count > 1 {
                    Picker("Kanal", selection: Binding(get: { secili ?? "" }, set: { kanal[p.id] = $0 })) {
                        ForEach(kanallar) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                }
                BirimMaliyetListesi(dokum: d)
                if kanallar.isEmpty {
                    Text("Bu ürünün kanal fiyatı girilmediği için komisyon ve kargo eklenmedi.")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                }
            }
        }
    }
}
