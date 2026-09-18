import Testing
import Foundation
@testable import MirissaCore

/// Bağımsız hesaplayıcı — ikinci bölüm: düzenli giderlerin yıl içindeki
/// dağılımı, KDV devri ve ağırlıklı ortalama maliyet.
@Suite("Bağımsız hesaplayıcı: gider takvimi, KDV devri, ortalama maliyet")
struct ReferenceLedgerTests {

    struct R: RandomNumberGenerator {
        var d: UInt64
        init(_ t: UInt64) { d = t &* 0x9E37_79B9_7F4A_7C15 &+ 1 }
        mutating func next() -> UInt64 { d ^= d << 13; d ^= d >> 7; d ^= d << 17; return d }
    }

    private func yuvarla(_ v: Double) -> Int {
        v < 0 ? -Int((-v).rounded(.toNearestOrAwayFromZero)) : Int(v.rounded(.toNearestOrAwayFromZero))
    }

    private func net(_ t: Kurus, _ o: VatRate?, _ dahil: Bool?) -> (net: Kurus, kdv: Kurus) {
        let r = o ?? .yok
        guard r != .yok, t != 0 else { return (t, 0) }
        let m = Double(r.rawValue) / 100
        if dahil ?? true { let n = yuvarla(Double(t) / (1 + m)); return (n, t - n) }
        return (t, yuvarla(Double(t) * m))
    }

    private let aylar = (1...12).map { String(format: "2026-%02d", $0) }

    // MARK: 1 — Düzenli giderler yıl boyunca doğru aylara düşüyor mu

    @Test func duzenliGiderTakvimiBagimsizHesaplaAyni() {
        var g = R(2026)
        for tur in 0..<300 {
            var s = AppState()
            for k in 0..<Int.random(in: 1...8, using: &g) {
                let basAy = Int.random(in: 1...12, using: &g)
                let tekrar = [Recurrence.tek, .aylik, .yillik].randomElement(using: &g)!
                var e = Expense(
                    id: "e\(k)", date: String(format: "2026-%02d-%02d", basAy,
                                              Int.random(in: 1...28, using: &g)),
                    name: "G\(k)", amount: Kurus(Int.random(in: 1...900_000, using: &g)),
                    category: .sabit, recurrence: tekrar,
                    vatRate: [VatRate.yok, .on, .yirmi].randomElement(using: &g)!,
                    vatIncluded: Bool.random(using: &g))
                if Bool.random(using: &g) {
                    e.endMonth = String(format: "2026-%02d", Int.random(in: basAy...12, using: &g))
                }
                for ay in aylar where Int.random(in: 0...5, using: &g) == 0 {
                    e.overrides[ay] = Bool.random(using: &g)
                        ? ExpenseOverride(skipped: true)
                        : ExpenseOverride(amount: Kurus(Int.random(in: 1...500_000, using: &g)))
                }
                s.expenses.append(e)
            }
            let motor = Engine(s)

            for ay in aylar {
                var beklenen: Kurus = 0
                var beklenenKdv: Kurus = 0
                for e in s.expenses {
                    let bas = String(e.date.prefix(7))
                    guard ay >= bas else { continue }
                    // Yıllık gider durdurulsa da ödenmiş yılın payları yıl sonuna kadar yazılır
                    // (bu senaryoda bitiş hep ilk ödeme ayında ya da sonrasında, tek yıl içinde)
                    if let bitis = e.endMonth, ay > bitis, e.recurrence != .yillik { continue }
                    let aySayisi = (Int(ay.suffix(2))! - Int(bas.suffix(2))!)
                    if e.recurrence == .yillik {
                        // Yıllık: ödeme ayından itibaren her aya 1/12 (artan kuruş ilk aylara),
                        // KDV ödeme ayında. Ödeme ayı atlandıysa o yılın payları da yok.
                        let odemeAyi = String(format: "2026-%02d", Int(bas.suffix(2))! + (aySayisi / 12) * 12)
                        if let o = e.overrides[odemeAyi], o.skipped { continue }
                        let t = e.overrides[odemeAyi]?.amount ?? e.amount
                        let b = net(t, e.vatRate, e.vatIncluded)
                        let taban = b.net / 12, artan = b.net - taban * 12
                        beklenen += taban + (aySayisi % 12 < abs(artan) ? (artan > 0 ? 1 : -1) : 0)
                        if aySayisi % 12 == 0 { beklenenKdv += b.kdv }
                        continue
                    }
                    let dusuyor: Bool
                    switch e.recurrence {
                    case .tek: dusuyor = ay == bas
                    case .aylik, .yillik: dusuyor = true
                    }
                    guard dusuyor else { continue }
                    if let o = e.overrides[ay], o.skipped { continue }
                    let t = e.overrides[ay]?.amount ?? e.amount
                    let b = net(t, e.vatRate, e.vatIncluded)
                    beklenen += b.net
                    beklenenKdv += b.kdv
                }
                let r = motor.companyMonth(ay)
                #expect(r.ortakGider == beklenen, "tur \(tur) \(ay): gider \(r.ortakGider) ≠ \(beklenen)")
                #expect(r.giderKdv == beklenenKdv, "tur \(tur) \(ay): gider KDV")
            }
        }
    }

