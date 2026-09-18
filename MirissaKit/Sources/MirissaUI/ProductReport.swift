import SwiftUI
import MirissaCore

/// Hangi ürün hangi kanalda para kazandırıyor, hangisi kaybettiriyor
struct UrunRaporu: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @State private var acik: Set<Id> = []

    private var sonuclar: [UrunKanalSonuc] {
        store.engine.urunKanalKarliligi(from: period.from, to: min(period.to, Dates.currentMonth()))
    }

    /// Ürün bazında toplam (kanallar birleşik)
    private var urunler: [(id: Id, ad: String, toplam: UrunKanalSonuc, kanallar: [UrunKanalSonuc])] {
        var sira: [Id] = []
        var grup: [Id: [UrunKanalSonuc]] = [:]
        for s in sonuclar {
            if grup[s.productId] == nil { sira.append(s.productId) }
            grup[s.productId, default: []].append(s)
        }
        return sira.compactMap { id in
            guard let l = grup[id], let ilk = l.first else { return nil }
            let t = l.dropFirst().reduce(ilk) { UrunKanalSonucToplam.topla($0, $1) }
            return (id, ilk.productName, t, l.sorted { $0.kalan > $1.kalan })
        }
        .sorted { $0.toplam.kalan > $1.toplam.kalan }
    }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            PeriodPicker(period: period)
            if sonuclar.isEmpty {
                Card {
                    EmptyHint(icon: "chart.bar.xaxis", title: "Bu dönemde satış yok",
                              message: "Satış girince her ürünün her kanalda ne bıraktığı burada görünür.")
                }
            } else {
                Text("Kanalın kesintileri ürünlere dağıtıldı: komisyon ciroya, kargo ve koli adede, "
                     + "reklam ve kanal giderleri ciroya göre. Ürünlerin toplamı kanal raporundaki "
                     + "\"kanalda kalan\" ile aynıdır. Ortak giderler (kira, maaş) dağıtılmadı.")
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(urunler, id: \.id) { u in urunKarti(u) }
                IadeAnalizi(sonuclar: sonuclar)
                KampanyaHesabi()
            }
        }
    }

    private func urunKarti(_ u: (id: Id, ad: String, toplam: UrunKanalSonuc, kanallar: [UrunKanalSonuc])) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if acik.contains(u.id) { acik.remove(u.id) } else { acik.insert(u.id) }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.ad).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                            Text("\(Int(u.toplam.adet - u.toplam.iadeAdet)) adet · marj \(Money.formatPercent(u.toplam.marjPct))")
                                .font(.caption).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(u.toplam.kalan.tl)
                                .font(.headline)
                                .foregroundStyle(u.toplam.kalan < 0 ? Palette.zarar : Palette.kar)
                            if let a = u.toplam.adetBasiKalan {
                                Text("adet başı \(Money.roundHalfAwayFromZero(a).tl)")
                                    .font(.caption2).foregroundStyle(Palette.inkFaint)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if u.toplam.kalan < 0 {
                    Text("Bu ürün bu dönemde para kaybettirdi.")
                        .font(.caption.weight(.medium)).foregroundStyle(Palette.zarar)
                }
                if acik.contains(u.id) {
                    ForEach(u.kanallar) { k in kanalDokumu(k) }
                }
            }
        }
    }

    private func kanalDokumu(_ k: UrunKanalSonuc) -> some View {
        VStack(spacing: 6) {
            Divider().overlay(Palette.separator)
            HStack {
                Text(k.channelName).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text(k.kalan.tl).font(.footnote.weight(.semibold))
                    .foregroundStyle(k.kalan < 0 ? Palette.zarar : Palette.ink)
            }
            LabeledRow("Net satış (KDV hariç)", k.netSatis.tl)
            LabeledRow("Komisyon ve kesinti", "-" + k.kesinti.tl, tone: Palette.inkSoft)
            LabeledRow("Kargo ve hizmet", "-" + k.kargo.tl, tone: Palette.inkSoft)
            LabeledRow("Ürün maliyeti", "-" + k.urunMaliyeti.tl, tone: Palette.inkSoft)
            LabeledRow("Ambalaj ve koli", "-" + k.ambalaj.tl, tone: Palette.inkSoft)
            LabeledRow("Reklamdan önce kalan", k.reklamOncesiKalan.tl)
            if k.reklam != 0 { LabeledRow("Reklam payı", "-" + k.reklam.tl, tone: Palette.inkSoft) }
            if k.digerGider != 0 { LabeledRow("Kanal giderleri payı", "-" + k.digerGider.tl, tone: Palette.inkSoft) }
        }
    }
}

enum UrunKanalSonucToplam {
    static func topla(_ a: UrunKanalSonuc, _ b: UrunKanalSonuc) -> UrunKanalSonuc {
        var r = a
        r.adet += b.adet; r.iadeAdet += b.iadeAdet; r.netSatis += b.netSatis
        r.kesinti += b.kesinti; r.kargo += b.kargo; r.urunMaliyeti += b.urunMaliyeti
        r.ambalaj += b.ambalaj; r.reklam += b.reklam; r.digerGider += b.digerGider
        r.sabitKesinti += b.sabitKesinti
        return r
    }
}
