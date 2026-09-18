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
    /// Kanalın bir aydaki beklenen hakedişi (KDV dahil)
    func beklenenHakedis(month: MonthKey, channelId: Id) -> Kurus {
        let r = channelResult(channelId: channelId, month: month)
        return r.netSalesIncVat - r.channelFees - r.feeVat - r.stopaj
    }

    func hakedis(month: MonthKey, channelId: Id) -> HakedisKarsilastirma? {
        guard let yatan = state.channelMonth(month: month, channelId: channelId)?.payoutActual else { return nil }
        return HakedisKarsilastirma(month: month, channelId: channelId,
                                    beklenen: beklenenHakedis(month: month, channelId: channelId),
                                    yatan: yatan)
    }

    /// Net bir kesinti tutarının faturadaki (KDV dahil) karşılığı — kanal ayarına göre
    func kesintiBrut(_ net: Kurus, channelId: Id) -> Kurus {
        guard let ch = state.channel(channelId), ch.resolvedFeesIncludeVat,
              ch.resolvedFeeVatRate != .yok else { return net }
        return net + Money.roundHalfAwayFromZero(Double(net) * Double(ch.resolvedFeeVatRate.rawValue) / 100)
    }
}
