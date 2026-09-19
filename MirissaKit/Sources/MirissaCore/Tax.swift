import Foundation

// MARK: - Kanundaki oranlar

/// Vergi kuralları (yıl başına). Rakamlar kanundan/tebliğden gelir; kaynaklar her satırda yazılı.
/// Bilinmeyen bir yıl için en yakın bilinen yılın kuralı kullanılır ve sonuç "tahmini" işaretlenir.
public struct VergiKurallari: Hashable, Sendable {
    public var yil: Int
    /// Kurumlar vergisi oranı (KVK md. 32)
    public var kurumlarOrani: Double
    /// Yurt içi asgari kurumlar vergisi: indirim ve istisnalar düşülmeden önceki kurum kazancının
    /// bu oranından az olamaz (KVK md. 32/C). nil = o yıl yok
    public var asgariKurumlarOrani: Double?
    /// Gelir vergisi mükelleflerinin geçici vergi oranı (GVK mük. md. 120: tarifenin ilk dilim oranı)
    public var gelirGeciciOrani: Double
    /// Ücret dışı gelirler için gelir vergisi tarifesi (GVK md. 103): (dilim üst sınırı TL, oran %);
    /// son dilim sınırsız. nil = o yılın tarifesi uygulamada doğrulanmış olarak yok
    public var gelirTarifesi: [(ust: Double?, oran: Double)]?
    /// 4. çeyrek geçici vergi var mı (7566 sayılı Kanun: 1/1/2025'ten başlayan dönemlerden itibaren)
    public var dorduncuCeyrekGecici: Bool
    /// Vergiye uyumlu mükellef indirimi (GVK mük. 121) oranı ve o yılın kazancı için beyannamedeki üst sınırı
    /// (kuruş; nil = henüz yayımlanmadı/doğrulanmadı)
    public var uyumIndirimiOrani: Double = 5
    public var uyumIndirimiUstSiniri: Kurus? = nil

    public static func == (a: Self, b: Self) -> Bool { a.yil == b.yil }
    public func hash(into h: inout Hasher) { h.combine(yil) }

    // Kaynaklar:
    // - Kurumlar vergisi %25: KVK 5520 md. 32/1 (7456 sayılı Kanun md. 21), 2025 ve 2026 kazançları
    // - Yurt içi asgari kurumlar vergisi %10: KVK md. 32/C (7524 sayılı Kanun md. 36), 2025 ve sonrası;
    //   matrah ticari bilanço kârı + KKEG; ilk üç hesap dönemindeki kurumlar hariç; geçici vergide de uygulanır
    // - Gelir vergisi 2026 tarifesi: GVK md. 103, GV Genel Tebliği Seri 332 (RG 31/12/2025, 33124 5. Mük.)
    // - Geçici vergi %15 (gelir) / kurumlar oranı; 4. çeyrek: 7566 sayılı Kanun (RG 19/12/2025)
    // - %5 uyum indirimi üst sınırı: 2025 kazancı (2026'da verilen beyan) 12.000.000 TL — GV Genel Tebliği
    //   Seri 332 md. 3/4 (RG 31/12/2025); 2026 kazancı için henüz yayımlanmadı
    public static let bilinen: [Int: VergiKurallari] = [
        2025: VergiKurallari(
            yil: 2025, kurumlarOrani: 25, asgariKurumlarOrani: 10, gelirGeciciOrani: 15,
            gelirTarifesi: nil, dorduncuCeyrekGecici: true, uyumIndirimiUstSiniri: 12_000_000 * 100),
        2026: VergiKurallari(
            yil: 2026, kurumlarOrani: 25, asgariKurumlarOrani: 10, gelirGeciciOrani: 15,
            gelirTarifesi: [(190_000, 15), (400_000, 20), (1_000_000, 27), (5_300_000, 35), (nil, 40)],
            dorduncuCeyrekGecici: true),
    ]

