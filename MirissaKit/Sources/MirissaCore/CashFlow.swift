import Foundation

/// Nakit akışı ve "param kaç hafta yeter".
///
/// Kâr, bankadaki para değildir: pazaryeri hakedişi sonra öder, stok alımı parayı
/// bugün çeker, KDV ayın 28'inde ödenir. Bu hesap girilen kasa bakiyesinden başlar;
/// bilinen kalemleri tarihiyle, bilinmeyenleri son 3 ayın ortalamasıyla (tahmini) koyar.
public struct NakitKalemi: Identifiable, Hashable, Sendable {
    public var id: String
    public var gun: DateKey
    public var ad: String
    /// Giriş artı, çıkış eksi
    public var tutar: Kurus
    public var tahmini: Bool
}

public struct NakitHafta: Identifiable, Hashable, Sendable {
    public var baslangic: DateKey
    public var bitis: DateKey
    public var giris: Kurus
    public var cikis: Kurus
    /// Hafta sonundaki bakiye
    public var bakiye: Kurus
    public var id: DateKey { baslangic }
}

public struct NakitTahmini: Hashable, Sendable {
    public var baslangicBakiye: Kurus
    public var baslangicGunu: DateKey
    public var haftalar: [NakitHafta]
    /// Bilinen tarihli kalemler (gün sırasıyla)
    public var bilinenKalemler: [NakitKalemi]
    /// Bakiyenin ilk eksiye düştüğü hafta (1'den başlar). nil = süre boyunca yetiyor
    public var bittigiHafta: Int?
    /// Tahminde kullanılan aylık ortalamalar
    public var aylikTahsilat: Kurus
    public var aylikDuzensizGider: Kurus
    public var aylikStokAlimi: Kurus
    /// Tahmini tahsilatın başladığı gün (girilmiş kanal alacaklarından sonra)
    public var tahsilatBaslangici: DateKey
}

public extension Engine {

    /// Son 3 tamamlanmış ayın aylık ortalamaları
    private func nakitOrtalamalari(bugun: DateKey)
    -> (tahsilat: Kurus, duzensiz: Kurus, stok: Kurus, hesaplanan: Kurus, indirilecek: Kurus) {
        let buAy = Dates.month(of: bugun)
        let aylar = (1...3).map { Dates.addMonths(buAy, -$0) }
        var tahsilat = 0, duzensiz = 0, stok = 0, hesaplanan = 0, indirilecek = 0
        for m in aylar {
            let r = companyMonth(m)
            // Henüz girilmemiş ayların KDV tahmini için hesaplanan ve indirilecek KDV ortalaması
            let v = vatStatus(m)
            hesaplanan += v.hesaplanan
            indirilecek += v.indirilecek
            // Kanalların yatırdığı: müşterinin ödediği − platformun kestiği (KDV dahil)
            // Stopaj da pazaryerince kesilir: hesaba yatmaz
            tahsilat += r.channels.reduce(0) { $0 + $1.netSalesIncVat - $1.channelFees - $1.feeVat - $1.stopaj }
            for i in expenseInstances(month: m) {
                switch i.sourceKind {
                case .tekSeferlik: duzensiz += i.cashAmount
                case .stokAlimi: stok += i.cashAmount
                case .duzenli, .taksit: break   // tarihleriyle ayrıca konuyor
                }
            }
        }
        return (tahsilat / 3, duzensiz / 3, stok / 3, hesaplanan / 3, indirilecek / 3)
    }