    // MARK: 2 — KDV aydan aya doğru devrediyor mu

    @Test func kdvDevriBagimsizHesaplaAyni() {
        var g = R(77)
        for tur in 0..<200 {
            var s = Golden.senaryo()
            s.sales = []
            s.expenses = []
            s.purchases = []
            for ay in aylar {
                if Bool.random(using: &g) {
                    s.sales.append(SalesEntry(
                        id: "s\(ay)", month: ay, channelId: Golden.G.trendyol,
                        productId: Golden.G.sampuan, qty: 1,
                        grossSales: Kurus(Int.random(in: 0...2_000_000, using: &g)),
                        vatRate: .yirmi, vatIncluded: true))
                }
                if Bool.random(using: &g) {
                    s.expenses.append(Expense(
                        id: "e\(ay)", date: "\(ay)-10", name: "Gider \(ay)",
                        amount: Kurus(Int.random(in: 0...3_000_000, using: &g)),
                        category: .sabit, recurrence: .tek, vatRate: .yirmi, vatIncluded: true))
                }
            }
            let e = Engine(s)
            var devreden: Kurus = 0
            for ay in aylar {
                let r = e.companyMonth(ay)
                let hesaplanan = r.channels.reduce(0) { $0 + $1.outputVat }
                let indirilecek = r.giderKdv + r.channels.reduce(0) { $0 + $1.feeVat }
                let fark = hesaplanan - indirilecek - devreden
                let odenecek = max(fark, 0)
                let yeniDevreden = max(-fark, 0)
                let v = e.vatStatus(ay)
                #expect(v.oncekiDevreden == devreden, "tur \(tur) \(ay): önceki devreden")
                #expect(v.odenecek == odenecek, "tur \(tur) \(ay): ödenecek")
                #expect(v.devreden == yeniDevreden, "tur \(tur) \(ay): devreden")
                devreden = yeniDevreden
            }
        }
    }

    // MARK: 3 — Ağırlıklı ortalama maliyet

    /// Açılış + alımlar + satış tüketimi, kronolojik ve bağımsız katlama
    @Test func agirlikliOrtalamaBagimsizHesaplaAyni() {
        var g = R(314)
        for tur in 0..<300 {
            var s = AppState()
            let m = StockMaterial(id: "koli", name: "Koli", baseUnit: .adet,
                                  openingQty: Double(Int.random(in: 0...500, using: &g)),
                                  openingUnitCost: Kurus(Int.random(in: 0...2_000, using: &g)),
                                  openingDate: "2026-01-01")
            s.materials = [m]
            s.channels = [Channel(id: "k", name: "K")]
            s.products = [Product(id: "p", name: "P",
                                  recipe: [RecipeLine(id: "r", materialId: "koli",
                                                      qty: 1, unit: .adet)],
                                  openingQty: 100_000, openingDate: "2026-01-01")]

            // Rastgele ayda alımlar ve satışlar
            for ay in aylar {
                if Bool.random(using: &g) {
                    s.purchases.append(StockPurchase(
                        id: "a\(ay)", date: "\(ay)-05", item: .material("koli"),
                        qty: Double(Int.random(in: 1...800, using: &g)), unit: .adet,
                        totalPaid: Kurus(Int.random(in: 100...1_500_000, using: &g))))
                }
                if Bool.random(using: &g) {
                    s.sales.append(SalesEntry(
                        id: "s\(ay)", month: ay, channelId: "k", productId: "p",
                        qty: Double(Int.random(in: 1...300, using: &g)),
                        grossSales: 1_000))
                }
            }

            // Bağımsız katlama: her ayda önce alımlar (ayın 5'i), sonra satış (ay sonu)
            var adet = m.openingQty ?? 0
            var deger = Double(m.openingUnitCost ?? 0) * adet
            var sonMaliyet = adet > 0 ? deger / adet : Double(m.openingUnitCost ?? 0)
            var fiyatlar: [Double] = (m.openingQty ?? 0) > 0 ? [Double(m.openingUnitCost ?? 0)] : []
            for ay in aylar {
                for p in s.purchases where p.date.hasPrefix(ay) {
                    let fiyat = Double(p.totalPaid) / p.qty
                    fiyatlar.append(fiyat)
                    if adet < 0 {
                        // Eksi stoktayken alım: kalan bu alımın fiyatıyla değerlenir
                        adet += p.qty
                        deger = adet * fiyat
                        sonMaliyet = fiyat
                    } else {
                        adet += p.qty
                        deger += Double(p.totalPaid)
                        sonMaliyet = adet > 0 ? deger / adet : sonMaliyet
                    }
                }
                for sat in s.sales where sat.month == ay {
                    let birim = adet > 0 ? deger / adet : sonMaliyet
                    adet -= sat.qty
                    deger -= birim * sat.qty
                    if adet > 0 { sonMaliyet = deger / adet } else {
                        sonMaliyet = birim
                        deger = adet * birim
                    }
                }
            }
            let motor = Engine(s)
            #expect(abs(motor.qty(.material("koli")) - adet) < 0.0001, "tur \(tur): adet")
            let beklenenBirim = adet > 0 ? deger / adet : sonMaliyet
            #expect(abs(motor.unitCost(.material("koli")) - beklenenBirim) < 0.01,
                    "tur \(tur): birim maliyet \(motor.unitCost(.material("koli"))) ≠ \(beklenenBirim)")

            // Kural seçiminden bağımsız şart: birim maliyet asla eksi olmaz ve
            // girilen alış fiyatlarının aralığı dışına çıkmaz. Her ara adımda.
            if let enAz = fiyatlar.min(), let enCok = fiyatlar.max() {
                for r in motor.history(.material("koli")) {
                    #expect(r.unitCostAfter >= 0, "tur \(tur): eksi birim maliyet \(r.unitCostAfter)")
                    #expect(r.unitCostAfter <= enCok + 0.01,
                            "tur \(tur): maliyet en yüksek alış fiyatını aştı \(r.unitCostAfter) > \(enCok)")
                    if r.balanceAfter > 0 {
                        #expect(r.unitCostAfter >= enAz - 0.01,
                                "tur \(tur): maliyet en düşük alış fiyatının altına indi")
                    }
                }
            }
        }
    }
}