    /// Yılın kuralı; yoksa en yakın bilinen yıl (`kesin` false)
    public static func kural(_ yil: Int) -> (kural: VergiKurallari, kesin: Bool) {
        if let k = bilinen[yil] { return (k, true) }
        let en = bilinen.keys.min { abs($0 - yil) < abs($1 - yil) || (abs($0 - yil) == abs($1 - yil) && $0 > $1) }!
        return (bilinen[en]!, false)
    }

    /// Yılın gelir vergisi tarifesi; o yıl doğrulanmış tarife yoksa en yakın tarifeli yıl (`kesin` false)
    public static func tarife(_ yil: Int) -> (tarife: [(ust: Double?, oran: Double)], kesin: Bool) {
        if let t = bilinen[yil]?.gelirTarifesi { return (t, true) }
        let en = bilinen.filter { $0.value.gelirTarifesi != nil }.keys
            .min { abs($0 - yil) < abs($1 - yil) || (abs($0 - yil) == abs($1 - yil) && $0 > $1) }!
        return (bilinen[en]!.gelirTarifesi!, false)
    }

    /// Gelir vergisi tarifesiyle vergi (kuruş)
    public static func gelirVergisi(_ matrah: Kurus, tarife: [(ust: Double?, oran: Double)]) -> Kurus {
        var kalan = Double(max(matrah, 0)) / 100
        var alt = 0.0, vergi = 0.0
        for d in tarife {
            let ust = d.ust ?? .infinity
            let dilim = min(kalan, ust - alt)
            guard dilim > 0 else { break }
            vergi += dilim * d.oran / 100
            kalan -= dilim
            alt = ust
        }
        return Money.roundHalfAwayFromZero(vergi * 100)
    }
}

// MARK: - Vergi hesabı

/// Bir geçici vergi dönemi: tahakkuk eden (hesaplanan), gerçekten ödenen, kalan ve vade.
/// Ödeme kaydı yoksa ödenmemiş sayılır; ödendiği varsayılmaz.
public struct GeciciVergiDonemi: Identifiable, Hashable, Sendable {
    public var yil: Int
    public var ceyrek: Int
    /// Dönem için hesaplanan geçici vergi (önceki dönemlerin hesaplanan geçici vergileri ve stopaj düşülmüş)
    public var tahakkuk: Kurus
    /// Kullanıcının girdiği gerçek ödeme
    public var odeme: VergiOdemesi?
    /// Son ödeme günü (dönemi izleyen 2. ayın 17'si)
    public var vade: DateKey
    /// Dönem bitti mi (bitmediyse tahakkuk, bugüne kadarki verilerle tahmindir)
    public var bitti: Bool

    public var id: String { "\(yil)-\(ceyrek)" }
    public var odenen: Kurus { odeme?.tutar ?? 0 }
    public var kalan: Kurus { max(tahakkuk - odenen, 0) }
}

/// %5 vergiye uyumlu mükellef indirimi (GVK mük. 121) için kullanıcının beyanı
public enum UyumIndirimiDurumu: String, Sendable {
    /// Şartları muhasebeci doğruladı: yıllık beyanda uygulanır
    case evet
    case hayir
    /// Bilinmiyor: uygulanmaz, sonuç "tahmini" yazılır
    case bilinmiyor
}

/// Tahmini vergi karşılığı. "Gerçek kâr" vergi öncesidir (ticari kâr). Her zaman tahmindir: beyanname değildir.
public struct VergiKarsiligi: Hashable, Sendable {
    public enum Kaynak: Hashable, Sendable {
        /// Kanundaki oran/tarife (şirket: kurumlar vergisi, şahıs: gelir vergisi tarifesi)
        case kanun(sirket: Bool)
        /// Kullanıcının (muhasebecinin) girdiği sabit oran
        case elleOran(Double)
    }