    func nakitTahmini(bugun: DateKey = Dates.today(), hafta: Int = 12) -> NakitTahmini? {
        guard let bakiye = state.settings.ek.kasaBakiye else { return nil }
        let bas = state.settings.ek.kasaTarih ?? bugun
        let son = Dates.addDays(bas, hafta * 7)
        var kalemler: [NakitKalemi] = []
        func pencerede(_ g: DateKey) -> Bool { g > bas && g <= son }

        // 1) Giderler, alım peşinatları ve taksitler (tarihli, bilinen)
        for i in Expenses.instances(state, from: Dates.month(of: bas), to: Dates.month(of: son))
        where pencerede(i.date) && i.cashAmount != 0 {
            kalemler.append(NakitKalemi(id: "g:\(i.id)", gun: i.date, ad: i.name,
                                        tutar: -i.cashAmount, tahmini: false))
        }
        // 2) Alacak ve borçlar (vadesi olanlar). Vadesi geçmiş ama kapanmamış olan ilk güne yazılır.
        let ilkGun = Dates.addDays(bas, 1)
        for b in state.balances where !b.settled {
            guard let v = b.dueDate, v <= son else { continue }
            let gecikmis = v <= bas
            kalemler.append(NakitKalemi(id: "b:\(b.id)", gun: gecikmis ? ilkGun : v,
                                        ad: gecikmis ? "\(b.name) (vadesi geçti)" : b.name,
                                        tutar: b.kind == .alacak ? b.amount : -b.amount, tahmini: false))
        }
        // 1b) Vadesi geçmiş ama ödenmemiş taksitler: ilk gün, "gecikmiş" diye (vadesi pencerede
        // olanlar zaten 1. adımdaki gider satırlarında)
        for p in state.purchases where !p.excludeFromExpenses {
            for t in p.odeme?.taksitler ?? [] where !t.odendi && t.vade <= bas && t.tutar != 0 {
                kalemler.append(NakitKalemi(id: "gecikmis:\(p.id):\(t.id)", gun: ilkGun,
                                            ad: "\(state.itemName(p.item)) alımı taksiti (vadesi geçti)",
                                            tutar: -t.tutar, tahmini: false))
            }
        }
        let ort = nakitOrtalamalari(bugun: bugun)
        // 3) KDV: bir ayın KDV'si izleyen ayın 28'inde ödenir. Satışları henüz tam girilmemiş
        // (bu ve sonraki) aylar için son 3 ayın ortalaması kullanılır; yoksa tahmini tahsilatın KDV'si
        // hiç ödenmiyormuş gibi görünürdü.
        // Devreden KDV zincirlenir: önceki aydan kalan KDV alacağı tahmini ayların ödemesinden düşülür.
        var ay = Dates.addMonths(Dates.month(of: bas), -1)
        var tasinan: Kurus?
        while ay <= Dates.month(of: son) {
            let vade = "\(Dates.addMonths(ay, 1))-28"
            let v = vatStatus(ay)
            let tahmini = ay >= Dates.month(of: bugun)
            var tutar = v.odenecek
            if tahmini {
                let devreden = tasinan ?? v.oncekiDevreden
                let net = max(v.hesaplanan, ort.hesaplanan) - max(v.indirilecek, ort.indirilecek)
                tutar = max(net - devreden, 0)
                tasinan = max(devreden - net, 0)
            }
            if pencerede(vade), state.settings.vatEnabled {
                if tutar > 0 {
                    kalemler.append(NakitKalemi(id: "kdv:\(ay)", gun: vade,
                                                ad: "\(Dates.displayMonth(ay)) KDV ödemesi",
                                                tutar: -tutar, tahmini: tahmini))
                }
            }
            ay = Dates.addMonths(ay, 1)
        }
        // 4) Geçici vergi (oran girildiyse)
        for ceyrekSonu in [3, 6, 9].map({ Dates.monthKey(Dates.year(of: Dates.month(of: bas)), $0) }) {
            // Henüz gelmemiş çeyrek sonu bugünün çeyreğine düşer; aynı vergi iki kez yazılmasın
            if let v = vergiKarsiligi(month: ceyrekSonu, today: bugun),
               v.ceyrek == Dates.monthNumber(of: ceyrekSonu) / 3, pencerede(v.ceyrekSonOdeme),
               v.ceyrekGeciciVergi > 0 {
                kalemler.append(NakitKalemi(id: "vergi:\(ceyrekSonu)", gun: v.ceyrekSonOdeme,
                                            ad: "\(v.ceyrek). çeyrek geçici vergi",
                                            tutar: -v.ceyrekGeciciVergi, tahmini: true))
            }
        }

        // 5) Tahminler: satış tahsilatı, düzensiz gider, stok alımı (günlük eşit).
        // Bir ay için girilmiş (bilinen) tek seferlik gider ve alımlar o ayın tahmininden düşülür:
        // yoksa hem bilinen kalem hem ortalama olarak iki kez sayılırdı.
        var aylikBilinen: [MonthKey: Kurus] = [:]
        func gunlukDuzensiz(_ gun: DateKey) -> Double {
            let m = Dates.month(of: gun)
            let bilinen: Kurus
            if let c = aylikBilinen[m] { bilinen = c } else {
                bilinen = expenseInstances(month: m)
                    .filter { $0.sourceKind == .tekSeferlik || $0.sourceKind == .stokAlimi }
                    .reduce(0) { $0 + $1.cashAmount }
                aylikBilinen[m] = bilinen
            }
            let gunSayisi = Dates.daysInMonth(year: Dates.year(of: m), month: Dates.monthNumber(of: m))
            return Double(max(ort.duzensiz + ort.stok - bilinen, 0)) / Double(gunSayisi)
        }
        // Girilmiş kanal alacakları geçmiş satışların parasıdır; tahmini tahsilat onlardan sonra başlar
        let sonAlacak = state.balances
            .filter { !$0.settled && $0.kind == .alacak && $0.source == .kanal }
            .compactMap(\.dueDate).max()
        let tahsilatBas = max(bas, sonAlacak ?? bas)

        // Haftalık toplama
        var haftalar: [NakitHafta] = []
        var b = bakiye
        var bitti: Int?
        for h in 0..<hafta {
            let hb = Dates.addDays(bas, h * 7)
            let hs = Dates.addDays(bas, (h + 1) * 7)
            let buHafta = kalemler.filter { $0.gun > hb && $0.gun <= hs }
            var giris = buHafta.filter { $0.tutar > 0 }.reduce(0) { $0 + $1.tutar }
            var cikis = -buHafta.filter { $0.tutar < 0 }.reduce(0) { $0 + $1.tutar }
            // Tahmini kalemler: haftanın tahsilat başladıktan sonraki günleri kadar
            let tahsilatGunu = max(0, min(7, Dates.daysBetween(max(hb, tahsilatBas), hs)))
            giris += Money.roundHalfAwayFromZero(Double(ort.tahsilat) * Double(tahsilatGunu) / 30)
            cikis += Money.roundHalfAwayFromZero((1...7).reduce(0.0) { $0 + gunlukDuzensiz(Dates.addDays(hb, $1)) })
            b += giris - cikis
            if bitti == nil, b < 0 { bitti = h + 1 }
            haftalar.append(NakitHafta(baslangic: Dates.addDays(hb, 1), bitis: hs,
                                       giris: giris, cikis: cikis, bakiye: b))
        }
        return NakitTahmini(baslangicBakiye: bakiye, baslangicGunu: bas, haftalar: haftalar,
                            bilinenKalemler: kalemler.sorted { $0.gun < $1.gun },
                            bittigiHafta: bitti, aylikTahsilat: ort.tahsilat,
                            aylikDuzensizGider: ort.duzensiz, aylikStokAlimi: ort.stok,
                            tahsilatBaslangici: tahsilatBas)
    }
}
