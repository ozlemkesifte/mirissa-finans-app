import Foundation

/// Bir SKU'nun bir kanalda satılması şirkete ne bırakıyor.
/// Geçmiş satış verisi olmadan, yalnızca kurulum bilgilerinden hesaplanır.
public struct UnitContribution: Identifiable, Hashable, Sendable {
    public var productId: Id
    public var productName: String
    public var channelId: Id
    public var channelName: String
    /// Müşterinin ödediği fiyat (KDV dahil)
    public var price: Kurus
    /// KDV hariç satış geliri
    public var netRevenue: Kurus
    /// Komisyon + kargo + hizmet + diğer kesintiler (KDV hariç), tek ürünlük bir sipariş için
    public var channelFees: Kurus
    /// `channelFees` içindeki sipariş başına sabit kısım (kargo, hizmet bedeli, sipariş başı ek kesinti).
    /// Siparişte kaç ürün olursa olsun bir kez kesilir.
    public var perOrderFees: Kurus = 0
    public var productCost: Kurus
    /// Ürün başına ambalaj (patpat, kutu, dolgu…) — koli hariç
    public var packagingCost: Kurus
    /// Bir kolinin (sipariş başı malzemelerin) maliyeti
    public var orderPackagingCost: Kurus = 0
    /// Aylık girilen ve geçmiş aylardan tahmin edilen kesintiler
    public var estimatedFees: [String] = []
    /// Aylık girilecek denip hiç tutar girilmediği için hesaba katılamayanlar
    public var missingFees: [String] = []

    public var id: String { "\(channelId)#\(productId)" }

    /// Tek ürünlük bir siparişin şirkete bıraktığı tutar (1 koli)
    public var contribution: Kurus {
        netRevenue - channelFees - productCost - packagingCost - orderPackagingCost
    }

    /// Siparişteki her ürünün bıraktığı tutar, sipariş başı kesintiler ve koli hariç
    public var perUnitBeforeOrderFees: Kurus { contribution + perOrderFees + orderPackagingCost }

    public var marginPct: Double {
        netRevenue > 0 ? Double(contribution) / Double(netRevenue) * 100 : 0
    }
}

/// Hedef hesaplanamıyorsa neyin eksik olduğu. "0 kargo" yerine bu gösterilir.
public struct MissingSetupInfo: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, Hashable {
        case fiyat
        case urunMaliyeti
        case kanalKesintisi
        case sabitGider
        case dagilim
        case kanalUrunleri
    }

    public var kind: Kind
    public var title: String
    public var productId: Id?
    public var channelId: Id?

    public var id: String { "\(kind.rawValue)-\(productId ?? "-")-\(channelId ?? "-")-\(title)" }

    public init(_ kind: Kind, _ title: String, productId: Id? = nil, channelId: Id? = nil) {
        self.kind = kind
        self.title = title
        self.productId = productId
        self.channelId = channelId
    }
}

public extension Engine {

    /// Hedef hesabında hangi günün fiyat ve oranları kullanılacak.
    /// Geçmiş bir ay için o ayın sonu; bu ay ve sonrası için bugün.
    /// (Geçmiş ayın hedefi bugünkü fiyatla hesaplanırsa rapor sonradan değişirdi.)
    func hedefGunu(month: MonthKey, today: DateKey = Dates.today()) -> DateKey {
        month < Dates.month(of: today)
            ? Dates.monthEnd(month)
            : max(today, Dates.monthStart(month))
    }

    // MARK: - Satış başına katkı

