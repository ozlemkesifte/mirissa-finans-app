import Foundation

/// Trendyol / Shopify sipariş raporlarını (CSV) aylık satış kayıtlarına çevirir.
/// Satırlar sipariş kalemleridir; aynı sipariş numarası birden çok satırda olabilir.
public enum RaporIceAktarma {

    public enum Alan: String, CaseIterable, Sendable, Hashable {
        case siparisNo, tarih, urun, sku, adet, birimFiyat, satirTutari, indirim, durum

        public var ad: String {
            switch self {
            case .siparisNo: return "Sipariş numarası"
            case .tarih: return "Sipariş tarihi"
            case .urun: return "Ürün adı"
            case .sku: return "Barkod / SKU"
            case .adet: return "Adet"
            case .birimFiyat: return "Birim fiyat"
            case .satirTutari: return "Satır tutarı"
            case .indirim: return "İndirim"
            case .durum: return "Sipariş durumu"
            }
        }

        /// Sütun başlığında aranan ifadeler (küçük harf, Türkçe/İngilizce)
        var anahtarlar: [String] {
            switch self {
            case .siparisNo: return ["sipariş numarası", "sipariş no", "siparis no", "order id", "order number", "name", "sipariş"]
            case .tarih: return ["sipariş tarihi", "created at", "order date", "tarih", "paid at", "date"]
            case .urun: return ["ürün adı", "lineitem name", "ürün ismi", "product name", "ürün", "product"]
            case .sku: return ["barkod", "stok kodu", "lineitem sku", "sku", "barcode"]
            case .adet: return ["lineitem quantity", "adet", "miktar", "quantity", "qty"]
            case .birimFiyat: return ["birim fiyat", "lineitem price", "unit price", "satış fiyatı"]
            case .satirTutari: return ["faturalanacak tutar", "satış tutarı", "tutar", "line total", "total"]
            case .indirim: return ["indirim tutarı", "lineitem discount", "indirim", "discount amount", "discount"]
            case .durum: return ["sipariş statüsü", "sipariş durumu", "financial status", "durum", "status"]
            }
        }
    }

    public struct Tablo: Sendable {
        public var basliklar: [String]
        public var satirlar: [[String]]
    }

    // MARK: CSV

    /// Ayraç (virgül, noktalı virgül, sekme) ilk satırdan anlaşılır; tırnaklı alanlar desteklenir.
    public static func oku(_ metin: String) -> Tablo {
        var m = metin
        if m.hasPrefix("\u{FEFF}") { m.removeFirst() }
        let ilkSatir = m.prefix { $0 != "\n" && $0 != "\r" }
        let adaylar: [Character] = [";", ",", "\t"]
        let ayrac = adaylar.max { a, b in ilkSatir.filter { $0 == a }.count < ilkSatir.filter { $0 == b }.count } ?? ","
        var satirlar: [[String]] = []
        var satir: [String] = []
        var alan = ""
        var tirnak = false
        var i = m.unicodeScalars.makeIterator()
        var onceki: Unicode.Scalar?
        while let c = i.next() {
            if tirnak {
                if c == "\"" {
                    if let n = i.next() {
                        if n == "\"" { alan.unicodeScalars.append("\"") }
                        else {
                            tirnak = false
                            if Character(n) == ayrac { satir.append(alan); alan = "" }
                            else if n == "\n" || n == "\r" {
                                if !(n == "\n" && onceki == "\r") { satir.append(alan); satirlar.append(satir) }
                                satir = []; alan = ""
                            } else { alan.unicodeScalars.append(n) }
                            onceki = n
                            continue
                        }
                    } else { tirnak = false }
                } else { alan.unicodeScalars.append(c) }
            } else if c == "\"" && alan.isEmpty {
                tirnak = true
            } else if Character(c) == ayrac {
                satir.append(alan); alan = ""
            } else if c == "\n" || c == "\r" {
                if c == "\n" && onceki == "\r" { onceki = c; continue }
                satir.append(alan); satirlar.append(satir); satir = []; alan = ""
            } else {
                alan.unicodeScalars.append(c)
            }
            onceki = c
        }
        if !alan.isEmpty || !satir.isEmpty { satir.append(alan); satirlar.append(satir) }
        satirlar = satirlar.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let baslik = satirlar.first else { return Tablo(basliklar: [], satirlar: []) }
        return Tablo(basliklar: baslik.map { $0.trimmingCharacters(in: .whitespaces) },
                     satirlar: Array(satirlar.dropFirst()))
    }

