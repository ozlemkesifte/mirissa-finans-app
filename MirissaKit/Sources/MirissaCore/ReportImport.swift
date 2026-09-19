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
        } else if virgul != nil {
            // Yalnız virgül: birden çoksa binlik (1,234,567), tekse Türkçe ondalık (12,5 · 12,500)
            t = t.filter({ $0 == "," }).count > 1
                ? t.replacingOccurrences(of: ",", with: "")
                : t.replacingOccurrences(of: ",", with: ".")
        } else if let n = nokta {
            let sonrasi = t[t.index(after: n)...].count
            let rakamlar = t.hasPrefix("-") ? String(t.dropFirst()) : t
            // Birden çok nokta ya da tek nokta + 3 hane: binlik (1.234 TL); "0." ile başlayan ondalıktır
            if t.filter({ $0 == "." }).count > 1 || (sonrasi == 3 && !rakamlar.hasPrefix("0.")) {
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
        /// Tamamı iade edilen sipariş: satılmış (kargosu ödenmiş) ve iade alınmış sayılır, silinmez
        public var iade: Bool = false
    }

    public struct Hata: Hashable, Sendable {
        public var satir: Int
        public var neden: String
    }

    public static func kalemler(_ t: Tablo, sutun: [Alan: Int]) -> (kalemler: [Kalem], hatalar: [Hata]) {
        var out: [Kalem] = []
        var hatalar: [Hata] = []
        var sonSiparis = "", sonTarih: DateKey?, sonDurum: String?
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
            // Shopify ödeme durumunu da yalnızca siparişin ilk satırına yazar
            let durumMetni = deger(r, .durum) ?? (no == sonSiparis ? sonDurum : nil)
            sonSiparis = no; sonTarih = gun; sonDurum = durumMetni
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
            let durum = (durumMetni ?? "").lowercased(with: Locale(identifier: "tr_TR"))
            // İptal: hiç gönderilmedi, satış sayılmaz. İade: gönderildi ve geri geldi (kargo ödendi).
            // Kısmi iade hangi satır olduğunu söylemez: satış olduğu gibi kalır, iadeyi elle girersin.
            let iptal = ["iptal", "cancel", "void"].contains { durum.contains($0) }
            let kismi = durum.contains("partial") || durum.contains("kısmi")
            let iade = !iptal && !kismi && (durum == "refunded" || durum.contains("iade"))
            out.append(Kalem(siparisNo: no, tarih: g, urunAnahtari: anahtar, urunAdi: ad.isEmpty ? anahtar : ad,
                             adet: a, tutar: tutar, indirim: abs(deger(r, .indirim).flatMap(Self.tutar) ?? 0),
                             iptal: iptal, iade: iade))
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
        /// Daha önce rapor aktarılmış aylar: satışlar silinmez, yeni siparişler üstüne eklenir
        public var eklenenAylar: [MonthKey] = []
        /// Daha önce aktarıldığı için tekrar sayılmayan sipariş sayısı
        public var tekrarAtlanan: Int = 0
        /// Önceki aktarımda alınıp sonradan iptal/iade edilen siparişlerin satırları: satışlardan düşülür
        public var geriAlinacak: [SalesEntry] = []
        public var sonradanIptal: Int = 0
        /// Önceki aktarımda alınıp sonradan iade edilen siparişlerin iadesi: mevcut satışa eklenir
        public var iadeEklenecek: [SalesEntry] = []
    }

    /// Kanal-ay kayıtları; satışı silinmiş ayın "aktarılmış sipariş" listesi yok sayılır
    /// (satışları elle silinen ay yeniden aktarılabilsin)
    public static func satisiOlanAylar(_ s: AppState, kanalId: Id) -> [ChannelMonth] {
        let satisliAylar = Set(s.sales.filter { $0.channelId == kanalId }.map(\.month))
        return s.channelMonths.map { cm in
            var c = cm
            if cm.channelId == kanalId, !satisliAylar.contains(cm.month) {
                c.iceAktarilanSiparisler = nil
                c.iadesiAlinanSiparisler = nil
            }
            return c
        }
    }

    /// Kalemleri ay × ürün satışlarına ve ay kayıtlarına (sipariş sayısı, 3+ ürünlü sipariş) çevirir.
    /// `eslesme`: rapor ürün anahtarı → uygulama ürünü (nil = atla).
    /// `urunKdvOrani`: ürünün satış KDV oranı (ürüne özel oran ya da varsayılan; KDV kapalıysa nil)
    public static func donustur(_ kalemler: [Kalem], kanalId: Id, eslesme: [String: Id],
                                mevcutAylar: [ChannelMonth], urunKdvOrani: (Id) -> VatRate?) -> Sonuc {
        let gecerli = kalemler.filter { !$0.iptal }
        let iptal = Set(kalemler.filter(\.iptal).map(\.siparisNo)).count
        var atlanan = 0
        struct Anahtar: Hashable { var ay: MonthKey; var urun: Id }
        struct Toplam {
            var adet = 0.0, tutar: Kurus = 0, indirim: Kurus = 0
            /// İadede müşterinin ödediği (indirim düşülmüş) tutar toplanır
            mutating func ekle(_ k: Kalem, odenen: Bool = false) {
                adet += k.adet
                if odenen { tutar += max(k.tutar - k.indirim, 0) } else { tutar += k.tutar; indirim += k.indirim }
            }
        }
        var toplam: [Anahtar: Toplam] = [:]
        var iadeToplam: [Anahtar: Toplam] = [:]
        var sonradanIade: [Anahtar: Toplam] = [:]
        var geri: [Anahtar: Toplam] = [:]
        var iadesiAlinan: [MonthKey: Set<String>] = [:]
        var siparisAdet: [MonthKey: [String: Double]] = [:]
        var iptalEdilen: [MonthKey: [String: Double]] = [:]
        let mevcutlar = Dictionary(mevcutAylar.filter { $0.channelId == kanalId }.map { ($0.month, $0) },
                                   uniquingKeysWith: { a, _ in a })
        // Ay başına daha önce aktarılmış / iadesi alınmış siparişler (her ay bir kez kurulur)
        var alinmisCache: [MonthKey: Set<String>] = [:], iadeCache: [MonthKey: Set<String>] = [:]
        func alinmis(_ ay: MonthKey) -> Set<String> {
            if let c = alinmisCache[ay] { return c }
            let c = Set(mevcutlar[ay]?.iceAktarilanSiparisler ?? []); alinmisCache[ay] = c; return c
        }
        func oncekiIade(_ ay: MonthKey) -> Set<String> {
            if let c = iadeCache[ay] { return c }
            let c = Set(mevcutlar[ay]?.iadesiAlinanSiparisler ?? []); iadeCache[ay] = c; return c
        }
        var tekrar = Set<String>()
        for k in gecerli {
            guard let urun = eslesme[k.urunAnahtari] else { atlanan += 1; continue }
            let ay = Dates.month(of: k.tarih)
            let a = Anahtar(ay: ay, urun: urun)
            // Bu sipariş daha önce aktarıldı: tekrar sayılmaz; o zamandan beri iade edildiyse iadesi eklenir
            if alinmis(ay).contains(k.siparisNo) {
                tekrar.insert(k.siparisNo)
                if k.iade, !oncekiIade(ay).contains(k.siparisNo) {
                    sonradanIade[a, default: Toplam()].ekle(k, odenen: true)
                    iadesiAlinan[ay, default: []].insert(k.siparisNo)
                }
                continue
            }
            if k.iade {
                iadeToplam[a, default: Toplam()].ekle(k, odenen: true)
                iadesiAlinan[ay, default: []].insert(k.siparisNo)
            }
            toplam[a, default: Toplam()].ekle(k)
            siparisAdet[ay, default: [:]][k.siparisNo, default: 0] += k.adet
        }
        // Önceki aktarımda alınmış ama bu raporda iptal görünen siparişler geri alınır
        for k in kalemler where k.iptal {
            guard let urun = eslesme[k.urunAnahtari] else { continue }
            let ay = Dates.month(of: k.tarih)
            guard alinmis(ay).contains(k.siparisNo) else { continue }
            geri[Anahtar(ay: ay, urun: urun), default: Toplam()].ekle(k)
            iptalEdilen[ay, default: [:]][k.siparisNo, default: 0] += k.adet
        }
        func satirlar(_ d: [Anahtar: Toplam], _ yap: (Anahtar, Toplam) -> SalesEntry) -> [SalesEntry] {
            d.keys.sorted { ($0.ay, $0.urun) < ($1.ay, $1.urun) }.map { yap($0, d[$0]!) }
        }
        let satislar = satirlar(toplam) { a, t in
            let r = iadeToplam[a]
            return SalesEntry(month: a.ay, channelId: kanalId, productId: a.urun, qty: t.adet,
                              grossSales: t.tutar, discount: min(t.indirim, t.tutar),
                              returnsAmount: r?.tutar ?? 0, returnsQty: r?.adet ?? 0,
                              vatRate: urunKdvOrani(a.urun), vatIncluded: true)
        }
        let iadeEklenecek = satirlar(sonradanIade) { a, r in
            SalesEntry(month: a.ay, channelId: kanalId, productId: a.urun, qty: 0, grossSales: 0,
                       returnsAmount: r.tutar, returnsQty: r.adet,
                       vatRate: urunKdvOrani(a.urun), vatIncluded: true)
        }
        let geriAlinacak = satirlar(geri) { a, t in
            SalesEntry(month: a.ay, channelId: kanalId, productId: a.urun, qty: t.adet,
                       grossSales: t.tutar, discount: min(t.indirim, t.tutar),
                       vatRate: urunKdvOrani(a.urun), vatIncluded: true)
        }
        var aylar: [ChannelMonth] = []
        var eklenen: [MonthKey] = []
        let buyukMu: (Double) -> Bool = { $0 >= Double(OrderPackaging.ikinciKoliUrunSayisi) }
        let degisenAylar = Set(siparisAdet.keys).union(iptalEdilen.keys).union(iadesiAlinan.keys)
        for ay in degisenAylar {
            let siparisler = siparisAdet[ay] ?? [:]
            let iptaller = iptalEdilen[ay] ?? [:]
            var cm = mevcutlar[ay] ?? ChannelMonth(month: ay, channelId: kanalId)
            let buyuk = siparisler.values.filter(buyukMu).count
            let alinmis = cm.iceAktarilanSiparisler ?? []
            if alinmis.isEmpty {
                cm.orderCount = siparisler.count
                cm.bigOrderCount = buyuk
                cm.iadesiAlinanSiparisler = nil
            } else {
                // Aynı ayın devamı: önceki aktarımın üstüne eklenir, sonradan iptal edilenler düşülür
                eklenen.append(ay)
                cm.orderCount = max((cm.orderCount ?? 0) + siparisler.count - iptaller.count, 0)
                cm.bigOrderCount = max((cm.bigOrderCount ?? 0) + buyuk - iptaller.values.filter(buyukMu).count, 0)
            }
            cm.iceAktarilanSiparisler = alinmis.filter { iptaller[$0] == nil } + siparisler.keys.sorted()
            if let yeni = iadesiAlinan[ay] {
                cm.iadesiAlinanSiparisler = Array(Set(cm.iadesiAlinanSiparisler ?? []).union(yeni)).sorted()
            }
            aylar.append(cm)
        }
        var sonuc = Sonuc(satislar: satislar, aylar: aylar.sorted { $0.month < $1.month },
                          siparisSayisi: siparisAdet.values.reduce(0) { $0 + $1.count },
                          iptalSiparis: iptal, atlananKalem: atlanan,
                          aylarListesi: degisenAylar.sorted())
        sonuc.eklenenAylar = eklenen.sorted()
        sonuc.tekrarAtlanan = tekrar.count
        sonuc.geriAlinacak = geriAlinacak
        sonuc.sonradanIptal = iptalEdilen.values.reduce(0) { $0 + $1.count }
        sonuc.iadeEklenecek = iadeEklenecek
        return sonuc
    }
}