    public var yil: Int
    public var kaynak: Kaynak
    /// Hesap kullanıcının girdiği orandaysa oran, kanundaysa kurumlar oranı ya da şahısta ortalama oran
    public var oranPct: Double
    /// Yılbaşından seçili aya kadar vergi öncesi kâr (ticari kâr)
    public var yilBasindanKar: Kurus
    /// KKEG işaretli giderler (indirilemeyen KDV'leri dahil)
    public var kkegGiderler: Kurus
    /// Elle eklenen KKEG; nil = girilmedi
    public var kkegEk: Kurus?
    public var gecmisYilZarari: Kurus?
    public var istisnaIndirim: Kurus?
    /// Normal vergi matrahı: max(ticari kâr + KKEG − istisna/indirim − geçmiş yıl zararı, 0)
    public var matrah: Kurus
    /// Normal matrah üzerinden vergi (kurumlar %25 / gelir tarifesi / elle oran)
    public var normalVergi: Kurus
    /// Asgari kurumlar vergisi matrahı ve vergisi; uygulanmıyorsa nil
    public var asgariMatrah: Kurus?
    public var asgariVergi: Kurus?
    /// Asgari vergi neden uygulanmıyor (şahıs, elle oran, ilk üç yıl…); uygulanıyorsa nil
    public var asgariYokNedeni: String?
    /// Uygulanacak vergi: max(normal, asgari) — stopaj, geçici vergi ve indirim düşülmeden
    public var yilBasindanVergi: Kurus
    /// Yurt içi asgari kurumlar vergisi hesaplanan vergiyi yükseltti mi
    public var asgariUygulandi: Bool
    /// %5 uyum indirimi: kullanıcının beyanı ve tutar (yalnız "evet"te 0'dan büyük)
    public var uyumDurumu: UyumIndirimiDurumu
    public var uyumIndirimi: Kurus
    /// Yılbaşından bu yana pazaryerlerinin kestiği stopaj — vergiden mahsup edilir
    public var yilBasindanStopaj: Kurus
    /// Yılbaşından bu yana ayrılması gereken toplam (vergi − stopaj, eksiye düşmez)
    public var yilBasindanKarsilik: Kurus
    /// Seçili ayın payı (ay kârı zararsa 0; yıl toplamı eksiye düşmez)
    public var ayinPayi: Kurus
    /// İçinde bulunulan çeyreğin geçici vergi tahmini (önceki dönemlerin hesaplanan geçici vergileri ve stopaj düşülmüş)
    public var ceyrek: Int
    public var ceyrekGeciciVergi: Kurus
    /// Önceki çeyreklerde hesaplanan (tahakkuk eden) geçici vergiler: yalnız bu çeyreğin hesabında düşülür
    public var oncekiGeciciTahakkuk: Kurus
    /// Yılın bütün geçici vergi dönemleri (bugüne kadar)
    public var geciciDonemler: [GeciciVergiDonemi]
    /// Geçici verginin son ödeme günü (çeyreği izleyen 2. ayın 17'si)
    public var ceyrekSonOdeme: DateKey
    /// Yıllık beyanın son ödeme günü
    public var yillikSonOdeme: DateKey
    /// Kural bilinen bir yıla ait değilse (en yakın yılın tarifesi kullanıldı)
    public var kuralTahmini: Bool
    /// Kurumlar vergisi mükellefi mi (gelir vergisinde yıllık ödeme Mart/Temmuz iki taksittir)
    public var sirket: Bool
    /// Asgari kurumlar vergisi için kuruluş yılı girilmedi (ilk üç yıl muaftır)
    public var kurulusYiliGirilmedi: Bool
    /// Yıllık beyan için girilen gerçek ödeme (yoksa ödenmemiş)
    public var yillikOdeme: VergiOdemesi? = nil
    /// %5 indirimin o yılki üst sınırı yayımlanmadı (sınır uygulanmadı)
    public var uyumUstSiniriBilinmiyor: Bool = false
    /// Geçmiş yıl zararı asgari matrahtan düşüldü (muhasebeci uygulaması seçildi)
    public var asgariZararIndirildi: Bool = false