    /// Sütunları başlıklarından tanır. Her alan için ilk uyan sütun; bir sütun iki alana verilmez.
    public static func sutunlariBul(_ basliklar: [String]) -> [Alan: Int] {
        let kucuk = basliklar.map { $0.lowercased(with: Locale(identifier: "tr_TR")) }
        var out: [Alan: Int] = [:]
        var kullanilan = Set<Int>()
        // Önce tam eşleşme, sonra içerme
        for tamMi in [true, false] {
            for alan in Alan.allCases where out[alan] == nil {
                for anahtar in alan.anahtarlar {
                    if let i = kucuk.indices.first(where: { !kullanilan.contains($0)
                        && (tamMi ? kucuk[$0] == anahtar : kucuk[$0].contains(anahtar)) }) {
                        out[alan] = i; kullanilan.insert(i); break
                    }
                }
            }
        }
        return out
    }

    // MARK: Sayı ve tarih

    /// "1.234,56" · "1234,56" · "1,234.56" · "1234.56" · "₺1.234" · "TRY 99"
    public static func tutar(_ s: String) -> Kurus? {
        var t = s.filter { "0123456789.,-".contains($0) }
        guard !t.isEmpty else { return nil }
        let virgul = t.lastIndex(of: ","), nokta = t.lastIndex(of: ".")
        if let v = virgul, let n = nokta {
            if v > n { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { t = t.replacingOccurrences(of: ",", with: "") }
        } else if let v = virgul {
            let sonrasi = t[t.index(after: v)...].count
            t = sonrasi == 3 && t.filter({ $0 == "," }).count >= 1 && !t.hasPrefix("0,")
                ? t.replacingOccurrences(of: ",", with: "")
                : t.replacingOccurrences(of: ",", with: ".")
        } else if let n = nokta {
            let sonrasi = t[t.index(after: n)...].count
            if sonrasi == 3 && t.filter({ $0 == "." }).count >= 1 && !t.hasPrefix("0.") {
                t = t.replacingOccurrences(of: ".", with: "")
            }
        }
        guard let d = Double(t) else { return nil }
        return Money.roundHalfAwayFromZero(d * 100)
    }

    public static func adet(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return Double(t)
    }

    /// "2026-09-01 10:22:33 +0300" · "01.09.2026 10:22" · "01/09/2026" · "1.9.2026"
    public static func tarih(_ s: String) -> DateKey? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let ilk = t.split(whereSeparator: { $0 == " " || $0 == "T" }).first.map(String.init) ?? t
        let p = ilk.split(whereSeparator: { "-./".contains($0) }).compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        let (y, a, g): (Int, Int, Int) = p[0] > 31 ? (p[0], p[1], p[2]) : (p[2], p[1], p[0])
        guard (1...12).contains(a), (1...31).contains(g), y > 1900 else { return nil }
        return String(format: "%04d-%02d-%02d", y, a, g)
    }

    // MARK: Satırlar

    public struct Kalem: Hashable, Sendable {
        public var siparisNo: String
        public var tarih: DateKey
        public var urunAnahtari: String   // SKU varsa SKU, yoksa ürün adı
        public var urunAdi: String
        public var adet: Double
        /// Satırın müşteriye tutarı (KDV dahil, satır indirimi düşülmemiş)
        public var tutar: Kurus
        public var indirim: Kurus
        public var iptal: Bool
    }

    public struct Hata: Hashable, Sendable {
        public var satir: Int
        public var neden: String
    }

    public static func kalemler(_ t: Tablo, sutun: [Alan: Int]) -> (kalemler: [Kalem], hatalar: [Hata]) {
        var out: [Kalem] = []
        var hatalar: [Hata] = []
        var sonSiparis = "", sonTarih: DateKey?
        func deger(_ r: [String], _ a: Alan) -> String? {
            guard let i = sutun[a], i < r.count else { return nil }
            let v = r[i].trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        }
        for (n, r) in t.satirlar.enumerated() {
            let no = deger(r, .siparisNo) ?? sonSiparis
            // Shopify: aynı siparişin sonraki satırlarında tarih boş olabilir
            let tarihMetni = deger(r, .tarih)
            let gun = tarihMetni.flatMap(tarih) ?? (no == sonSiparis ? sonTarih : nil)
            sonSiparis = no; sonTarih = gun
            let ad = deger(r, .urun) ?? ""
            let anahtar = deger(r, .sku) ?? ad
            guard !anahtar.isEmpty else { continue }   // ürünsüz satır (kargo, toplam satırı)
            guard let g = gun else { hatalar.append(Hata(satir: n + 2, neden: "Tarih okunamadı")); continue }
            let a = deger(r, .adet).flatMap(adet) ?? 1
            var tutar: Kurus
            if let st = deger(r, .satirTutari).flatMap(Self.tutar), sutun[.birimFiyat] == nil {
                tutar = st
            } else if let bf = deger(r, .birimFiyat).flatMap(Self.tutar) {
                tutar = Money.roundHalfAwayFromZero(Double(bf) * a)
            } else if let st = deger(r, .satirTutari).flatMap(Self.tutar) {
                tutar = st
            } else {
                hatalar.append(Hata(satir: n + 2, neden: "Tutar okunamadı")); continue
            }
            let durum = (deger(r, .durum) ?? "").lowercased(with: Locale(identifier: "tr_TR"))
            let iptal = ["iptal", "cancel", "void", "refunded", "iade edildi"].contains { durum.contains($0) }
            out.append(Kalem(siparisNo: no, tarih: g, urunAnahtari: anahtar, urunAdi: ad.isEmpty ? anahtar : ad,
                             adet: a, tutar: tutar, indirim: abs(deger(r, .indirim).flatMap(Self.tutar) ?? 0),
                             iptal: iptal))
        }
        return (out, hatalar)
    }

