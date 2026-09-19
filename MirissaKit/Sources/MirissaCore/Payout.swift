import Foundation

/// Hakediş eşleştirme: pazaryerinin yatırdığı para ile uygulamanın beklediği.
/// Fark varsa kesintiler tahminden farklıdır (kampanya katkısı, desi farkı,
/// iade kargosu, ceza…). Uygulamanın hesabı kendiliğinden değişmez.
public struct HakedisKarsilastirma: Hashable, Sendable {
    public var month: MonthKey
    public var channelId: Id
    /// Müşterinin ödediği (KDV dahil) − platformun kestiği (KDV dahil)
    public var beklenen: Kurus
    public var yatan: Kurus
    /// Beklenen − yatan: artı ise beklenenden az yattı
    public var fark: Kurus { beklenen - yatan }
    /// Farkın satışa oranı; küçük farklar yuvarlama sayılır
    public var onemli: Bool { abs(fark) > max(100 * 100, beklenen / 200) }   // 100 TL ya da %0,5
}

public extension Engine {
    /// Kanalın bir aydaki beklenen hakedişi (KDV dahil).
    /// Kendi sitede aylık sabit ücret (abonelik) ödemeden kesilmez, ayrıca faturalanır: beklenen
    /// hakedişten düşülmez. Pazaryerinde aylık ücret hakedişten kesilir.
    func beklenenHakedis(month: MonthKey, channelId: Id) -> Kurus {
        let r = channelResult(channelId: channelId, month: month)
        var kesinti = r.channelFees + r.feeVat
        if state.channel(channelId)?.kind == .ownStore {
            // Sabit ücretin faturadaki tutarı (net + KDV'si) birlikte çıkarılır
            kesinti -= r.sabitKesintiBrut
        }
        return r.netSalesIncVat - kesinti - r.stopaj
    }

    func hakedis(month: MonthKey, channelId: Id) -> HakedisKarsilastirma? {
        guard let yatan = state.channelMonth(month: month, channelId: channelId)?.payoutActual else { return nil }
        return HakedisKarsilastirma(month: month, channelId: channelId,
                                    beklenen: beklenenHakedis(month: month, channelId: channelId),
                                    yatan: yatan)
    }

    /// Hesaba yatan paradaki (KDV dahil) bir farkın, kesinti alanına yazılacak karşılığı.
    /// Kesintiler KDV hariç giriliyorsa fark KDV'den arındırılır; motor KDV'yi kendisi ekler.
    func kesintiGirisi(brutFark: Kurus, channelId: Id, month: MonthKey) -> Kurus {
        guard let ch = state.channel(channelId) else { return brutFark }
        let k = ch.kesintiKdv(on: Dates.monthEnd(month))
        return k.dahil ? brutFark : Vat.net(brutFark, rate: k.oran, included: true)
    }

    /// Net bir kesinti tutarının faturadaki (KDV dahil) karşılığı — kanal ayarına göre
    func kesintiBrut(_ net: Kurus, channelId: Id, month: MonthKey? = nil) -> Kurus {
        guard let ch = state.channel(channelId) else { return net }
        let k = ch.kesintiKdv(on: month.map(Dates.monthEnd) ?? Dates.today())
        guard k.dahil else { return net }
        let s = Vat.split(net, rate: k.oran, included: false)
        return s.net + s.vat
    }
}