    /// Bir SKU'nun bir kanaldaki bir satışının bıraktığı tutar.
    /// Fiyat girilmemişse `nil` döner — sıfır varsayılmaz.
    func unitContribution(productId: Id, channelId: Id,
                          on date: DateKey = Dates.today()) -> UnitContribution? {
        guard let p = productsById[productId], !p.archived,
              let ch = state.channel(channelId), !ch.archived,
              let fiyat = p.price(for: channelId, on: date), fiyat > 0 else { return nil }

        // Pazaryeri fiyatı müşterinin ödediği tutardır: KDV dahildir.
        // Oran, bu ürünün o kanaldaki son satışından alınır (ör. %10 KDV'li ürün);
        // hiç satış yoksa ayarlardaki varsayılan kullanılır.
        let oran = satisKdvOrani(productId: productId, channelId: channelId, on: date)
        let net = Vat.net(fiyat, rate: oran, included: true)

        let kk = kanalKesintisi(ch, siparisDegeri: fiyat, on: date, satisKdv: oran)
        let k = kk.0
        let b = cost(of: productId, asOf: date)
        return UnitContribution(
            productId: productId, productName: p.name,
            channelId: channelId, channelName: ch.name,
            price: fiyat, netRevenue: net,
            channelFees: k.toplam, perOrderFees: k.siparisBasi,
            productCost: b.intrinsic, packagingCost: b.packaging,
            orderPackagingCost: b.orderPackaging,
            estimatedFees: kk.tahmin, missingFees: kk.eksik
        )
    }

    /// Bir siparişin kanal kesintileri (KDV hariç).
    /// Yüzdeler KDV dahil sipariş değeri üzerinden, kargo ve hizmet bedeli sipariş başına bir kez.
    func siparisKesintisi(_ ch: Channel, siparisDegeri: Kurus,
                          on date: DateKey) -> (toplam: Kurus, siparisBasi: Kurus) {
        kanalKesintisi(ch, siparisDegeri: siparisDegeri, on: date).0
    }

    /// Sipariş kesintisi + "aylık gireceğim" denenlerin tahmini ve eksikleri
    func kanalKesintisi(_ ch: Channel, siparisDegeri: Kurus, on date: DateKey,
                        satisKdv: VatRate? = nil)
    -> ((toplam: Kurus, siparisBasi: Kurus), tahmin: [String], eksik: [String]) {
        let r = ch.rates(on: date)
        let ek = elleAylikTahmin(ch, on: date)
        // Tahmin edilen alan ayardaki aynı alanın yerine geçer (ayın gerçek tutarı gibi)
        let komisyonOrani: Double
        if let t = ek.komisyonYuzde {
            komisyonOrani = t
        } else {
            // Komisyon KDV hariç fiyattan alınıyorsa taban, motordaki gibi
            // KDV hariç satış (kesinti tutarları KDV dahil giriliyorsa üstüne kesinti KDV'si)
            let carpan = komisyonTabanCarpani(ch, on: date, satisKdv: satisKdv
                ?? (state.settings.vatEnabled ? state.settings.defaultVatRate : .yok))
            komisyonOrani = r.commissionPct * carpan + r.paymentPct
        }
        let diger = ek.digerYuzde ?? r.otherDeductionPct
        var yuzde = Double(siparisDegeri) * (komisyonOrani + diger) / 100
        var sabit = (ek.kargoSiparisBasi ?? Double(r.shippingPerOrder))
            + (ek.hizmetSiparisBasi ?? Double(r.serviceFeePerOrder))
        for f in r.extras where !f.unknown && !ek.degistirir(AylikKesinti.alan(f)) {
            switch f.basis {
            case .yuzde: yuzde += Double(siparisDegeri) * f.value / 100
            case .siparisBasi: sabit += f.value
            case .aylikSabit, .elleAylik: break   // sipariş başına değil
            }
        }
        func net(_ v: Double) -> Kurus {
            let k = ch.kesintiKdv(on: date)
            return Vat.net(Money.roundHalfAwayFromZero(v), rate: k.oran, included: k.dahil)
        }
        return ((net(yuzde + sabit), net(sabit)), ek.tahmin, ek.eksik)
    }

