import SwiftUI
import MirissaCore

/// Satıştan kaldırılan ürünler, kapatılan kanallar ve kullanılmayan malzemeler.
/// Hiçbiri silinmez; tek dokunuşla geri alınır.
struct ArsivBolumu: View {
    @Environment(AppStore.self) private var store
    @State private var acik = false

    private var urunler: [Product] { store.state.products.filter(\.archived) }
    private var kanallar: [Channel] { store.state.channels.filter(\.archived) }
    private var malzemeler: [StockMaterial] { store.state.materials.filter(\.archived) }
    private var toplam: Int { urunler.count + kanallar.count + malzemeler.count }

    var body: some View {
        if toplam > 0 {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { acik.toggle() }
                    } label: {
                        HStack {
                            Label("Arşiv (\(toplam))", systemImage: "archivebox")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: acik ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if acik {
                        Text("Geçmiş kayıtları ve raporları duruyor. Geri alınca yeniden listelerde görünür.")
                            .font(.caption)
                            .foregroundStyle(Palette.inkFaint)
                        ForEach(urunler) { p in satir(p.name, "Ürün") { store.setProductArchived(p.id, false) } }
                        ForEach(kanallar) { c in satir(c.name, "Kanal") { store.setChannelArchived(c.id, false) } }
                        ForEach(malzemeler) { m in satir(m.name, "Malzeme") { store.setMaterialArchived(m.id, false) } }
                    }
                }
            }
        }
    }

    private func satir(_ ad: String, _ tur: String, _ geriAl: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ad).font(.subheadline).foregroundStyle(Palette.ink)
                Text(tur).font(.caption2).foregroundStyle(Palette.inkFaint)
            }
            Spacer()
            Button("Geri al", action: geriAl)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.accent)
        }
    }
}
