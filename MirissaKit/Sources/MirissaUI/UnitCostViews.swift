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

/// Bir satıştan hesabına ne yatar, KDV'den sonra ne kalır, sana net ne kalır — kalem kalem
struct SatisHakedisListesi: View {
    var d: SatisHakedisDokumu

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledRow("Müşterinin ödediği (KDV dahil)", d.fiyat.tl, strong: true)
            if d.satisKdv != 0 {
                LabeledRow("İçindeki KDV (\(d.satisKdvOrani.displayName))", (-d.satisKdv).tl, tone: Palette.inkSoft)
                LabeledRow("KDV hariç satış", d.kdvHaricSatis.tl)
            }
            Divider().overlay(Palette.separator)
            Text("\(d.kanalAdi) kesintileri (faturadaki tutar)")
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.inkSoft)
            if d.kesintiler.isEmpty {
                Text("Bu kanal için kesinti oranı girilmemiş.")
                    .font(.caption2).foregroundStyle(Palette.inkFaint)
            }
            ForEach(d.kesintiler) { k in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(k.ad).font(.footnote).foregroundStyle(Palette.ink)
                        Text(k.detay + (k.kdv != 0 ? " · KDV'si \(k.kdv.tl)" : ""))
                            .font(.caption2).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer(minLength: 8)
                    Text((-k.brut).tl).font(.footnote.weight(.medium)).foregroundStyle(Palette.ink)
                }
            }
            if d.stopaj != 0 {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("E-ticaret stopajı").font(.footnote).foregroundStyle(Palette.ink)
                        Text("\(Money.formatPercentKisa(d.stopajOrani ?? 0)) × KDV hariç satış · gider değil, vergiden düşülür")
                            .font(.caption2).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer(minLength: 8)
                    Text((-d.stopaj).tl).font(.footnote.weight(.medium)).foregroundStyle(Palette.ink)
                }
            }
            Divider().overlay(Palette.separator)
            LabeledRow("Hesabına yatan", d.hesabinaYatan.tl, strong: true)
            if d.satisKdv != 0 {
                LabeledRow("Bu satıştan ödenecek KDV", (-d.odenecekKdv).tl, tone: Palette.inkSoft)
                Text("Satışın KDV'si \(d.satisKdv.tl) − kesinti faturalarındaki KDV \(d.kesintiKdv.tl). "
                     + "Ürün ve ambalaj alımlarındaki KDV bunu ayrıca azaltır (aylık KDV raporunda).")
                    .font(.caption2).foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if d.stopaj != 0 {
                LabeledRow("Stopaj geri (vergiden düşülür)", d.stopaj.tl, tone: Palette.inkSoft)
            }
            LabeledRow("Ürün maliyeti", (-d.urunMaliyeti).tl, tone: Palette.inkSoft)
            LabeledRow("Ambalaj", (-d.ambalajMaliyeti).tl, tone: Palette.inkSoft)
            if d.koliMaliyeti != 0 {
                LabeledRow("Koli (siparişte 1)", (-d.koliMaliyeti).tl, tone: Palette.inkSoft)
            }
            Divider().overlay(Palette.separator)
            LabeledRow("Sana kalan (vergi öncesi)", d.netKalan.tl,
                       tone: d.netKalan < 0 ? Palette.zarar : Palette.kar, strong: true)
            if !d.aylikSabitler.isEmpty {
                Text("Siparişe bölünmeyen aylık ücretler (aylık hesaba girer): "
                     + d.aylikSabitler.map { "\($0.ad) \($0.tutar.tl)" }.joined(separator: ", "))
                    .font(.caption2).foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !d.eksikler.isEmpty {
                Text("Eksik bilgi: " + d.eksikler.joined(separator: ", ") + ". Girilince sonuç tamamlanır.")
                    .font(.caption2).foregroundStyle(Palette.uyari)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Tek ürünlük bir sipariş için; reklam ve genel giderler hariç.")
                .font(.caption2).foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ürün detayında: kanal seçip satıştan kalanı gör
struct SatisHakedisKarti: View {
    @Environment(AppStore.self) private var store
    var productId: Id
    @State private var kanal: Id?

    var body: some View {
        let p = store.state.product(productId)
        let kanallar = store.state.activeChannels.filter { p?.price(for: $0.id, on: Dates.today()) != nil }
        let secili = kanal ?? kanallar.first?.id
        VStack(spacing: Metrics.gap) {
            SectionTitle("Bir satıştan sana kalan")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    if kanallar.count > 1 {
                        Picker("Kanal", selection: Binding(get: { secili ?? "" }, set: { kanal = $0 })) {
                            ForEach(kanallar) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if let s = secili, let d = store.engine.satisHakedisDokumu(productId: productId, channelId: s) {
                        SatisHakedisListesi(d: d)
                    } else {
                        Text("Satış fiyatı girilince komisyon, kargo, KDV ve stopaj kalem kalem burada hesaplanır.")
                            .font(.caption).foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