    /// Rapordaki ürün anahtarını uygulamadaki ürünle eşleştirmek için öneri:
    /// barkod/SKU tam eşleşme, sonra ad içerme.
    public static func eslestirmeOnerisi(_ anahtar: String, ad: String, urunler: [Product]) -> Id? {
        let k = ad.lowercased(with: Locale(identifier: "tr_TR"))
        if let p = urunler.first(where: { ($0.sku ?? "").caseInsensitiveCompare(anahtar) == .orderedSame && !($0.sku ?? "").isEmpty }) {
            return p.id
        }
        let adaylar = urunler.filter { k.contains($0.name.lowercased(with: Locale(identifier: "tr_TR"))) }
        return adaylar.count == 1 ? adaylar[0].id : adaylar.max { $0.name.count < $1.name.count }?.id
    }

    public struct Sonuc: Sendable {
        public var satislar: [SalesEntry]
        public var aylar: [ChannelMonth]
        public var siparisSayisi: Int
        public var iptalSiparis: Int
        public var atlananKalem: Int
        public var aylarListesi: [MonthKey]
    }

    /// Kalemleri ay × ürün satışlarına ve ay kayıtlarına (sipariş sayısı, 3+ ürünlü sipariş) çevirir.
    /// `eslesme`: rapor ürün anahtarı → uygulama ürünü (nil = atla).
    public static func donustur(_ kalemler: [Kalem], kanalId: Id, eslesme: [String: Id],
                                mevcutAylar: [ChannelMonth], kdvOrani: VatRate?) -> Sonuc {
        let gecerli = kalemler.filter { !$0.iptal }
        let iptal = Set(kalemler.filter(\.iptal).map(\.siparisNo)).count
        var atlanan = 0
        struct Anahtar: Hashable { var ay: MonthKey; var urun: Id }
        var toplam: [Anahtar: (adet: Double, tutar: Kurus, indirim: Kurus)] = [:]
        var siparisAdet: [MonthKey: [String: Double]] = [:]
        for k in gecerli {
            guard let urun = eslesme[k.urunAnahtari] else { atlanan += 1; continue }
            let ay = Dates.month(of: k.tarih)
            let a = Anahtar(ay: ay, urun: urun)
            var t = toplam[a] ?? (0, 0, 0)
            t.adet += k.adet; t.tutar += k.tutar; t.indirim += k.indirim
            toplam[a] = t
            siparisAdet[ay, default: [:]][k.siparisNo, default: 0] += k.adet
        }
        let satislar = toplam.keys.sorted { ($0.ay, $0.urun) < ($1.ay, $1.urun) }.map { a -> SalesEntry in
            let t = toplam[a]!
            return SalesEntry(month: a.ay, channelId: kanalId, productId: a.urun, qty: t.adet,
                              grossSales: t.tutar, discount: min(t.indirim, t.tutar),
                              vatRate: kdvOrani, vatIncluded: true)
        }
        var aylar: [ChannelMonth] = []
        for (ay, siparisler) in siparisAdet {
            var cm = mevcutAylar.first { $0.month == ay && $0.channelId == kanalId }
                ?? ChannelMonth(month: ay, channelId: kanalId)
            cm.orderCount = siparisler.count
            cm.bigOrderCount = siparisler.values.filter { $0 >= Double(OrderPackaging.ikinciKoliUrunSayisi) }.count
            aylar.append(cm)
        }
        return Sonuc(satislar: satislar, aylar: aylar.sorted { $0.month < $1.month },
                     siparisSayisi: siparisAdet.values.reduce(0) { $0 + $1.count },
                     iptalSiparis: iptal, atlananKalem: atlanan,
                     aylarListesi: siparisAdet.keys.sorted())
    }
}