/// Bulunan hata: eksi stoktayken gelen alımlar birim maliyeti şişiriyor,
/// bazen eksiye düşürüyordu. Gerçek kullanımda sık olur: başlangıç stoğu
/// girilmeden satış girilip sonra alım eklenirse.
@Suite("Eksi stokta alım maliyeti")
struct NegativeStockPurchaseTests {

    private func durum() -> AppState {
        var s = AppState()
        s.materials = [StockMaterial(id: "koli", name: "Koli", baseUnit: .adet)]
        s.channels = [Channel(id: "k", name: "K")]
        s.products = [Product(id: "p", name: "P",
                              recipe: [RecipeLine(id: "r", materialId: "koli", qty: 1, unit: .adet)],
                              openingQty: 10_000, openingDate: "2026-01-01")]
        return s
    }

    @Test func alimEksigiKapatinaKalanSonFiyatlaDegerlenir() {
        var s = durum()
        // Başlangıç stoğu girilmemiş: Ocak'ta 100 koli kullanıldı -> stok -100
        s.sales = [SalesEntry(id: "s1", month: "2026-01", channelId: "k", productId: "p",
                              qty: 100, grossSales: tl(10_000))]
        // Şubat: 50 koli × 10 TL -> hâlâ -50
        s.purchases = [StockPurchase(id: "a1", date: "2026-02-05", item: .material("koli"),
                                     qty: 50, unit: .adet, totalPaid: tl(500))]
        var e = Engine(s)
        #expect(e.qty(.material("koli")) == -50)
        #expect(e.unitCost(.material("koli")) == Double(tl(10)))

        // Mart: 200 koli × 12 TL -> +150, birim maliyet 12 TL
        s.purchases.append(StockPurchase(id: "a2", date: "2026-03-05", item: .material("koli"),
                                         qty: 200, unit: .adet, totalPaid: tl(2_400)))
        e = Engine(s)
        #expect(e.qty(.material("koli")) == 150)
        // Eski motor burada 16 TL diyordu (2.400 TL'yi 150 adede bölerek)
        #expect(e.unitCost(.material("koli")) == Double(tl(12)))
        #expect(e.balance(.material("koli")).value == tl(1_800))
    }

    @Test func birimMaliyetAsiaEksiOlmaz() {
        var s = durum()
        s.purchases = [
            StockPurchase(id: "a1", date: "2026-01-05", item: .material("koli"),
                          qty: 100, unit: .adet, totalPaid: tl(1_000)),
            StockPurchase(id: "a2", date: "2026-03-05", item: .material("koli"),
                          qty: 80, unit: .adet, totalPaid: tl(960)),
            StockPurchase(id: "a3", date: "2026-05-05", item: .material("koli"),
                          qty: 500, unit: .adet, totalPaid: tl(5_500)),
        ]
        s.sales = [
            SalesEntry(id: "s1", month: "2026-02", channelId: "k", productId: "p",
                       qty: 250, grossSales: tl(1)),
            SalesEntry(id: "s2", month: "2026-04", channelId: "k", productId: "p",
                       qty: 300, grossSales: tl(1)),
        ]
        let e = Engine(s)
        for r in e.history(.material("koli")) {
            #expect(r.unitCostAfter >= 0, "\(r.date): eksi maliyet \(r.unitCostAfter)")
            #expect(r.unitCostAfter <= Double(tl(12)) + 0.01, "\(r.date): \(r.unitCostAfter)")
        }
        // Mayıs sonrası kalan stok son alımın fiyatında: 11 TL
        #expect(e.unitCost(.material("koli")) == Double(tl(11)))
        // Eksiye düşen stok bütünlük denetiminde bildirilir
        var eksi = s
        eksi.purchases.removeLast()
        #expect(Integrity.check(eksi).contains { $0.message.contains("eksiye düştü") })
    }
}