    /// Bir ürünün satış KDV oranı.
    /// Bu ay ve sonrası: ürüne özel oran; yoksa o kanaldaki son satışının oranı; o da yoksa varsayılan.
    /// Geçmiş ay: o aya kadarki son gerçek satışın oranı önce gelir — ürünün oranı bugün
    /// değiştirilirse geçmiş ayların hedefi değişmesin.
    func satisKdvOrani(productId: Id, channelId: Id, on date: DateKey,
                       today: DateKey = Dates.today()) -> VatRate {
        let ay = Dates.month(of: date)
        let sonSatis = state.sales
            .filter { $0.productId == productId && $0.channelId == channelId && $0.month <= ay }
            .max { $0.month < $1.month }
        let urunOrani = state.settings.vatEnabled ? productsById[productId]?.kdvOrani : nil
        let gecmis = ay < Dates.month(of: today)
        if gecmis, let o = sonSatis?.vatRate { return o }
        if let o = urunOrani { return o }
        return sonSatis?.vatRate
            ?? (state.settings.vatEnabled ? state.settings.defaultVatRate : .yok)
    }

    /// KDV dahil sipariş değerinin kaç katı komisyon tabanıdır.
    /// Varsayılan 1; "komisyon KDV hariç fiyattan" seçiliyse (1 + kesinti KDV'si) / (1 + satış KDV'si).
    func komisyonTabanCarpani(_ ch: Channel, on date: DateKey, satisKdv: VatRate) -> Double {
        guard ch.komisyonKdvHaric(on: date) else { return 1 }
        let satis = 1 + Double(satisKdv.rawValue) / 100
        let k = ch.kesintiKdv(on: date)
        let kesinti = k.dahil ? 1 + Double(k.oran.rawValue) / 100 : 1
        return kesinti / satis
    }

    /// Bu kanalda bir siparişte ortalama kaç ürün çıkıyor.
    /// Yalnızca sipariş sayısı gerçekten girilmiş aylardan hesaplanır; yoksa `nil`
    /// (adetten tahmin edilen sipariş sayısı zaten "1 sipariş = 1 ürün" demektir).
    func unitsPerOrder(channelId: Id, month: MonthKey) -> Double? {
        let aylar = (1...12).map { Dates.addMonths(month, -$0) } + [month]
        for ay in aylar {
            guard let c = companyMonth(ay).channels.first(where: { $0.channelId == channelId }),
                  !c.ordersIsEstimate, c.orders > 0, c.units > 0 else { continue }
            return max(c.units / Double(c.orders), 1)
        }
        return nil
    }

    /// Siparişte ortalama U ürün varsa o siparişin değeri ve bıraktığı tutar.
    /// Kargo ve hizmet bedeli siparişte bir kez; koli 1–2 ürüne 1, 3+ ürüne 2.
    func siparisBasina(_ u: UnitContribution, urunAdedi adet: Double, ay: MonthKey)
    -> (deger: Double, kalan: Double, ciro: Double) {
        let koli = OrderPackaging.koliPerSiparis(state, channelId: u.channelId, month: ay,
                                                 urunAdedi: adet)
        return (Double(u.price) * adet,
                Double(u.perUnitBeforeOrderFees) * adet - Double(u.perOrderFees)
                    - Double(u.orderPackagingCost) * koli,
                Double(u.netRevenue) * adet)
    }

