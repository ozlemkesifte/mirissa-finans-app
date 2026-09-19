import SwiftUI
import MirissaCore

/// Giderler: her satışta ürün başına giden ile satış olmasa da ödenen genel giderler ayrı
struct GiderAyrimiKarti: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @State private var urunlerAcik = false

    private var donem: String { period.scope == .month ? Dates.displayMonth(period.month) : "\(period.year)" }

    var body: some View {
        let g = store.engine.giderAyrimi(from: period.from, to: min(period.to, Dates.currentMonth()))
        if g.urunBasinaToplam != 0 || g.genelToplam != 0 {
            VStack(spacing: Metrics.gap) {
                if g.tutarsizlik != 0 { TutarsizlikUyarisi(tutar: g.tutarsizlik) }
                grup("Satışa bağlı giderler — \(donem) toplamı",
                     "Satış adedi arttıkça artan giderler. Bu, \(donem) içindeki bütün satışların toplamıdır; "
                        + "tek bir satışın maliyeti değildir (onu yukarıda ürün ürün görebilirsin).",
                     g.urunBasina, g.urunBasinaToplam, ikon: "cart") { EmptyView() }
                grup("Genel giderler — \(donem) toplamı",
                     "Satış olmasa da ödenir. Yılda bir ödenenler aylara bölünerek yazılır. Başa baş hedefi bunları karşılamak içindir.",
                     g.genel, g.genelToplam, ikon: "building.2") { EmptyView() }
            }
        }
    }

    private func grup<Ek: View>(_ baslik: String, _ aciklama: String, _ kalemler: [GiderKalemi],
                                _ toplam: Kurus, ikon: String, @ViewBuilder ek: () -> Ek) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(baslik, systemImage: ikon)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(toplam.tl).font(.headline).foregroundStyle(Palette.ink)
                }
                Text(aciklama).font(.caption).foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if !kalemler.isEmpty { Divider().overlay(Palette.separator) }
                ForEach(kalemler) { k in
                    VStack(alignment: .leading, spacing: 1) {
                        LabeledRow(k.ad, k.tutar.tl)
                        if let a = k.aciklama {
                            Text(a).font(.caption2).foregroundStyle(Palette.inkFaint)
                        }
                    }
                }
                ek()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func urunDokumu(_ urunler: [UrunGideri]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Palette.separator)
            Button {
                withAnimation(.snappy(duration: 0.2)) { urunlerAcik.toggle() }
            } label: {
                HStack {
                    Text("Ürün ürün (adet başı)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: urunlerAcik ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold)).foregroundStyle(Palette.inkFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if urunlerAcik {
                ForEach(urunler) { u in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(u.ad).font(.footnote.weight(.semibold))
                            Spacer()
                            Text(u.adetBasi.map { "adet başı \(Money.roundHalfAwayFromZero($0).tl)" } ?? u.toplam.tl)
                                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
                        }
                        Text("\(Int(u.adet)) adet · toplam \(u.toplam.tl)")
                            .font(.caption2).foregroundStyle(Palette.inkFaint)
                        satir("Ürün maliyeti", u.urunMaliyeti, u.adet)
                        satir("Ambalaj ve koli", u.ambalaj, u.adet)
                        satir("Komisyon ve kesintiler", u.kesinti, u.adet)
                        satir("Kargo ve hizmet", u.kargo, u.adet)
                    }
                    .padding(.vertical, 2)
                }
                Text("Reklam ve genel giderler ürünlere dağıtılmadı; ürün ürün kâr için Raporlar → Ürünler.")
                    .font(.caption2).foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func satir(_ ad: String, _ tutar: Kurus, _ adet: Double) -> some View {
        HStack {
            Text(ad).font(.caption).foregroundStyle(Palette.inkSoft)
            Spacer()
            Text(adet > 0 ? "\(Money.roundHalfAwayFromZero(Double(tutar) / adet).tl) / adet" : tutar.tl)
                .font(.caption).foregroundStyle(Palette.inkSoft)
        }
    }
}

/// Hesabın kendi içinde tutmadığı durum. Fark hiçbir kaleme yazılmaz; kullanıcı rakamlara
/// güvenmemesi gerektiğini açıkça görür.
struct TutarsizlikUyarisi: View {
    var tutar: Kurus

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(Palette.zarar)
            Text("Hesap tutarsızlığı: \(tutar.tl) kalemlerle açıklanamıyor. Bu rakamlara güvenme.")
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.zarar)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.zararYumusak, in: RoundedRectangle(cornerRadius: 10))
    }
}
