import Foundation

/// Kurulacak bir hatırlatma (bildirim). Saat her zaman sabah 10:00.
public struct PlanliHatirlatma: Identifiable, Hashable, Sendable {
    public var id: String
    public var gun: DateKey
    public var baslik: String
    public var metin: String
}

public extension Engine {
    /// Önümüzdeki `gunSayisi` gün için hatırlatmalar (en fazla `enFazla` tane, en yakını önce).
    /// iPhone aynı anda en fazla 64 bekleyen bildirim tutar.
    func hatirlatmalar(bugun: DateKey = Dates.today(), gunSayisi: Int = 60, enFazla: Int = 60) -> [PlanliHatirlatma] {
        let son = Dates.addDays(bugun, gunSayisi)
        var out: [PlanliHatirlatma] = []
        func ekle(_ id: String, _ gun: DateKey, _ baslik: String, _ metin: String) {
            if gun > bugun && gun <= son { out.append(PlanliHatirlatma(id: id, gun: gun, baslik: baslik, metin: metin)) }
        }
        var ay = Dates.month(of: bugun)
        while ay <= Dates.month(of: son) {
            let gecen = Dates.addMonths(ay, -1)
            ekle("satis-\(ay)", "\(ay)-02", "Satışları gir",
                 "\(Dates.displayMonth(gecen)) satışlarını, sipariş sayılarını ve hakedişi girme zamanı.")
            if state.settings.vatEnabled {
                ekle("kdv-\(ay)", "\(ay)-24", "KDV beyanı yaklaşıyor",
                     "\(Dates.displayMonth(gecen)) KDV'si 28'inde ödenir. Ay sonu listesini bitir, beyandan sonra ayı kilitle.")
            }
            if [1, 4, 7, 10].contains(Dates.monthNumber(of: ay)) {
                ekle("maliyet-\(ay)", "\(ay)-05", "Maliyetleri gözden geçir",
                     "Fason, ambalaj ve sabit giderlerin güncel mi? Eski rakamlar başa baş ve reklam hedefini düşük gösterir.")
            }
            ay = Dates.addMonths(ay, 1)
        }
        // Haftalık yedek: her pazar
        var g = Dates.addDays(bugun, 1)
        while g <= son {
            if Dates.weekday(of: g) == 1 {
                ekle("yedek-\(g)", g, "Haftalık yedek", "Verilerini telefon dışına kaydet (Ayarlar → Yedekleme).")
            }
            g = Dates.addDays(g, 1)
        }
        for b in acikBorclar(today: bugun) {
            ekle("taksit-\(b.id)", Dates.addDays(b.taksit.vade, -2), "Ödeme yaklaşıyor",
                 "\(b.kalem) taksiti \(Money.format(b.taksit.tutar)), vade \(Dates.displayDateShort(b.taksit.vade)).")
        }
        for b in state.balances where !b.settled {
            guard let v = b.dueDate else { continue }
            ekle("bakiye-\(b.id)", Dates.addDays(v, -1), b.kind == .alacak ? "Tahsilat günü" : "Ödeme günü",
                 "\(b.name): \(Money.format(b.amount)), \(Dates.displayDateShort(v)).")
        }
        for o in siparisOnerileri(bugun: bugun) where !o.acil {
            ekle("siparis-\(o.id)", o.sonSiparisGunu, "Sipariş zamanı",
                 "\(o.ad) için en geç bugün sipariş ver (önerilen \(Units.formatQty(o.sonGundeMiktar, baseUnit: o.birim))).")
        }
        let buYil = Dates.year(of: Dates.month(of: bugun))
        // 4. çeyrek geçici vergisi izleyen yılın Şubat'ında ödenir: geçen yılın 4. çeyreği de bakılır
        for (yil, c) in [(buYil - 1, 12), (buYil, 3), (buYil, 6), (buYil, 9), (buYil, 12)] {
            // Henüz gelmemiş çeyrek bugünün çeyreğine düşer; aynı hatırlatma tekrar etmesin
            if let v = vergiKarsiligi(month: Dates.monthKey(yil, c), today: bugun), v.ceyrek == c / 3,
               v.ceyrekGeciciVergi > 0 {
                ekle("vergi-\(yil)-\(c)", Dates.addDays(v.ceyrekSonOdeme, -3), "Geçici vergi",
                     "\(v.ceyrek). çeyrek geçici vergi yaklaşık \(Money.format(v.ceyrekGeciciVergi)), son gün \(Dates.displayDateShort(v.ceyrekSonOdeme)).")
            }
        }
        // Geçen yılın yıllık gelir/kurumlar vergisi (geçici vergiler ödenmiş varsayılır)
        if let v = vergiKarsiligi(month: Dates.monthKey(buYil - 1, 12), today: bugun), v.yillikBeyandaOdenecek > 0 {
            let gunler = v.sirket ? ["\(buYil)-04-30"] : ["\(buYil)-03-31", "\(buYil)-07-31"]
            for (i, g) in gunler.enumerated() {
                ekle("yillikvergi-\(buYil - 1)-\(i)", Dates.addDays(g, -5), "Yıllık vergi",
                     "\(buYil - 1) yıllık \(v.sirket ? "kurumlar" : "gelir") vergisi \(v.sirket ? "" : "\(i + 1). taksiti ")"
                     + "yaklaşık \(Money.format(v.sirket ? v.yillikBeyandaOdenecek : (i == 0 ? v.yillikBeyandaOdenecek - v.yillikBeyandaOdenecek / 2 : v.yillikBeyandaOdenecek / 2))), son gün \(Dates.displayDateShort(g)).")
            }
        }
        return Array(out.sorted { ($0.gun, $0.id) < ($1.gun, $1.id) }.prefix(enFazla))
    }
}