    /// Satış karışımına göre ortalama bir sipariş.
    /// Ağırlıklar ürün adedi payıdır; her kanalın sipariş başına ürün adedi ve
    /// sipariş başı kesintisi ayrı hesaba katılır.
    func karisikSiparis(month: MonthKey, today: DateKey = Dates.today())
    -> (deger: Double, kalan: Double, ciro: Double, adet: Double, gecmisten: Bool,
        kalemler: [UnitContribution], digerDegisken: Double)? {
        let gun = hedefGunu(month: month, today: today)
        let (agirliklar, gecmisten, temelAy) = targetMix(month: month)
        guard !agirliklar.isEmpty else { return nil }

        var deger = 0.0, kalanUrun = 0.0, ciro = 0.0, adetPay = 0.0
        var kanalAdet: [Id: Double] = [:]
        var kanalSiparisKesintisi: [Id: Kurus] = [:]
        var kanalKoliMaliyeti: [Id: Double] = [:]
        var kalemler: [UnitContribution] = []
        for a in agirliklar {
            guard let u = unitContribution(productId: a.productId,
                                           channelId: a.channelId, on: gun) else { continue }
            // Geçmiş aydan geliyorsa gerçekte satılan fiyat esas alınır:
            // indirim ve iadeler liste fiyatını olduğundan iyi gösterir.
            let oran = temelAy.map {
                gerceklesmeOrani(channelId: a.channelId, productId: a.productId, month: $0)
            } ?? 1
            // Yüzdeye bağlı kesintiler fiyatla birlikte küçülür, sipariş başı olanlar küçülmez
            let yuzdeKesinti = Double(u.channelFees - u.perOrderFees) * oran
            let birimKalan = Double(u.netRevenue) * oran - yuzdeKesinti
                - Double(u.productCost) - Double(u.packagingCost)
            deger += Double(u.price) * oran * a.pay
            kalanUrun += birimKalan * a.pay
            ciro += Double(u.netRevenue) * oran * a.pay
            adetPay += a.pay
            kanalAdet[a.channelId, default: 0] += a.pay
            kanalSiparisKesintisi[a.channelId] = u.perOrderFees
            kanalKoliMaliyeti[a.channelId, default: 0] += Double(u.orderPackagingCost) * a.pay
            kalemler.append(u)
        }
        guard adetPay > 0 else { return nil }
        // Karışımdaki adet payının kaç siparişe denk geldiği
        var siparisPay = 0.0, siparisKesintisi = 0.0
        for (kanal, adet) in kanalAdet {
            let u = unitsPerOrder(channelId: kanal, month: month) ?? 1
            siparisPay += adet / u
            siparisKesintisi += adet / u * Double(kanalSiparisKesintisi[kanal] ?? 0)
            // Kolinin ortalama maliyeti (bu kanaldaki ürünlerin payına göre) × siparişte koli sayısı
            let koli = OrderPackaging.koliPerSiparis(state, channelId: kanal, month: month, urunAdedi: u)
            siparisKesintisi += adet / u * koli * (kanalKoliMaliyeti[kanal] ?? 0) / adet
        }
        guard siparisPay > 0 else { return nil }
        // Reklam dışı satışa bağlı giderler (influencer vb.). Başa baş hesabı bunları
        // aylık tutar olarak sabit gidere ekler; reklam hedefi sipariş başına düşer.
        // Karar çağırana bırakılır ki aynı gider iki kez sayılmasın.
        let digerDegisken = temelAy.map { digerDegiskenGiderSiparisBasi(month: $0) } ?? 0
        return (deger / siparisPay, (kalanUrun - siparisKesintisi) / siparisPay,
                ciro / siparisPay, adetPay / siparisPay, gecmisten, kalemler, digerDegisken)
    }

    /// Fiyatı tanımlı bütün SKU + kanal ikilileri
    func unitContributions(on date: DateKey = Dates.today()) -> [UnitContribution] {
        var out: [UnitContribution] = []
        for ch in state.activeChannels {
            for urunId in ch.soldProducts(in: state, on: date) {
                if let u = unitContribution(productId: urunId, channelId: ch.id, on: date) {
                    out.append(u)
                }
            }
        }
        return out.sorted { $0.contribution > $1.contribution }
    }

    // MARK: - Satış dağılımı

