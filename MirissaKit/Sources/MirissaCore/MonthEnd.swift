import Foundation

/// Ay sonu kontrol listesi. Maddelerin çoğu girilen verilerden kendiliğinden
/// işaretlenir; yalnızca uygulamanın bilemeyeceği olanlar elle işaretlenir.
public struct AySonuMaddesi: Identifiable, Hashable, Sendable {
    public enum Eylem: String, Hashable, Sendable {
        case satis, siparis, hakedis, sayim, gider, kilit, yedek
    }
    public var id: Eylem { eylem }
    public var eylem: Eylem
    public var baslik: String
    public var aciklama: String
    public var tamam: Bool
    /// İlgili kanal (sipariş ve hakediş maddeleri için)
    public var kanalId: Id?
    /// Elle işaretlenen madde mi
    public var elle: Bool = false
}

/// Bir ayın satış verisi durumu. "0 satış" ile "henüz girilmedi" ayrı tutulur: satışsız ay
/// kullanıcı ay sonu listesinde "bu ay satış olmadı" diye işaretlemedikçe girilmemiş sayılır.
public enum SatisDurumu: Sendable, Hashable {
    case girildi
    /// Satış girilmedi ama ay "0 satış" olarak işaretlendi: gerçek sıfır
    case sifirSatis
    case girilmedi
}

public extension Engine {

    func satisDurumu(_ month: MonthKey) -> SatisDurumu {
        if satisliAylar.contains(month) { return .girildi }
        return (state.settings.ek.aySonuIsaretleri?[month] ?? []).contains(AySonuMaddesi.Eylem.satis.rawValue)
            ? .sifirSatis : .girilmedi
    }

    /// Geçmiş (ya da içinde bulunulan) bir ayda gider var ama satış verisi girilmemiş
    /// ("0 satış" olarak işaretlenen ay girilmiş sayılır)
    func satisGirilmedi(month: MonthKey, today: DateKey = Dates.today()) -> Bool {
        guard month <= Dates.month(of: today) else { return false }
        return satisDurumu(month) == .girilmedi && companyMonth(month).toplamGider != 0
    }

    func aySonuListesi(month: MonthKey, today: DateKey = Dates.today()) -> [AySonuMaddesi] {
        var out: [AySonuMaddesi] = []
        let isaretler = Set(state.settings.ek.aySonuIsaretleri?[month] ?? [])
        let satislar = state.sales.filter { $0.month == month }
        // Son 3 ayda satışı olan her kanaldan bu ay da satış beklenir
        let oncekiAylar = (1...3).map { Dates.addMonths(month, -$0) }
        let beklenen = Set(state.sales.filter { oncekiAylar.contains($0.month) }.map(\.channelId))
            .filter { id in state.channel(id).map { !$0.archived } ?? false }
        let girilen = Set(satislar.map(\.channelId))
        let eksikKanallar = beklenen.subtracting(girilen).compactMap { state.channel($0)?.name }.sorted()
        // Satış yoksa "bu ay satış olmadı" elle işaretlenir: işaretlenmeyen ay "girilmedi" sayılır
        // (tahminlerde atlanır), işaretlenen ay gerçek sıfırdır
        let sifirIsaretli = isaretler.contains(AySonuMaddesi.Eylem.satis.rawValue)
        out.append(AySonuMaddesi(
            eylem: .satis, baslik: satislar.isEmpty ? "Satışlar girildi (ya da bu ay satış olmadı)" : "Satışlar girildi",
            aciklama: satislar.isEmpty
                ? (sifirIsaretli ? "Bu ay satış olmadı olarak işaretlendi (0 satış)."
                   : "Bu ay hiç satış girilmedi. Gerçekten satış olmadıysa işaretle; yoksa tahminler bu ayı atlar.")
                : (eksikKanallar.isEmpty ? "\(girilen.count) kanalın satışı girildi."
                   : "Satışı eksik görünen kanal: \(eksikKanallar.joined(separator: ", "))."),
            tamam: satislar.isEmpty ? sifirIsaretli : eksikKanallar.isEmpty,
            elle: satislar.isEmpty))

        let siparissiz = girilen.filter { (state.channelMonth(month: month, channelId: $0)?.orderCount ?? 0) == 0 }
        out.append(AySonuMaddesi(
            eylem: .siparis, baslik: "Sipariş sayıları girildi",
            aciklama: siparissiz.isEmpty ? "Kargo ve koli gerçek sipariş sayısıyla hesaplanıyor."
                : "Girilmeyen: \(siparissiz.compactMap { state.channel($0)?.name }.sorted().joined(separator: ", ")). Kargo ve koli tahmini.",
            tamam: !girilen.isEmpty && siparissiz.isEmpty,
            kanalId: siparissiz.sorted().first))

        let pazaryerleri = girilen.filter { state.channel($0)?.kind == .marketplace }
        if !pazaryerleri.isEmpty {
            let hakedissiz = pazaryerleri.filter { state.channelMonth(month: month, channelId: $0)?.payoutActual == nil }
            out.append(AySonuMaddesi(
                eylem: .hakedis, baslik: "Hakediş kontrol edildi",
                aciklama: hakedissiz.isEmpty ? "Yatan tutar beklenenle karşılaştırıldı."
                    : "Pazaryerinin yatırdığı tutarı gir; kesinti farkı varsa görünür.",
                tamam: hakedissiz.isEmpty, kanalId: hakedissiz.sorted().first))
        }

        let sayimVar = state.counts.contains { Dates.month(of: $0.date) == month }
        out.append(AySonuMaddesi(
            eylem: .sayim, baslik: "Stok sayımı yapıldı",
            aciklama: sayimVar ? "Bu ay sayım girildi." : "Ayda bir koli, kutu ve ürünleri saymak fire ve kaybı ortaya çıkarır.",
            tamam: sayimVar || isaretler.contains("sayim")))

        out.append(AySonuMaddesi(
            eylem: .gider, baslik: "Giderler ve faturalar kontrol edildi",
            aciklama: "Reklam, kargo faturası, fason ödemesi gibi tek seferlik giderlerin hepsi girildi mi?",
            tamam: isaretler.contains("gider"), elle: true))

        if state.settings.vatEnabled {
            let kilitli = state.settings.ek.kilitli.contains(month)
            out.append(AySonuMaddesi(
                eylem: .kilit, baslik: "KDV beyanı verildi, ay kilitlendi",
                aciklama: kilitli ? "Bu ayın kayıtları artık değiştirilemez." : "Beyannameyi verince ayı kilitle; rakamlar sonradan bozulmaz.",
                tamam: kilitli))
        }

        let yedek = state.settings.ek.sonYedekPaylasim.map { $0 >= Dates.monthEnd(month) } ?? false
        out.append(AySonuMaddesi(
            eylem: .yedek, baslik: "Yedek alındı",
            aciklama: yedek ? "Ay kapandıktan sonra yedek alındı." : "Ayın kayıtları bitince yedeği telefon dışına kaydet.",
            tamam: yedek))
        return out
    }
}
