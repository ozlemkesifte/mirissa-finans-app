import SwiftUI
import MirissaCore

/// Kasa + banka bakiyesini girme
struct KasaBakiyesiGirisi: View {
    @Environment(AppStore.self) private var store
    @State private var tutar: Kurus = 0

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bugün kasada ve bankada toplam ne kadar var?")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Text("Şirket hesaplarının toplamı. Paranın kaç hafta yeteceği buradan hesaplanır. "
                     + "Ayda bir güncellemen yeterli.")
                    .font(.caption).foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                BuyukParaAlani(baslik: "Kasa + banka", deger: $tutar)
                Button("Kaydet") {
                    store.ekAyarla { $0.kasaBakiye = tutar; $0.kasaTarih = Dates.today() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tutar == 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { tutar = store.state.settings.ek.kasaBakiye ?? 0 }
    }
}

/// Raporlar → Nakit
struct NakitRaporu: View {
    @Environment(AppStore.self) private var store
    @State private var guncelle = false

    var body: some View {
        VStack(spacing: Metrics.gap) {
            if let t = store.engine.nakitTahmini(), !guncelle {
                ozet(t)
                haftalar(t)
                bilinenler(t)
                varsayimlar(t)
                Button("Kasa bakiyesini güncelle") { guncelle = true }
                    .font(.footnote.weight(.semibold))
            } else {
                KasaBakiyesiGirisi()
                    .onChange(of: store.state.settings.ek.kasaTarih) { _, _ in guncelle = false }
            }
        }
    }

    private func ozet(_ t: NakitTahmini) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("PARAN NE KADAR YETER").font(.caption.weight(.semibold)).tracking(0.6)
                    .foregroundStyle(Palette.inkFaint)
                if let h = t.bittigiHafta {
                    Text("Yaklaşık \(h) hafta").font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(Palette.zarar)
                    Text("Bu gidişle \(Dates.displayDateShort(t.haftalar[h - 1].bitis)) haftasında kasa eksiye düşüyor.")
                        .font(.footnote).foregroundStyle(Palette.zarar)
                } else {
                    Text("\(t.haftalar.count) haftadan fazla")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(Palette.kar)
                    Text("Önümüzdeki \(t.haftalar.count) haftada kasa eksiye düşmüyor.")
                        .font(.footnote).foregroundStyle(Palette.inkSoft)
                }
                LabeledRow("\(Dates.displayDateShort(t.baslangicGunu)) bakiyesi", t.baslangicBakiye.tl)
                if let son = t.haftalar.last {
                    LabeledRow("\(Dates.displayDateShort(son.bitis)) tahmini bakiye", son.bakiye.tl,
                               tone: son.bakiye < 0 ? Palette.zarar : Palette.ink, strong: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func haftalar(_ t: NakitTahmini) -> some View {
        Card {
            VStack(spacing: 6) {
                HStack {
                    Text("Hafta").font(.caption2).foregroundStyle(Palette.inkFaint)
                    Spacer()
                    Text("Giriş / Çıkış").font(.caption2).foregroundStyle(Palette.inkFaint)
                    Text("Bakiye").font(.caption2).foregroundStyle(Palette.inkFaint).frame(width: 90, alignment: .trailing)
                }
                ForEach(t.haftalar) { h in
                    HStack {
                        Text(Dates.displayDateShort(h.baslangic)).font(.caption).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("+\(Money.formatCompact(h.giris)) / −\(Money.formatCompact(h.cikis))")
                            .font(.caption2).foregroundStyle(Palette.inkSoft)
                        Text(Money.formatCompact(h.bakiye)).font(.caption.weight(.semibold))
                            .foregroundStyle(h.bakiye < 0 ? Palette.zarar : Palette.ink)
                            .frame(width: 90, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bilinenler(_ t: NakitTahmini) -> some View {
        if !t.bilinenKalemler.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tarihi belli ödemeler ve tahsilatlar").font(.subheadline.weight(.semibold))
                    ForEach(t.bilinenKalemler.prefix(30)) { k in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(k.ad).font(.footnote).foregroundStyle(Palette.ink)
                                Text(Dates.displayDateShort(k.gun) + (k.tahmini ? " · tahmini" : ""))
                                    .font(.caption2).foregroundStyle(Palette.inkFaint)
                            }
                            Spacer()
                            Text((k.tutar > 0 ? "+" : "−") + abs(k.tutar).tl)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(k.tutar > 0 ? Palette.kar : Palette.ink)
                        }
                    }
                }
            }
        }
    }

    private func varsayimMetni(_ t: NakitTahmini) -> String {
        var m = "Nasıl hesaplandı: Tarihi belli olanlar (düzenli giderler, vadeli alım taksitleri, alacak ve borçlar, "
        m += "KDV ödemesi ayın 28'inde, geçici vergi) gününde yazıldı. Bilinmeyenler son 3 ayın ortalamasıyla "
        m += "eşit dağıtıldı (tahmini): satış tahsilatı ayda " + t.aylikTahsilat.tl
        m += " (platform kesintisi düşülmüş), düzensiz gider ayda " + t.aylikDuzensizGider.tl
        m += ", stok alımı ayda " + t.aylikStokAlimi.tl + "."
        if t.tahsilatBaslangici > t.baslangicGunu {
            m += " Girdiğin kanal alacakları olduğu için tahmini tahsilat "
            m += Dates.displayDateShort(t.tahsilatBaslangici) + " sonrası başlatıldı."
        }
        return m
    }

    private func varsayimlar(_ t: NakitTahmini) -> some View {
        Text(varsayimMetni(t))
            .font(.caption2).foregroundStyle(Palette.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ana sayfada tek satırlık nakit özeti
struct NakitOzetKarti: View {
    @Environment(AppStore.self) private var store
    var onTap: () -> Void

    var body: some View {
        if let t = store.engine.nakitTahmini() {
            Button(action: onTap) {
                Card {
                    HStack {
                        Image(systemName: "banknote").foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nakit").font(.caption.weight(.semibold)).foregroundStyle(Palette.inkFaint)
                            Text(t.bittigiHafta.map { "Yaklaşık \($0) hafta yeter" }
                                 ?? "\(t.haftalar.count) haftadan fazla yeter")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(t.bittigiHafta == nil ? Palette.ink : Palette.zarar)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