    /// Hedefte kullanılacak ağırlıklar: (kanal, ürün, pay).
    /// Geçmiş ay varsa gerçek dağılım, yoksa kullanıcının onayladığı yaklaşık dağılım.
    func targetMix(month: MonthKey) -> (agirliklar: [(channelId: Id, productId: Id, pay: Double)],
                                        gecmisten: Bool, temelAy: MonthKey?) {
        /// Ağırlık ürün adedidir. Eski kayıtlarda adet boş bırakılmış olabilir:
        /// o satırın adedi tutar ÷ o ayki fiyattan tahmin edilir. Fiyat da yoksa
        /// o ayın bütün satırları tutara göre tartılır — adet ile kuruş asla toplanmaz.
        func dagilim(_ ay: MonthKey) -> [(channelId: Id, productId: Id, pay: Double)]? {
            let satislar = state.sales.filter { $0.month == ay && ($0.netQty > 0 || $0.netSales > 0) }
            guard !satislar.isEmpty else { return nil }
            let gun = Dates.monthEnd(ay)
            func kdvDahil(_ e: SalesEntry) -> Double {
                let b = e.vatSplit
                return Double(max(b.net + b.vat, 0))
            }
            var adetler: [Double]? = []
            for e in satislar {
                if e.netQty > 0 { adetler?.append(e.netQty); continue }
                if let f = productsById[e.productId]?.price(for: e.channelId, on: gun), f > 0 {
                    adetler?.append(kdvDahil(e) / Double(f))
                } else {
                    adetler = nil
                    break
                }
            }
            let agirliklar = adetler ?? satislar.map(kdvDahil)
            let toplam = agirliklar.reduce(0, +)
            guard toplam > 0 else { return nil }
            return zip(satislar, agirliklar).compactMap { e, w in
                w > 0 ? (channelId: e.channelId, productId: e.productId, pay: w / toplam) : nil
            }
        }

        // 1) Son tamamlanmış aydan gerçek dağılım
        for geri in 1...12 {
            let ay = Dates.addMonths(month, -geri)
            if let d = dagilim(ay) { return (d, true, ay) }
        }
        // 2) Kullanıcının onayladığı yaklaşık dağılım.
        //    Bir SKU o kanalda satılmıyorsa dağılıma girmez.
        if let mix = state.settings.salesMix, mix.confirmed {
            let gun = Dates.monthEnd(month)
            let hepsi = mix.agirliklar(state: state)
            // Yalnızca kullanıcının açıkça "bu kanalda şunları satıyorum"
            // dediği liste süzer. Fiyatı henüz girilmemiş bir SKU dağılımdan
            // düşürülmez — düşseydi sistem onun fiyatını hiç sormazdı.
            let filtreli = hepsi.filter { a in
                guard let ch = state.channel(a.channelId) else { return false }
                guard let acikListe = ch.soldProductIds, !acikListe.isEmpty else { return true }
                return acikListe.contains(a.productId)
            }
            let toplam = filtreli.reduce(0.0) { $0 + $1.pay }
            guard toplam > 0 else { return ([], false, nil) }
            return (filtreli.map { ($0.channelId, $0.productId, $0.pay / toplam) }, false, nil)
        }
        // 3) Ayın kendi satışları girilmişse dağılımı oradan al
        if let d = dagilim(month) { return (d, true, month) }

        // 4) Sonraki aylarda satış varsa (kullanıcı ileriye kayıt girmiş olabilir)
        for ileri in 1...12 {
            let ay = Dates.addMonths(month, ileri)
            if let d = dagilim(ay) { return (d, true, ay) }
        }

        // 5) Tek bir olasılık varsa soracak bir şey yok:
        //    tek kanal ve o kanalda tek SKU satılıyorsa dağılım zaten belli.
        let gun = Dates.monthEnd(month)
        var tekIkililer: [(channelId: Id, productId: Id, pay: Double)] = []
        for ch in state.activeChannels {
            let satilan = ch.soldProducts(in: state, on: gun)
            guard !satilan.isEmpty else { tekIkililer = []; break }
            tekIkililer += satilan.map { (ch.id, $0, 0) }
        }
        if tekIkililer.count == 1 {
            return ([(tekIkililer[0].channelId, tekIkililer[0].productId, 1)], false, nil)
        }
        // Tek ürün varsa ürün dağılımı sormaya gerek yok; kanal payları da
        // tek kanalsa bellidir.
        if state.activeChannels.count == 1, state.activeProducts.count == 1 {
            return ([(state.activeChannels[0].id, state.activeProducts[0].id, 1)], false, nil)
        }
        return ([], false, nil)
    }

