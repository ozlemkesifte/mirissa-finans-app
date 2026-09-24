import SwiftUI
import MirissaCore

/// Finans & Vergiler → Reklam: reklamın gerçekte ne getirdiği.
/// Bütün rakamlar girilen kayıtlardan gelir; panel verisi ya da tahmin kullanılmaz.
struct ReklamBolumu: View {
    @Environment(Period.self) private var period

    var body: some View {
        VStack(spacing: Metrics.gap) {
            MonthStepper(month: Bindable(period).month)
            ReklamRaporu(month: period.month)
        }
    }
}

/// Reklam kartlarının tamamı. Ana ekrandaki reklam satırı da bunu açar: kart listesi tek yerde durur.
struct ReklamRaporu: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey

    var body: some View {
        // Karne bir kez hesaplanır, kartlara verilir
        let a = store.engine.reklamAyi(month)
        VStack(spacing: Metrics.gap) {
            ReklamKarnesiKarti(a: a)
            ReklamTavaniKarti(a: a)
            HedefeKalanReklamKarti(a: a)
            ReklamAylarKarti(month: month)
            ReklamKanallariKarti(month: month)
            ReklamHedefiBolumu(month: month, acik: true)
                .padding(.horizontal, Metrics.pad)
                .padding(.vertical, 14)
                .background(Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }
}

/// Ayın reklam karnesi: harcama, ROAS (panel gibi ve gerçek), kâr bazlı ROAS, sipariş başı reklam
struct ReklamKarnesiKarti: View {
    var a: ReklamAyi

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                Text("REKLAM KARNESİ · \(Dates.displayMonth(a.month))")
                    .font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Palette.inkFaint)
                if a.harcama == 0 {
                    Text("Bu ay reklam gideri girilmedi.")
                        .font(.subheadline).foregroundStyle(Palette.inkSoft)
                } else {
                    LabeledRow("Reklam harcaması (KDV hariç)", a.harcama.tl, strong: true)
                    LabeledRow("Satış (iade ve indirim düşülmüş, KDV dahil)", a.ciro.tl)
                    if a.iadeIndirim != 0 {
                        LabeledRow("İade ve indirim", "-" + a.iadeIndirim.tl, tone: Palette.inkSoft)
                    }
                    Divider().overlay(Palette.separator)
                    satir("Panelde görünene yakın ROAS", a.brutRoas,
                          "iade ve indirim düşülmeden satış ÷ reklam")
                    satir("Gerçek ROAS", a.roas, "iade ve indirim düşülmüş satış ÷ reklam")
                    satir("Kâr bazlı ROAS", a.poas,
                          "1 TL reklama kalan katkı: komisyon, kargo, ürün ve ambalaj düşülmüş")
                    if let c = a.cpa {
                        LabeledRow("Sipariş başına reklam", c.tl,
                                   tone: Palette.inkSoft, badge: a.siparisTahmini ? "sipariş tahmini" : nil)
                    }
                    Divider().overlay(Palette.separator)
                    LabeledRow("Reklamdan önce katkı", a.katkiReklamsiz.tl, tone: Palette.inkSoft)
                    LabeledRow("Reklamdan sonra kalan", a.reklamSonrasiKatki.tl,
                               tone: a.reklamSonrasiKatki < 0 ? Palette.zarar : Palette.kar, strong: true)
                    if a.katkiyiYedi {
                        Label("Reklam bu ay katkının tamamını yedi: sabit giderlere hiçbir şey kalmadı.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Palette.zarar)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if a.poas != nil, let p = a.poas, p < 1 {
                        Text("Kâr bazlı ROAS 1'in altında: reklam, getirdiği katkıdan fazlasına mal oluyor.")
                            .font(.caption).foregroundStyle(Palette.uyari)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func satir(_ ad: String, _ deger: Double?, _ aciklama: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            LabeledRow(ad, deger.map { RoasFormat.format($0) } ?? "hesaplanamadı",
                       tone: deger == nil ? Palette.inkFaint : Palette.ink)
            Text(aciklama).font(.caption2).foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Hedef kâr için reklam en fazla ne olabilir
struct ReklamTavaniKarti: View {
    @Environment(AppStore.self) private var store
    var a: ReklamAyi

    var body: some View {
        if a.hasData {
            let e = store.engine
            let month = a.month
            let hedef = e.aylikHedefVergiOncesi(month: month)
            let tavan = a.tavan(hedefKar: hedef ?? 0)
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("REKLAM TAVANI").font(.caption.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(Palette.inkFaint)
                    LabeledRow("Başa baş için en fazla", a.tavan(hedefKar: 0).tl, strong: true)
                    if hedef != nil {
                        LabeledRow(e.karHedefiBasligi(month: month) ?? "Kâr hedefi için en fazla",
                                   tavan.tl, strong: true)
                    }
                    LabeledRow("Bu ay harcanan", a.harcama.tl,
                               tone: a.harcama > tavan ? Palette.zarar : Palette.inkSoft)
                    Text("Bu ayın girilen satışları, kesintileri ve sabit giderleriyle: reklam bu tutarı geçerse "
                         + "hedef tutmaz. Ay ilerledikçe satış girdikçe tavan da yükselir.")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Son 6 ay: harcama, sipariş, CPA, ROAS, kâr bazlı ROAS
struct ReklamAylarKarti: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey

    var body: some View {
        let aylar = store.engine.reklamTablosu(endingAt: month, months: 6).filter(\.hasData)
        if !aylar.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SON AYLAR").font(.caption.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(Palette.inkFaint)
                    ForEach(aylar) { a in
                        VStack(alignment: .leading, spacing: 1) {
                            Divider().overlay(Palette.separator)
                            LabeledRow(Dates.displayMonth(a.month), a.harcama.tl,
                                       tone: a.katkiyiYedi ? Palette.zarar : Palette.ink)
                            Text(ozet(a)).font(.caption2).foregroundStyle(Palette.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Reklam harcaması KDV hariç, satış KDV dahildir; ROAS iade ve indirim düşülmüş satışla, "
                         + "kâr bazlı ROAS katkıyla hesaplanır.")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func ozet(_ a: ReklamAyi) -> String {
        var p: [String] = []
        if a.siparis > 0 { p.append("\(a.siparis) sipariş") }
        if let c = a.cpa { p.append("sipariş başı \(Money.format(c))") }
        return (p + ReklamOzeti.parcalar(a)).joined(separator: " · ")
    }
}

/// Kanal kanal reklam verimi
struct ReklamKanallariKarti: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey

    var body: some View {
        let liste = store.engine.kanalReklamlari(month: month).filter { $0.harcama != 0 }
        if !liste.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("KANALLARA GÖRE").font(.caption.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(Palette.inkFaint)
                    ForEach(liste, id: \.kanal) { k in
                        VStack(alignment: .leading, spacing: 1) {
                            Divider().overlay(Palette.separator)
                            LabeledRow(k.kanal, k.harcama.tl)
                            Text(ozet(k)).font(.caption2).foregroundStyle(Palette.inkFaint)
                        }
                    }
                    Text("Yalnız o kanala işaretlenmiş reklam giderleri sayılır; kanalsız (ortak) reklam burada görünmez.")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func ozet(_ k: ReklamKanali) -> String { ReklamOzeti.parcalar(k).joined(separator: " · ") }
}

/// Hedefe kalan kargo ve bu ayki sipariş başı reklamla yaklaşık maliyeti; stok yetmiyorsa uyarı
struct HedefeKalanReklamKarti: View {
    @Environment(AppStore.self) private var store
    var a: ReklamAyi

    var body: some View {
        let e = store.engine
        let month = a.month
        let p = e.plan(month: month)
        let hedef = p.targets.first { !$0.isBreakeven } ?? p.targets.first
        if let hedef, month >= Dates.currentMonth() {
            let kalan = max(hedef.orders - a.siparis, 0)
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HEDEFE KALAN").font(.caption.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(Palette.inkFaint)
                    LabeledRow(hedef.isBreakeven ? "Başa baş için kalan kargo"
                                 : ((e.karHedefiBasligi(month: month) ?? "Kâr hedefi için") + " kalan kargo"),
                               "\(kalan)", strong: true)
                    if let cpa = a.cpa, kalan > 0 {
                        LabeledRow("Bu ayki sipariş başı reklamla", (cpa * kalan).tl, tone: Palette.uyari)
                        Text("Bu ay sipariş başına \(Money.format(cpa)) reklam harcandı; kalan \(kalan) kargo "
                             + "aynı maliyetle gelirse yaklaşık bu kadar reklam gerekir. Reklamsız gelen siparişler "
                             + "bu tutarı düşürür.")
                            .font(.caption2).foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if kalan > 0 {
                        Text("Bu ay henüz reklam harcaması ya da sipariş girilmedi; sipariş başı reklam hesaplanamıyor.")
                            .font(.caption2).foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if kalan > 0, let k = e.stokKapasitesi(), k.kargo < kalan {
                        Label("Stok yetersiz: mevcut stokla yaklaşık \(k.kargo) kargo hazırlanabilir (\(k.darbogaz)). "
                              + "Reklamı artırmadan önce stok gerekiyor.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Palette.zarar)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Ay ve kanal satırlarının ortak özeti: oranlar motordaki tek tanımdan gelir
enum ReklamOzeti {
    static func parcalar(_ o: ReklamOlcumu) -> [String] {
        var p: [String] = []
        if let r = o.roas { p.append("ROAS \(RoasFormat.format(r))") }
        if let k = o.poas { p.append("kâr bazlı \(RoasFormat.format(k))") }
        p.append("reklamdan sonra \(Money.format(o.reklamSonrasiKatki))")
        return p
    }
}