    /// Gerçekten ödenmiş geçici vergiler (yalnız ödeme kaydı olanlar)
    public var odenmisGeciciVergiler: Kurus { geciciDonemler.reduce(0) { $0 + $1.odenen } }
    /// Tevkifat ve ödenmiş geçici vergi düşüldükten sonra ödenmesi gereken (uyum indiriminden önce)
    public var odenmesiGereken: Kurus { max(yilBasindanVergi - mahsupEdilecek, 0) }
    /// Uyum indiriminin bu vergiden düşülebilen kısmı (GVK mük. 121: ödenmesi gereken vergiden indirilir)
    public var kullanilanUyumIndirimi: Kurus { min(uyumIndirimi, odenmesiGereken) }
    /// Düşülemeyen uyum indirimi: beyan tarihini izleyen bir yıl içinde diğer vergilere mahsup edilebilir,
    /// iade edilmez. Kullanılıp kullanılmayacağı bilinmediği için net kâra eklenmez.
    public var uyumIndirimiDevreden: Kurus { uyumIndirimi - kullanilanUyumIndirimi }
    /// Vadesi geçmiş, ödenmemiş geçici vergi
    public func odenmemisGecici(bugun: DateKey) -> Kurus {
        geciciDonemler.filter { $0.vade < bugun }.reduce(0) { $0 + $1.kalan }
    }
    /// Vergi yükü: uygulanacak vergi − kullanılan uyum indirimi
    public var odenecekVergi: Kurus { yilBasindanVergi - kullanilanUyumIndirimi }
    /// Mahsup edilecek vergiler: stopaj + gerçekten ödenmiş geçici vergiler
    public var mahsupEdilecek: Kurus { yilBasindanStopaj + odenmisGeciciVergiler }
    /// Tahmini kalan vergi borcu: uygulanacak − tevkifat − ödenmiş geçici vergi − uyum indirimi (eksiye düşmez)
    public var kalanVergiBorcu: Kurus { odenmesiGereken - kullanilanUyumIndirimi }
    /// Mahsup edilemeyen tevkifat/geçici vergi fazlası (iade/mahsup talebi konusu)
    public var mahsupFazlasi: Kurus { max(mahsupEdilecek - yilBasindanVergi, 0) }
    /// Yıllık beyanda ödenecek kalan: yalnız gerçekten ödenmiş geçici vergiler düşülür
    public var yillikBeyandaOdenecek: Kurus { kalanVergiBorcu }
    /// Yıllık beyan için girilen gerçek ödeme ve sonrası kalan
    public var yillikOdenen: Kurus { yillikOdeme?.tutar ?? 0 }
    public var yillikKalan: Kurus { max(kalanVergiBorcu - yillikOdenen, 0) }
    /// Nakit planı için: yıllık beyanda ödenecek kalan, ödenmemiş geçici vergi kalanları da ayrıca
    /// "planlanan ödeme" olarak gösterildiği için onlar düşülerek (aynı tutar iki kez planlanmaz)
    public var planlananYillikOdeme: Kurus {
        max(yillikKalan - geciciDonemler.reduce(0) { $0 + $1.kalan }, 0)
    }
    /// Vergi sonrası tahmini net kâr: ticari kâr − (uygulanacak vergi − kullanılan uyum indirimi)
    public var vergiSonrasiNetKar: Kurus { yilBasindanKar - odenecekVergi }
    /// Girilmemiş / doğrulanmamış vergi bilgileri: sonuç tahminidir
    public var eksikler: [String] {
        var e: [String] = []
        if kkegEk == nil { e.append("KKEG (işaretli giderler dışında)") }
        if gecmisYilZarari == nil { e.append("geçmiş yıl zararları") }
        if istisnaIndirim == nil { e.append("istisna ve indirimler") }
        if kurulusYiliGirilmedi { e.append("şirketin kuruluş yılı (ilk 3 yıl asgari kurumlar vergisi uygulanmaz)") }
        if uyumDurumu == .bilinmiyor { e.append("%5 uyum indirimi şartları (hesaba katılmadı)") }
        if uyumDurumu == .evet && uyumUstSiniriBilinmiyor {
            e.append("\(yil) kazancı için %5 indirim üst sınırı (henüz yayımlanmadı; sınır uygulanmadı)")
        }
        if (istisnaIndirim ?? 0) > 0 && asgariMatrah != nil {
            e.append("istisnaların asgari matrahtan düşülüp düşülmeyeceği (KVK 32/C-2 listesi; burada düşülmedi)")
        }
        return e
    }
}

public extension Engine {

