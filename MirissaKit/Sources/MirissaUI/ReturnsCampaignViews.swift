import SwiftUI
import MirissaCore

/// Raporlar → Ürünler: iade analizi
struct IadeAnalizi: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    var sonuclar: [UrunKanalSonuc]

    var body: some View {
        let l = store.engine.iadeAnalizi(from: period.from, to: min(period.to, Dates.currentMonth()))
        if !l.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("İadeler", systemImage: "arrow.uturn.left")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    ForEach(l) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("\(r.productName) · \(r.channelName)").font(.footnote.weight(.semibold))
                                Spacer()
                                Text(Money.formatPercent(r.oranPct))
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(r.oranPct >= 10 ? Palette.zarar : Palette.ink)
                            }
                            Text("\(Int(r.iade)) / \(Int(r.satilan)) adet iade · iade tutarı \(r.iadeTutari.tl)"
                                 + (r.hasarli > 0 ? " · \(Int(r.hasarli)) hasarlı" : ""))
                                .font(.caption).foregroundStyle(Palette.inkSoft)
                            if r.toplamKayip > 0 {
                                Text("İade yüzünden kayıp: \(r.toplamKayip.tl) (boşa giden ambalaj \(r.bosaGidenAmbalaj.tl)"
                                     + (r.hasarliMaliyet > 0 ? ", hasarlı mal \(r.hasarliMaliyet.tl)" : "") + ")")
                                    .font(.caption2).foregroundStyle(Palette.inkFaint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text("İade kargosunu pazaryeri kestiyse ay sonu \"diğer kesinti\"ye ya da hakediş farkına yansır.")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Raporlar → Ürünler: "şu indirimi yaparsam ne olur?"
struct KampanyaHesabi: View {
    @Environment(AppStore.self) private var store
    @State private var urun: Id = ""
    @State private var kanal: Id = ""
    @State private var indirim: Double = 20

    private var urunler: [Product] { store.state.activeProducts }
    private var kanallar: [Channel] { store.state.activeChannels }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Kampanya hesabı", systemImage: "percent")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Picker("Ürün", selection: $urun) {
                    ForEach(urunler) { Text($0.name).tag($0.id) }
                }
                Picker("Kanal", selection: $kanal) {
                    ForEach(kanallar) { Text($0.name).tag($0.id) }
                }
                HStack(spacing: 8) {
                    ForEach([10.0, 15, 20, 30], id: \.self) { d in
                        Button("%\(Int(d))") { indirim = d }
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(indirim == d ? Palette.accent : Palette.inset, in: Capsule())
                            .foregroundStyle(indirim == d ? Palette.onFilled : Palette.ink)
                            .buttonStyle(.plain)
                    }
                }
                sonuc
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if urun.isEmpty { urun = urunler.first?.id ?? "" }
            if kanal.isEmpty { kanal = kanallar.first?.id ?? "" }
        }
    }

    @ViewBuilder
    private var sonuc: some View {
        if let k = store.engine.kampanyaHesabi(productId: urun, channelId: kanal, indirimPct: indirim) {
            LabeledRow("Fiyat", "\(k.eskiFiyat.tl) → \(k.yeniFiyat.tl)")
            LabeledRow("Siparişte kalan (reklamdan önce)", "\(k.eskiKatki.tl) → \(k.yeniKatki.tl)",
                       tone: k.yeniKatki < 0 ? Palette.zarar : Palette.ink, strong: true)
            if let c = k.gerekenSiparisCarpani {
                Text("Aynı kârı tutturmak için siparişlerin %\(Int(((c - 1) * 100).rounded())) artması gerekir"
                     + (k.basaBasOnce.flatMap { o in k.basaBasSonra.map { " (başa baş: ayda \(o) → \($0) sipariş)" } } ?? "")
                     + ".")
                    .font(.footnote).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Bu indirimle her satış zarar ettirir. Pazaryeri kampanya katkısı vermiyorsa bu indirimi yapma.")
                    .font(.footnote.weight(.medium)).foregroundStyle(Palette.zarar)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Bu ürünün bu kanaldaki fiyatı girilmemiş.").font(.footnote).foregroundStyle(Palette.inkFaint)
        }
    }
}
