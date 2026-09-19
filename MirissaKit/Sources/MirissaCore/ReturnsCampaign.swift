import Foundation

/// İade analizi: hangi ürün hangi kanalda ne kadar iade oluyor, iade neye mal oluyor.
public struct IadeSatiri: Identifiable, Hashable, Sendable {
    public var productId: Id
    public var productName: String
    public var channelId: Id
    public var channelName: String
    public var satilan: Double
    public var iade: Double
    /// Hasarlı dönüp stoğa giremeyen
    public var hasarli: Double
    /// İade edilen satış tutarı (KDV hariç)
    public var iadeTutari: Kurus
    /// İade edilen siparişlerin kolisi, patpatı geri gelmez
    public var bosaGidenAmbalaj: Kurus
    /// Hasarlı dönen malın maliyeti (fire)
    public var hasarliMaliyet: Kurus
    public var id: String { "\(channelId)#\(productId)" }
    public var oranPct: Double { satilan > 0 ? iade / satilan * 100 : 0 }
    public var toplamKayip: Kurus { bosaGidenAmbalaj + hasarliMaliyet }
}

/// Kampanya ya da indirim hesabı
public struct KampanyaSonucu: Hashable, Sendable {
    public var indirimPct: Double
    public var eskiFiyat: Kurus
    public var yeniFiyat: Kurus
    /// Tek ürünlük bir siparişin bıraktığı (reklamdan önce)
    public var eskiKatki: Kurus
    public var yeniKatki: Kurus
    /// Aynı toplam kârı tutturmak için sipariş kaç kat artmalı (yeni katkı ≤ 0 ise nil)
    public var gerekenSiparisCarpani: Double?
    /// Bu ayın başa baş sipariş sayısı: önce / sonra (sabit gider biliniyorsa)
    public var basaBasOnce: Int?
    public var basaBasSonra: Int?
}

public extension Engine {

    func iadeAnalizi(from: MonthKey, to: MonthKey) -> [IadeSatiri] {
        var sonuc: [String: IadeSatiri] = [:]
        for e in state.sales where e.month >= from && e.month <= to {
            let anahtar = "\(e.channelId)#\(e.productId)"
            let b = cost(of: e.productId, asOf: Dates.monthEnd(e.month))
            let oran = e.resolvedVatRate, dahil = e.resolvedVatIncluded
            var s = sonuc[anahtar] ?? IadeSatiri(
                productId: e.productId, productName: productsById[e.productId]?.name ?? "Ürün",
                channelId: e.channelId, channelName: state.channel(e.channelId)?.name ?? "Kanal",
                satilan: 0, iade: 0, hasarli: 0, iadeTutari: 0, bosaGidenAmbalaj: 0, hasarliMaliyet: 0)
            s.satilan += e.qty
            s.iade += e.returnsQty
            s.iadeTutari += Vat.net(e.returnsAmount, rate: oran, included: dahil)
            // Koli sipariş başınadır: iade edilen adet, o ay kanalda ürün başına düşen koli oranıyla sayılır
            // (1–2 ürün 1 koli). Ürünün kendi ambalajı (patpat, dolgu, etiket) adet başınadır.
            let kanal = channelResult(channelId: e.channelId, month: e.month)
            let koliOrani = kanal.units > 0 ? min(kanal.koliSayisi / kanal.units, 1) : 1
            s.bosaGidenAmbalaj += Money.roundHalfAwayFromZero(
                Double(b.packaging) * e.returnsQty + Double(b.orderPackaging) * e.returnsQty * koliOrani)
            if !e.returnsRestock {
                s.hasarli += e.returnsQty
                s.hasarliMaliyet += Money.roundHalfAwayFromZero(Double(b.intrinsic) * e.returnsQty)
            }
            sonuc[anahtar] = s
        }
        return sonuc.values.filter { $0.iade > 0 }.sorted { $0.oranPct > $1.oranPct }
    }

    func kampanyaHesabi(productId: Id, channelId: Id, indirimPct: Double,
                        on date: DateKey = Dates.today()) -> KampanyaSonucu? {
        guard let u = unitContribution(productId: productId, channelId: channelId, on: date),
              let ch = state.channel(channelId), indirimPct >= 0, indirimPct < 100 else { return nil }
        let yeniFiyat = Money.roundHalfAwayFromZero(Double(u.price) * (1 - indirimPct / 100))
        let oran = u.price > 0 ? Double(u.netRevenue) / Double(u.price) : 1
        let yeniNet = Money.roundHalfAwayFromZero(Double(yeniFiyat) * oran)
        let kesinti = kanalKesintisi(ch, siparisDegeri: yeniFiyat, on: date,
                                     satisKdv: satisKdvOrani(productId: productId, channelId: channelId, on: date)).0.toplam
        let yeniKatki = yeniNet - kesinti - u.productCost - u.packagingCost - u.orderPackagingCost
        let ay = Dates.month(of: date)
        // Ana başa baş kartıyla aynı temel: satışa bağlı giderler (değişken reklam, influencer…)
        // son satışlı ayda sipariş başına ne düştüyse o kadar düşülür; satış yoksa aylık tutar sabite eklenir.
        let temelAy = (1...12).map { Dates.addMonths(ay, -$0) }.first { companyMonth($0).orders > 0 }
        var sabit = Double(plannedFixedCosts(month: ay))
        var degiskenSiparisBasi = 0.0
        if let m = temelAy {
            let r = companyMonth(m)
            let toplam = r.ortakGiderDegisken
                + r.channels.reduce(0) { $0 + $1.adsVariable + $1.otherChannelExpensesVariable }
            degiskenSiparisBasi = Double(max(toplam, 0)) / Double(r.orders)
        } else {
            sabit += Double(satisaBagliAylikGiderler(month: ay))
        }
        func basaBas(_ k: Kurus) -> Int? {
            let net = Double(k) - degiskenSiparisBasi
            return net > 0 && sabit > 0 ? Int((sabit / net).rounded(.up)) : nil
        }
        return KampanyaSonucu(
            indirimPct: indirimPct, eskiFiyat: u.price, yeniFiyat: yeniFiyat,
            eskiKatki: u.contribution, yeniKatki: yeniKatki,
            gerekenSiparisCarpani: yeniKatki > 0 ? Double(u.contribution) / Double(yeniKatki) : nil,
            basaBasOnce: basaBas(u.contribution), basaBasSonra: basaBas(yeniKatki))
    }
}