    /// Temel alınan ayda bu SKU gerçekte liste fiyatının yüzde kaçına satılmış.
    /// İndirim ve iadeler düşülür: hedef, gerçekte eline geçen tutara göre kurulur.
    func gerceklesmeOrani(channelId: Id, productId: Id, month: MonthKey) -> Double {
        let satirlar = state.sales.filter {
            $0.month == month && $0.channelId == channelId && $0.productId == productId
        }
        let adet = satirlar.reduce(0.0) { $0 + max($1.qty - $1.returnsQty, 0) }
        guard adet > 0,
              let fiyat = productsById[productId]?.price(for: channelId, on: Dates.monthEnd(month)),
              fiyat > 0 else { return 1 }
        let kdvDahil = satirlar.reduce(0) { toplam, e in
            let b = e.vatSplit
            return toplam + b.net + b.vat
        }
        let oran = Double(kdvDahil) / (adet * Double(fiyat))
        // Aşırı değerler veri hatasıdır; hedefi bozmasın
        return (oran > 0.2 && oran < 1.5) ? oran : 1
    }

    /// Temel ayda reklam dışı, satışa bağlı giderlerin sipariş başına düşen payı
    func digerDegiskenGiderSiparisBasi(month: MonthKey) -> Double {
        let r = companyMonth(month)
        guard r.orders > 0 else { return 0 }
        // Kanalı seçilmeden girilen satışa bağlı reklam da ortak değişken giderdedir;
        // reklam hedefi reklamı ayrıca düştüğü için burada sayılmaz (iki kez düşülmesin)
        let ortakReklam = expenseInstances(from: month, to: month)
            .filter { !$0.capitalized && $0.scope.channelId == nil
                && $0.category == .reklam && $0.behavior == .satisaBagli }
            .reduce(0) { $0 + $1.expenseAmount }
        let toplam = r.ortakGiderDegisken - ortakReklam
            + r.channels.reduce(0) { $0 + $1.otherChannelExpensesVariable }
        return Double(max(toplam, 0)) / Double(r.orders)
    }

    // MARK: - Hedef için eksikler

