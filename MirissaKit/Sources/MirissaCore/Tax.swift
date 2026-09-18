import Foundation

/// Vergi karşılığı: "Gerçek kâr" vergi öncesidir; harcanabilir sanılmasın diye
/// kenara ayrılması gereken yaklaşık tutar. Oranı kullanıcı (muhasebecisine sorarak)
/// girer; oran girilmemişse hiçbir tahmin yapılmaz.
public struct VergiKarsiligi: Hashable, Sendable {
    public var yil: Int
    public var oranPct: Double
    /// Yılbaşından seçili aya kadar vergi öncesi kâr
    public var yilBasindanKar: Kurus
    /// Yılbaşından bu yana hesaplanan vergi (stopaj düşülmeden)
    public var yilBasindanVergi: Kurus
    /// Yılbaşından bu yana pazaryerlerinin kestiği stopaj — vergiden düşülür
    public var yilBasindanStopaj: Kurus
    /// Yılbaşından bu yana ayrılması gereken toplam (vergi − stopaj, eksiye düşmez)
    public var yilBasindanKarsilik: Kurus
    /// Seçili ayın payı (ay kârı zararsa 0; yıl toplamı eksiye düşmez)
    public var ayinPayi: Kurus
    /// İçinde bulunulan çeyreğin geçici vergi tahmini (önceki çeyrekler düşülmüş)
    public var ceyrek: Int
    public var ceyrekGeciciVergi: Kurus
    /// Geçici verginin son ödeme ayı ve günü (çeyreği izleyen 2. ayın 17'si)
    public var ceyrekSonOdeme: DateKey
}

public extension Engine {

    func vergiKarsiligi(month: MonthKey, today: DateKey = Dates.today()) -> VergiKarsiligi? {
        guard let oran = state.settings.ek.vergiOrani, oran > 0 else { return nil }
        let yil = Dates.year(of: month)
        let buAy = min(month, Dates.month(of: today))
        func ytd(_ son: MonthKey) -> Kurus {
            let bas = Dates.monthKey(yil, 1)
            guard son >= bas else { return 0 }
            return companyTotals(from: bas, to: son).gercekKar
        }
        func karsilik(_ k: Kurus) -> Kurus { Money.roundHalfAwayFromZero(Double(max(k, 0)) * oran / 100) }
        func stopajYtd(_ son: MonthKey) -> Kurus {
            let bas = Dates.monthKey(yil, 1)
            guard son >= bas else { return 0 }
            return companyTotals(from: bas, to: son).stopaj
        }
        // Stopaj peşin ödenmiş vergidir: ayrılacak tutardan düşülür
        func kalan(_ son: MonthKey) -> Kurus { max(karsilik(ytd(son)) - stopajYtd(son), 0) }
        let simdi = ytd(buAy)
        let ayNo = Dates.monthNumber(of: buAy)
        let ceyrek = (ayNo - 1) / 3 + 1
        let ceyrekSonu = Dates.monthKey(yil, ceyrek * 3)
        let oncekiCeyrekSonu = Dates.monthKey(yil, max((ceyrek - 1) * 3, 1))
        let ceyrekKalan = kalan(min(ceyrekSonu, Dates.month(of: today)))
        let oncekiKarsilik = ceyrek == 1 ? 0 : kalan(oncekiCeyrekSonu)
        let odemeAyi = Dates.addMonths(ceyrekSonu, 2)
        // 4. çeyrek için geçici vergi yoktur: yıllık beyanda ödenir
        let geciciVarMi = ceyrek < 4
        return VergiKarsiligi(
            yil: yil, oranPct: oran,
            yilBasindanKar: simdi,
            yilBasindanVergi: karsilik(simdi),
            yilBasindanStopaj: stopajYtd(buAy),
            yilBasindanKarsilik: kalan(buAy),
            ayinPayi: max(kalan(buAy) - kalan(Dates.addMonths(buAy, -1)), 0),
            ceyrek: ceyrek,
            ceyrekGeciciVergi: geciciVarMi ? max(ceyrekKalan - oncekiKarsilik, 0) : 0,
            ceyrekSonOdeme: geciciVarMi ? "\(odemeAyi)-17" : "\(yil + 1)-03-31"
        )
    }
}
