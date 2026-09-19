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

    public static func == (a: Self, b: Self) -> Bool { a.yil == b.yil }
    public func hash(into h: inout Hasher) { h.combine(yil) }

    // Kaynaklar:
    // - Kurumlar vergisi %25: KVK 5520 md. 32/1 (7456 sayılı Kanun md. 21), 2025 ve 2026 kazançları
    // - Yurt içi asgari kurumlar vergisi %10: KVK md. 32/C (7524 sayılı Kanun md. 36), 2025 ve sonrası;
    //   matrah ticari bilanço kârı + KKEG; ilk üç hesap dönemindeki kurumlar hariç; geçici vergide de uygulanır
    // - Gelir vergisi 2026 tarifesi: GVK md. 103, GV Genel Tebliği Seri 332 (RG 31/12/2025, 33124 5. Mük.)
    // - Geçici vergi %15 (gelir) / kurumlar oranı; 4. çeyrek: 7566 sayılı Kanun (RG 19/12/2025)
    public static let bilinen: [Int: VergiKurallari] = [
        2025: VergiKurallari(
            yil: 2025, kurumlarOrani: 25, asgariKurumlarOrani: 10, gelirGeciciOrani: 15,
            gelirTarifesi: nil, dorduncuCeyrekGecici: true),
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

/// Tahmini vergi karşılığı. "Gerçek kâr" vergi öncesidir (ticari kâr); vergi matrahı
/// ticari kâr + KKEG − istisna/indirim − geçmiş yıl zararıdır. Her zaman tahmindir: beyanname değildir.
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
    /// Tahmini vergi matrahı
    public var matrah: Kurus
    /// Yılbaşından bu yana hesaplanan vergi (stopaj ve geçici vergi düşülmeden)
    public var yilBasindanVergi: Kurus
    /// Yurt içi asgari kurumlar vergisi hesaplanan vergiyi yükseltti mi
    public var asgariUygulandi: Bool
    /// Yılbaşından bu yana pazaryerlerinin kestiği stopaj — vergiden mahsup edilir
    public var yilBasindanStopaj: Kurus
    /// Yılbaşından bu yana ayrılması gereken toplam (vergi − stopaj, eksiye düşmez)
    public var yilBasindanKarsilik: Kurus
    /// Seçili ayın payı (ay kârı zararsa 0; yıl toplamı eksiye düşmez)
    public var ayinPayi: Kurus
    /// İçinde bulunulan çeyreğin geçici vergi tahmini (önceki çeyrekler ve stopaj düşülmüş)
    public var ceyrek: Int
    public var ceyrekGeciciVergi: Kurus
    /// Önceki çeyreklerin tahmini geçici vergileri toplamı (ödendiği varsayılan; mahsup edilir)
    public var oncekiGeciciVergiler: Kurus
    /// Geçici verginin son ödeme günü (çeyreği izleyen 2. ayın 17'si); 4. çeyrekte yıllık beyan günü
    public var ceyrekSonOdeme: DateKey
    /// Yıllık beyanın son ödeme günü
    public var yillikSonOdeme: DateKey
    /// Kural bilinen bir yıla ait değilse (en yakın yılın tarifesi kullanıldı)
    public var kuralTahmini: Bool
    /// Kurumlar vergisi mükellefi mi (gelir vergisinde yıllık ödeme Mart/Temmuz iki taksittir)
    public var sirket: Bool
    /// Asgari kurumlar vergisi için kuruluş yılı girilmedi (ilk üç yıl muaftır)
    public var kurulusYiliGirilmedi: Bool

    /// Mahsup edilecek vergiler: stopaj + önceki çeyreklerin geçici vergileri
    public var mahsupEdilecek: Kurus { yilBasindanStopaj + oncekiGeciciVergiler }
    /// Tahmini kalan vergi borcu (eksiye düşmez)
    public var kalanVergiBorcu: Kurus { max(yilBasindanVergi - mahsupEdilecek, 0) }
    /// Mahsup edilemeyen fazla (iade/mahsup talebi konusu)
    public var mahsupFazlasi: Kurus { max(mahsupEdilecek - yilBasindanVergi, 0) }
    /// Yıllık beyanda ödenecek kalan: 4. çeyrek dahil bütün geçici vergilerin ödendiği varsayılır
    /// (yalnızca yılın son ayında anlamlıdır)
    public var yillikBeyandaOdenecek: Kurus {
        max(yilBasindanVergi - yilBasindanStopaj - oncekiGeciciVergiler - (ceyrek == 4 ? ceyrekGeciciVergi : 0), 0)
    }
    /// Vergi sonrası tahmini net kâr: ticari kâr − hesaplanan vergi (stopaj verginin peşin ödemesidir, ayrıca düşülmez)
    public var vergiSonrasiNetKar: Kurus { yilBasindanKar - yilBasindanVergi }
    /// Girilmemiş vergi bilgileri: sonuç bunlar 0 sayılarak tahmin edildi
    public var eksikler: [String] {
        var e: [String] = []
        if kkegEk == nil { e.append("KKEG (işaretli giderler dışında)") }
        if gecmisYilZarari == nil { e.append("geçmiş yıl zararları") }
        if istisnaIndirim == nil { e.append("istisna ve indirimler") }
        if kurulusYiliGirilmedi { e.append("şirketin kuruluş yılı (ilk 3 yıl asgari kurumlar vergisi uygulanmaz)") }
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

    /// Verilen vergi öncesi kâr ve ayarlamalarla yıllık vergi (kuruş) ve asgari vergi uygulandı mı.
    /// `kkeg`: matraha eklenen; `indirim`: istisna/indirim + geçmiş yıl zararı.
    func vergiTutari(kar: Kurus, kkeg: Kurus, istisna: Kurus, gecmisZarar: Kurus, yil: Int)
    -> (vergi: Kurus, matrah: Kurus, asgari: Bool)? {
        guard let kaynak = vergiKaynagi() else { return nil }
        let brutKazanc = max(kar + kkeg, 0)
        let matrah = max(kar + kkeg - istisna - gecmisZarar, 0)
        switch kaynak {
        case let .elleOran(o):
            return (Money.roundHalfAwayFromZero(Double(matrah) * o / 100), matrah, false)
        case let .kanun(sirket):
            let k = VergiKurallari.kural(yil).kural
            if sirket {
                let normal = Money.roundHalfAwayFromZero(Double(matrah) * k.kurumlarOrani / 100)
                if let a = k.asgariKurumlarOrani {
                    // Asgari vergi: indirim ve istisnalar düşülmeden önceki kazanç (ticari kâr + KKEG) üzerinden.
                    // Geçmiş yıl zararları düşülür (Danıştay 3. D. kararıyla; konu kesinleşmedi).
                    // Kuruluşun ilk üç hesap döneminde uygulanmaz (KVK 32/C-5).
                    if let kurulus = state.settings.ek.kurulusYili, yil <= kurulus + 2 { return (normal, matrah, false) }
                    let asgari = Money.roundHalfAwayFromZero(Double(max(brutKazanc - gecmisZarar, 0)) * a / 100)
                    if asgari > normal { return (asgari, matrah, true) }
                }
                return (normal, matrah, false)
            }
            return (VergiKurallari.gelirVergisi(matrah, tarife: VergiKurallari.tarife(yil).tarife), matrah, false)
        }
    }

    /// Geçici vergi: kurumlarda aynı hesap; şahısta tarife yerine geçici vergi oranı
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

    func vergiKarsiligi(month: MonthKey, today: DateKey = Dates.today()) -> VergiKarsiligi? {
        guard let kaynak = vergiKaynagi() else { return nil }
        let yil = Dates.year(of: month)
        let ek = state.settings.ek
        let anahtar = "\(yil)"
        let kkegEk = ek.kkegEk?[anahtar], zarar = ek.gecmisYilZarari?[anahtar], istisna = ek.istisnaIndirim?[anahtar]
        let buAy = min(month, Dates.month(of: today))
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
        func geciciKalan(_ son: MonthKey) -> Kurus {
            guard son >= bas else { return 0 }
            let g = geciciVergiTutari(kar: ytd(son), kkeg: kkeg(son), istisna: istisna ?? 0, gecmisZarar: zarar ?? 0, yil: yil)
            return max(g - stopajYtd(son), 0)
        }
        let simdi = ytd(buAy)
        let hesap = vergiTutari(kar: simdi, kkeg: kkeg(buAy), istisna: istisna ?? 0, gecmisZarar: zarar ?? 0, yil: yil)
        let ayNo = Dates.monthNumber(of: buAy)
        let ceyrek = (ayNo - 1) / 3 + 1
        let ceyrekSonu = Dates.monthKey(yil, ceyrek * 3)
        let ceyrekKalan = geciciKalan(min(ceyrekSonu, Dates.month(of: today)))
        // Önceki çeyreklerde ödenmiş geçici vergi: her çeyrekte kümülatif tutara tamamlanır, zarar eden
        // çeyrekte iade edilmez. Bu yüzden ödenen toplam, önceki çeyrek sonlarının en büyüğüdür.
        let oncekiKarsilik = (1..<ceyrek).map { geciciKalan(Dates.monthKey(yil, $0 * 3)) }.max() ?? 0
        let odemeAyi = Dates.addMonths(ceyrekSonu, 2)
        // 4. çeyrek geçici vergi 2025'ten itibaren yeniden var (7566 sayılı Kanun); son gün izleyen yılın 17 Şubat'ı
        let geciciVarMi = ceyrek < 4 || VergiKurallari.kural(yil).kural.dorduncuCeyrekGecici && yil >= 2025
        let sirket: Bool = { if case .kanun(sirket: false) = kaynak { return false }; return state.settings.ek.vergiTuru != "sahis" }()
        // Kurumlar: beyan ve ödeme izleyen yılın 30 Nisan'ı. Gelir: beyan 31 Mart, ödeme Mart ve Temmuz iki taksit
        let yillikSon = sirket ? "\(yil + 1)-04-30" : "\(yil + 1)-03-31"
        let oran: Double = {
            switch kaynak {
            case let .elleOran(o): return o
            case .kanun(sirket: true): return VergiKurallari.kural(yil).kural.kurumlarOrani
            case .kanun(sirket: false):
                let m = hesap?.matrah ?? 0
                return m > 0 ? Double(hesap?.vergi ?? 0) / Double(m) * 100 : 0
            }
        }()
        return VergiKarsiligi(
            yil: yil, kaynak: kaynak, oranPct: oran,
            yilBasindanKar: simdi,
            kkegGiderler: kkegGiderleri(from: bas, to: buAy),
            kkegEk: kkegEk, gecmisYilZarari: zarar, istisnaIndirim: istisna,
            matrah: hesap?.matrah ?? 0,
            yilBasindanVergi: hesap?.vergi ?? 0,
            asgariUygulandi: hesap?.asgari ?? false,
            yilBasindanStopaj: stopajYtd(buAy),
            yilBasindanKarsilik: kalan(buAy),
            ayinPayi: max(kalan(buAy) - kalan(Dates.addMonths(buAy, -1)), 0),
            ceyrek: ceyrek,
            ceyrekGeciciVergi: geciciVarMi ? max(ceyrekKalan - oncekiKarsilik, 0) : 0,
            oncekiGeciciVergiler: oncekiKarsilik,
            ceyrekSonOdeme: geciciVarMi ? "\(odemeAyi)-17" : yillikSon,
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
            }()
        )
    }

    /// Vergi sonrası net kâr hedefine ulaşmak için gereken vergi öncesi kâr (yıllık).
    /// Vergi türü/oranı girilmemişse `nil`. Yılın KKEG, istisna ve geçmiş yıl zararı girdileri kullanılır.
    func vergiOncesiKar(netKar: Kurus, yil: Int) -> Kurus? {
        guard vergiKaynagi() != nil, netKar > 0 else { return netKar > 0 ? nil : netKar }
        let ek = state.settings.ek, k = "\(yil)"
        let kkeg = kkegGiderleri(from: Dates.monthKey(yil, 1), to: Dates.monthKey(yil, 12)) + (ek.kkegEk?[k] ?? 0)
        func net(_ p: Kurus) -> Kurus {
            p - (vergiTutari(kar: p, kkeg: kkeg, istisna: ek.istisnaIndirim?[k] ?? 0,
                             gecmisZarar: ek.gecmisYilZarari?[k] ?? 0, yil: yil)?.vergi ?? 0)
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