    /// Hedefi hesaplamak için eksik olan bilgiler. Boşsa hesap yapılabilir.
    ///
    /// Yalnızca gerçekten gereken bilgiler sorulur: kullanıcının o kanalda
    /// sattığını söylediği SKU'lar. Her ürünü her kanalda satılıyor varsaymaz,
    /// yoksa kullanıcı hiç satmadığı ürün-kanal ikilileri için fiyat sorulur.
    func missingForTarget(month: MonthKey, today: DateKey = Dates.today()) -> [MissingSetupInfo] {
        var out: [MissingSetupInfo] = []
        let gun = hedefGunu(month: month, today: today)
        let (agirliklar, _, _) = targetMix(month: month)

        if agirliklar.isEmpty {
            out.append(MissingSetupInfo(
                .dagilim, "Satışların hangi kanal ve üründen geliyor?"))
        }

        // Hangi ikililer için bilgi gerekiyor:
        //  - dağılım varsa yalnızca onun kapsadığı ikililer
        //  - yoksa her kanalın kendi sattığını söylediği SKU'lar
        var ikililer: [(Id, Id)] = agirliklar.map { ($0.channelId, $0.productId) }
        if ikililer.isEmpty {
            for ch in state.activeChannels {
                let satilan = ch.soldProducts(in: state, on: gun)
                if satilan.isEmpty {
                    out.append(MissingSetupInfo(
                        .kanalUrunleri, "\(ch.name) kanalında hangi ürünleri sattığın belli değil",
                        channelId: ch.id))
                } else {
                    ikililer += satilan.map { (ch.id, $0) }
                }
            }
        }

        var gorulen = Set<String>()
        var maliyetiSorulan = Set<Id>()
        for (kanalId, urunId) in ikililer {
            let anahtar = "\(kanalId)#\(urunId)"
            guard gorulen.insert(anahtar).inserted else { continue }
            guard let p = productsById[urunId], !p.archived,
                  let ch = state.channel(kanalId), !ch.archived else { continue }
            if p.price(for: kanalId, on: gun) == nil {
                out.append(MissingSetupInfo(.fiyat, "\(p.name) — \(ch.name) fiyatı girilmemiş",
                                            productId: urunId, channelId: kanalId))
            }
            // Setin maliyeti elle girilmez; eksikse bileşenini göster.
            for eksik in maliyetiEksikUrunler(urunId, asOf: gun)
            where maliyetiSorulan.insert(eksik).inserted {
                let ad = productsById[eksik]?.name ?? "Ürün"
                out.append(MissingSetupInfo(.urunMaliyeti, "\(ad) maliyeti girilmemiş",
                                            productId: eksik))
            }
        }

        // Kurulumda "bilmiyorum" denen kanal kesintileri
        for ch in state.activeChannels {
            for eksik in ch.rates(on: gun).eksikler {
                out.append(MissingSetupInfo(.kanalKesintisi, "\(ch.name) \(eksik) girilmemiş",
                                            channelId: ch.id))
            }
            // "Aylık gerçek tutarı gireceğim" denip hiç tutar girilmemiş kesintiler
            for eksik in elleAylikTahmin(ch, on: gun).eksik {
                out.append(MissingSetupInfo(
                    .kanalKesintisi,
                    "\(ch.name) \(eksik.lowercased(with: Locale(identifier: "tr_TR"))) tutarı hiç girilmemiş",
                    channelId: ch.id))
            }
        }

        if plannedFixedCosts(month: month) == 0 {
            out.append(MissingSetupInfo(.sabitGider, "Aylık sabit giderin girilmemiş"))
        }
        return out
    }

    /// Maliyeti girilmemiş ürünler. Set verilirse bileşenlerine iner:
    /// setin maliyeti bileşenlerden hesaplandığı için "set maliyeti" sorulmaz.
    func maliyetiEksikUrunler(_ productId: Id, asOf: DateKey, ziyaret: Set<Id> = []) -> [Id] {
        // Kendini içeren (hatalı) set tanımında sonsuz döngüye girme
        guard !ziyaret.contains(productId), ziyaret.count < 8,
              let p = productsById[productId] else { return [] }
        if p.isBundle {
            let sonraki = ziyaret.union([productId])
            let bilesenler = p.components.flatMap {
                maliyetiEksikUrunler($0.productId, asOf: asOf, ziyaret: sonraki)
            }
            // Setin kendi ek maliyeti yoksa sorun değil; bileşenlerine bak
            return bilesenler
        }
        // Ambalaj maliyeti reçeteden gelir; burada aranan ÜRÜNÜN kendi
        // üretim maliyetidir. Toplama bakmak yanıltıcı olurdu: reçetesi olan
        // bir ürünün maliyeti hiç girilmemiş olsa bile toplam sıfırdan büyük çıkar.
        let b = cost(of: productId, asOf: asOf)
        return (b.intrinsic == 0 && !b.ownFromPurchases) ? [productId] : []
    }

    // MARK: - Kurulumdan hesaplanan katkı

    /// Satış verisi olmadan, kurulum bilgilerinden sipariş başına ortalama katkı.
    /// Ağırlıklar dağılımdan gelir; fiyatı olmayan ikililer hesaba katılmaz.
    func plannedContributionPerOrder(month: MonthKey,
                                     today: DateKey = Dates.today())
    -> (katki: Double, ciro: Double, adet: Double, gecmisten: Bool)? {
        // Fiyatı olmayan ikililer düşülünce kalan paylar yeniden ölçeklenir
        guard let k = karisikSiparis(month: month, today: today) else { return nil }
        return (k.kalan, k.ciro, k.adet, k.gecmisten)
    }
}