    /// Vergi türü ve (varsa) elle girilen oran. İkisi de yoksa `nil`: vergi tahmini yapılmaz.
    private func vergiKaynagi() -> VergiKarsiligi.Kaynak? {
        let ek = state.settings.ek
        // Oran ekranda %60 ile sınırlı; elle düzenlenmiş yedekte de aşılmasın (ters hesap sonsuza gitmesin)
        if let o = ek.vergiOrani, o > 0 { return .elleOran(min(o, 60)) }
        switch ek.vergiTuru {
        case "sirket": return .kanun(sirket: true)
        case "sahis": return .kanun(sirket: false)
        default: return nil
        }
    }

    /// Vergi hesabının adımları
    struct VergiAdimlari {
        var normalMatrah: Kurus
        var normalVergi: Kurus
        var asgariMatrah: Kurus?
        var asgariVergi: Kurus?
        var asgariYokNedeni: String?
        var uygulanacak: Kurus { max(normalVergi, asgariVergi ?? 0) }
        var asgariUygulandi: Bool { (asgariVergi ?? 0) > normalVergi }
    }

    /// Yıllık (ya da yılbaşından bugüne) vergi adımları.
    /// Normal matrah = max(ticari kâr + KKEG − istisna/indirim − geçmiş yıl zararı, 0).
    /// Asgari matrah (KVK 32/C) = max(ticari kâr + KKEG, 0): indirim, istisna ve geçmiş yıl zararı düşülmez.
    func vergiAdimlari(kar: Kurus, kkeg: Kurus, istisna: Kurus, gecmisZarar: Kurus, yil: Int) -> VergiAdimlari? {
        guard let kaynak = vergiKaynagi() else { return nil }
        let matrah = max(kar + kkeg - istisna - gecmisZarar, 0)
        switch kaynak {
        case let .elleOran(o):
            return VergiAdimlari(normalMatrah: matrah, normalVergi: Money.roundHalfAwayFromZero(Double(matrah) * o / 100),
                                 asgariYokNedeni: "Senin girdiğin oran kullanılıyor; asgari kurumlar vergisi hesaplanmadı")
        case .kanun(sirket: false):
            return VergiAdimlari(normalMatrah: matrah,
                                 normalVergi: VergiKurallari.gelirVergisi(matrah, tarife: VergiKurallari.tarife(yil).tarife),
                                 asgariYokNedeni: "Gelir vergisi mükellefinde asgari kurumlar vergisi yoktur")
        case .kanun(sirket: true):
            let k = VergiKurallari.kural(yil).kural
            let normal = Money.roundHalfAwayFromZero(Double(matrah) * k.kurumlarOrani / 100)
            guard let a = k.asgariKurumlarOrani else {
                return VergiAdimlari(normalMatrah: matrah, normalVergi: normal, asgariYokNedeni: "Bu yıl asgari kurumlar vergisi yok")
            }
            if let kurulus = state.settings.ek.kurulusYili, yil <= kurulus + 2 {
                return VergiAdimlari(normalMatrah: matrah, normalVergi: normal,
                                     asgariYokNedeni: "Kuruluşun ilk üç hesap dönemi (KVK 32/C-5)")
            }
            // KVK 32/C-6: ticari bilanço kârı + KKEG; sıfırdan büyük değilse asgari vergi yok.
            // 32/C-2 listesindeki istisna/indirimler (Ar-Ge, teknokent…) bu uygulamada ayrıca girilmediği için düşülmez.
            // Geçmiş yıl zararı yalnız muhasebeci uygulaması seçildiyse düşülür (Danıştay 3. D. E.2024/5700 K.2025/4831).
            let a0 = kar + kkeg
            let zararDus = state.settings.ek.asgariZararIndirimi == true ? min(max(gecmisZarar, 0), max(a0, 0)) : 0
            let asgariMatrah = max(a0 - zararDus, 0)
            return VergiAdimlari(normalMatrah: matrah, normalVergi: normal, asgariMatrah: asgariMatrah,
                                 asgariVergi: Money.roundHalfAwayFromZero(Double(asgariMatrah) * a / 100))
        }
    }

    /// Geriye dönük uyumluluk: uygulanacak vergi, normal matrah, asgari uygulandı mı
    func vergiTutari(kar: Kurus, kkeg: Kurus, istisna: Kurus, gecmisZarar: Kurus, yil: Int)
    -> (vergi: Kurus, matrah: Kurus, asgari: Bool)? {
        vergiAdimlari(kar: kar, kkeg: kkeg, istisna: istisna, gecmisZarar: gecmisZarar, yil: yil)
            .map { ($0.uygulanacak, $0.normalMatrah, $0.asgariUygulandi) }
    }

    /// Geçici vergi: kurumlarda yıllık hesapla aynı (asgari dahil); şahısta tarife yerine geçici vergi oranı
    private func geciciVergiTutari(kar: Kurus, kkeg: Kurus, istisna: Kurus, gecmisZarar: Kurus, yil: Int) -> Kurus {
        if case .kanun(sirket: false)? = vergiKaynagi() {
            let matrah = max(kar + kkeg - istisna - gecmisZarar, 0)
            return Money.roundHalfAwayFromZero(Double(matrah) * VergiKurallari.kural(yil).kural.gelirGeciciOrani / 100)
        }
        return vergiTutari(kar: kar, kkeg: kkeg, istisna: istisna, gecmisZarar: gecmisZarar, yil: yil)?.vergi ?? 0
    }

    /// KKEG işaretli giderlerin (kâra giren tutar) toplamı
    func kkegGiderleri(from: MonthKey, to: MonthKey) -> Kurus {
        guard from <= to else { return 0 }
        return expenseInstances(from: from, to: to).filter(\.kkeg).reduce(0) { $0 + $1.expenseAmount }
    }

    /// %5 uyum indirimi tutarı (GVK mük. 121): yıllık beyanda hesaplanan verginin %5'i, yıllık üst sınırla.
    /// Asgari kurumlar vergisiyle ilişkisi `VergiKurallari.uyumAsgariAltinaInemez` ile belirlenir.
    /// İndirim, asgari kurumlar vergisiyle bulunan (üste çıkılmış) vergiye de uygulanır (KV Genel Tebliği 23
    /// §32.5.4; GİB Asgari KV Rehberi 2026 §2.10). O yılın üst sınırı yayımlanmadıysa sınır uygulanmaz ve bu söylenir.
    func uyumIndirimiTutari(adim: VergiAdimlari?, yil: Int) -> Kurus {
        guard let adim else { return 0 }
        let k = VergiKurallari.kural(yil).kural
        var indirim = Money.roundHalfAwayFromZero(Double(adim.uygulanacak) * k.uyumIndirimiOrani / 100)
        if let ust = k.uyumIndirimiUstSiniri { indirim = min(indirim, ust) }
        return max(indirim, 0)
    }

    /// %5 uyum indirimi beyanı
    func uyumIndirimiDurumu() -> UyumIndirimiDurumu {
        switch state.settings.ek.uyumIndirimi {
        case "evet": return .evet
        case "hayir": return .hayir
        default: return .bilinmiyor
        }
    }

    func vergiKarsiligi(month: MonthKey, today: DateKey = Dates.today()) -> VergiKarsiligi? {
        guard let kaynak = vergiKaynagi() else { return nil }
        let yil = Dates.year(of: month)
        let ek = state.settings.ek
        let anahtar = "\(yil)"
        let kkegEk = ek.kkegEk?[anahtar], zarar = ek.gecmisYilZarari?[anahtar], istisna = ek.istisnaIndirim?[anahtar]
        let bugunAy = Dates.month(of: today)
        let buAy = min(month, bugunAy)
        let bas = Dates.monthKey(yil, 1)
        func ytd(_ son: MonthKey) -> Kurus { son >= bas ? companyTotals(from: bas, to: son).gercekKar : 0 }
        func stopajYtd(_ son: MonthKey) -> Kurus { son >= bas ? companyTotals(from: bas, to: son).stopaj : 0 }
        func kkeg(_ son: MonthKey) -> Kurus { kkegGiderleri(from: bas, to: son) + (kkegEk ?? 0) }
        func vergi(_ son: MonthKey) -> Kurus {
            guard son >= bas else { return 0 }
            return vergiTutari(kar: ytd(son), kkeg: kkeg(son), istisna: istisna ?? 0, gecmisZarar: zarar ?? 0, yil: yil)?.vergi ?? 0
        }
        // Stopaj peşin ödenmiş vergidir: ayrılacak tutardan düşülür
        func kalan(_ son: MonthKey) -> Kurus { max(vergi(son) - stopajYtd(son), 0) }
        func geciciKumulatif(_ son: MonthKey) -> Kurus {
            guard son >= bas else { return 0 }
            let g = geciciVergiTutari(kar: ytd(son), kkeg: kkeg(son), istisna: istisna ?? 0, gecmisZarar: zarar ?? 0, yil: yil)
            return max(g - stopajYtd(son), 0)
        }
        let simdi = ytd(buAy)
        let adim = vergiAdimlari(kar: simdi, kkeg: kkeg(buAy), istisna: istisna ?? 0, gecmisZarar: zarar ?? 0, yil: yil)
        let ayNo = Dates.monthNumber(of: buAy)
        let ceyrek = (ayNo - 1) / 3 + 1
        let ceyrekSonu = Dates.monthKey(yil, ceyrek * 3)
        // 4. çeyrek geçici vergi 2025'ten itibaren yeniden var (7566 sayılı Kanun); son gün izleyen yılın 17 Şubat'ı
        let dorduncuVar = VergiKurallari.kural(yil).kural.dorduncuCeyrekGecici && yil >= 2025
        // Geçici vergi dönemleri: her dönemin tahakkuku, önceki dönemlerin HESAPLANAN geçici vergileri düşülerek
        // bulunur (beyannamedeki mahsup). Ödenip ödenmediği yalnız yıllık mahsubu ve nakdi etkiler.
        var donemler: [GeciciVergiDonemi] = []
        var kumulatif: Kurus = 0
        for q in 1...4 where q < 4 || dorduncuVar {
            let qBas = Dates.monthKey(yil, q * 3 - 2), qSon = Dates.monthKey(yil, q * 3)
            guard qBas <= bugunAy else { break }
            let k = max(geciciKumulatif(min(qSon, bugunAy)), kumulatif)
            donemler.append(GeciciVergiDonemi(yil: yil, ceyrek: q, tahakkuk: k - kumulatif,
                                              odeme: ek.geciciVergiOdemeleri?["\(yil)-\(q)"],
                                              vade: "\(Dates.addMonths(qSon, 2))-17", bitti: qSon < bugunAy))
            kumulatif = k
        }
        let buDonem = donemler.first { $0.ceyrek == ceyrek }
        let oncekiTahakkuk = donemler.filter { $0.ceyrek < ceyrek }.reduce(0) { $0 + $1.tahakkuk }
        let geciciVarMi = ceyrek < 4 || dorduncuVar
        let sirket: Bool = { if case .kanun(sirket: false) = kaynak { return false }; return state.settings.ek.vergiTuru != "sahis" }()
        // Kurumlar: beyan ve ödeme izleyen yılın 30 Nisan'ı. Gelir: beyan 31 Mart, ödeme Mart ve Temmuz iki taksit
        let yillikSon = sirket ? "\(yil + 1)-04-30" : "\(yil + 1)-03-31"
        let uygulanacak = adim?.uygulanacak ?? 0
        // %5 uyum indirimi: yalnız muhasebecinin doğruladığı "evet"te, yıllık beyanda hesaplanan vergiden
        let uyum = uyumIndirimiDurumu()
        let uyumTutari = uyum == .evet ? uyumIndirimiTutari(adim: adim, yil: yil) : 0
        let oran: Double = {
            switch kaynak {
            case let .elleOran(o): return o
            case .kanun(sirket: true): return VergiKurallari.kural(yil).kural.kurumlarOrani
            case .kanun(sirket: false):
                let m = adim?.normalMatrah ?? 0
                return m > 0 ? Double(adim?.normalVergi ?? 0) / Double(m) * 100 : 0
            }
        }()
        return VergiKarsiligi(
            yil: yil, kaynak: kaynak, oranPct: oran,
            yilBasindanKar: simdi,
            kkegGiderler: kkegGiderleri(from: bas, to: buAy),
            kkegEk: kkegEk, gecmisYilZarari: zarar, istisnaIndirim: istisna,
            matrah: adim?.normalMatrah ?? 0,
            normalVergi: adim?.normalVergi ?? 0,
            asgariMatrah: adim?.asgariMatrah,
            asgariVergi: adim?.asgariVergi,
            asgariYokNedeni: adim?.asgariYokNedeni,
            yilBasindanVergi: uygulanacak,
            asgariUygulandi: adim?.asgariUygulandi ?? false,
            uyumDurumu: uyum,
            uyumIndirimi: uyumTutari,
            yilBasindanStopaj: stopajYtd(buAy),
            yilBasindanKarsilik: kalan(buAy),
            ayinPayi: max(kalan(buAy) - kalan(Dates.addMonths(buAy, -1)), 0),
            ceyrek: ceyrek,
            ceyrekGeciciVergi: geciciVarMi ? (buDonem?.tahakkuk ?? 0) : 0,
            oncekiGeciciTahakkuk: oncekiTahakkuk,
            geciciDonemler: donemler,
            ceyrekSonOdeme: geciciVarMi ? "\(Dates.addMonths(ceyrekSonu, 2))-17" : yillikSon,
            yillikSonOdeme: yillikSon,
            kuralTahmini: {
                switch kaynak {
                case .kanun(sirket: true): return !VergiKurallari.kural(yil).kesin
                case .kanun(sirket: false): return !VergiKurallari.tarife(yil).kesin
                case .elleOran: return false
                }
            }(),
            sirket: sirket,
            kurulusYiliGirilmedi: {
                if case .kanun(sirket: true) = kaynak { return state.settings.ek.kurulusYili == nil }
                return false
            }(),
            yillikOdeme: ek.geciciVergiOdemeleri?["\(yil)-yillik"],
            uyumUstSiniriBilinmiyor: VergiKurallari.bilinen[yil]?.uyumIndirimiUstSiniri == nil,
            asgariZararIndirildi: adim?.asgariMatrah != nil && ek.asgariZararIndirimi == true && (zarar ?? 0) > 0
        )
    }

    /// Vergi sonrası net kâr hedefine ulaşmak için gereken vergi öncesi kâr (yıllık).
    /// Vergi türü/oranı girilmemişse `nil`. Yılın KKEG, istisna ve geçmiş yıl zararı girdileri kullanılır.
    func vergiOncesiKar(netKar: Kurus, yil: Int) -> Kurus? {
        guard vergiKaynagi() != nil, netKar > 0 else { return netKar > 0 ? nil : netKar }
        let ek = state.settings.ek, k = "\(yil)"
        let kkeg = kkegGiderleri(from: Dates.monthKey(yil, 1), to: Dates.monthKey(yil, 12)) + (ek.kkegEk?[k] ?? 0)
        func net(_ p: Kurus) -> Kurus {
            let a = vergiAdimlari(kar: p, kkeg: kkeg, istisna: ek.istisnaIndirim?[k] ?? 0,
                                  gecmisZarar: ek.gecmisYilZarari?[k] ?? 0, yil: yil)
            let uyum = uyumIndirimiDurumu() == .evet ? uyumIndirimiTutari(adim: a, yil: yil) : 0
            return p - ((a?.uygulanacak ?? 0) - min(uyum, a?.uygulanacak ?? 0))
        }
        // Vergi sonrası kâr, vergi öncesi kârla birlikte artar: ikiye bölerek en küçük yeterli tutar bulunur
        var alt: Kurus = netKar, ust: Kurus = netKar * 3 + 100
        while net(ust) < netKar { ust *= 2 }
        while ust - alt > 1 {
            let orta = alt + (ust - alt) / 2
            if net(orta) >= netKar { ust = orta } else { alt = orta }
        }
        return net(alt) >= netKar ? alt : ust
    }
}
