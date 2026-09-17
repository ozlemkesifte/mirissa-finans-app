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
    public var packagingCost: Kurus

    public var id: String { "\(channelId)#\(productId)" }

    /// Tek ürünlük bir siparişin şirkete bıraktığı tutar
    public var contribution: Kurus {
        netRevenue - channelFees - productCost - packagingCost
    }

    /// Siparişteki her ürünün bıraktığı tutar, sipariş başı kesintiler hariç
    public var perUnitBeforeOrderFees: Kurus { contribution + perOrderFees }

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

    // MARK: - Satış başına katkı

    /// Bir SKU'nun bir kanaldaki bir satışının bıraktığı tutar.
    /// Fiyat girilmemişse `nil` döner — sıfır varsayılmaz.
    func unitContribution(productId: Id, channelId: Id,
                          on date: DateKey = Dates.today()) -> UnitContribution? {
        guard let p = productsById[productId], !p.archived,
              let ch = state.channel(channelId), !ch.archived,
              let fiyat = p.price(for: channelId, on: date), fiyat > 0 else { return nil }

        // Pazaryeri fiyatı müşterinin ödediği tutardır: KDV dahildir.
        let oran = state.settings.vatEnabled ? state.settings.defaultVatRate : .yok
        let net = Vat.net(fiyat, rate: oran, included: true)

        let k = siparisKesintisi(ch, siparisDegeri: fiyat, on: date)
        let b = cost(of: productId, asOf: date)
        return UnitContribution(
            productId: productId, productName: p.name,
            channelId: channelId, channelName: ch.name,
            price: fiyat, netRevenue: net,
            channelFees: k.toplam, perOrderFees: k.siparisBasi,
            productCost: b.intrinsic, packagingCost: b.packaging
        )
    }

    /// Bir siparişin kanal kesintileri (KDV hariç).
    /// Yüzdeler KDV dahil sipariş değeri üzerinden, kargo ve hizmet bedeli sipariş başına bir kez.
    func siparisKesintisi(_ ch: Channel, siparisDegeri: Kurus,
                          on date: DateKey) -> (toplam: Kurus, siparisBasi: Kurus) {
        let r = ch.rates(on: date)
        var yuzde = Double(siparisDegeri) * (r.commissionPct + r.paymentPct + r.otherDeductionPct) / 100
        var sabit = Double(r.shippingPerOrder) + Double(r.serviceFeePerOrder)
        for f in r.extras where !f.unknown {
            switch f.basis {
            case .yuzde: yuzde += Double(siparisDegeri) * f.value / 100
            case .siparisBasi: sabit += f.value
            case .aylikSabit, .elleAylik: break   // sipariş başına değil
            }
        }
        func net(_ v: Double) -> Kurus {
            Vat.net(Money.roundHalfAwayFromZero(v), rate: ch.resolvedFeeVatRate,
                    included: ch.resolvedFeesIncludeVat)
        }
        return (net(yuzde + sabit), net(sabit))
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
    func siparisBasina(_ u: UnitContribution, urunAdedi adet: Double)
    -> (deger: Double, kalan: Double, ciro: Double) {
        (Double(u.price) * adet,
         Double(u.perUnitBeforeOrderFees) * adet - Double(u.perOrderFees),
         Double(u.netRevenue) * adet)
    }

    /// Satış karışımına göre ortalama bir sipariş.
    /// Ağırlıklar ürün adedi payıdır; her kanalın sipariş başına ürün adedi ve
    /// sipariş başı kesintisi ayrı hesaba katılır.
    func karisikSiparis(month: MonthKey, today: DateKey = Dates.today())
    -> (deger: Double, kalan: Double, ciro: Double, adet: Double, gecmisten: Bool,
        kalemler: [UnitContribution])? {
        let gun = max(today, Dates.monthStart(month))
        let (agirliklar, gecmisten) = targetMix(month: month)
        guard !agirliklar.isEmpty else { return nil }

        var deger = 0.0, kalanUrun = 0.0, ciro = 0.0, adetPay = 0.0
        var kanalAdet: [Id: Double] = [:]
        var kanalSiparisKesintisi: [Id: Kurus] = [:]
        var kalemler: [UnitContribution] = []
        for a in agirliklar {
            guard let u = unitContribution(productId: a.productId,
                                           channelId: a.channelId, on: gun) else { continue }
            deger += Double(u.price) * a.pay
            kalanUrun += Double(u.perUnitBeforeOrderFees) * a.pay
            ciro += Double(u.netRevenue) * a.pay
            adetPay += a.pay
            kanalAdet[a.channelId, default: 0] += a.pay
            kanalSiparisKesintisi[a.channelId] = u.perOrderFees
            kalemler.append(u)
        }
        guard adetPay > 0 else { return nil }
        // Karışımdaki adet payının kaç siparişe denk geldiği
        var siparisPay = 0.0, siparisKesintisi = 0.0
        for (kanal, adet) in kanalAdet {
            let u = unitsPerOrder(channelId: kanal, month: month) ?? 1
            siparisPay += adet / u
            siparisKesintisi += adet / u * Double(kanalSiparisKesintisi[kanal] ?? 0)
        }
        guard siparisPay > 0 else { return nil }
        return (deger / siparisPay, (kalanUrun - siparisKesintisi) / siparisPay,
                ciro / siparisPay, adetPay / siparisPay, gecmisten, kalemler)
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
                                        gecmisten: Bool) {
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
            if let d = dagilim(Dates.addMonths(month, -geri)) { return (d, true) }
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
            guard toplam > 0 else { return ([], false) }
            return (filtreli.map { ($0.channelId, $0.productId, $0.pay / toplam) }, false)
        }
        // 3) Ayın kendi satışları girilmişse dağılımı oradan al
        if let d = dagilim(month) { return (d, true) }

        // 4) Sonraki aylarda satış varsa (kullanıcı ileriye kayıt girmiş olabilir)
        for ileri in 1...12 {
            if let d = dagilim(Dates.addMonths(month, ileri)) { return (d, true) }
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
            return ([(tekIkililer[0].channelId, tekIkililer[0].productId, 1)], false)
        }
        // Tek ürün varsa ürün dağılımı sormaya gerek yok; kanal payları da
        // tek kanalsa bellidir.
        if state.activeChannels.count == 1, state.activeProducts.count == 1 {
            return ([(state.activeChannels[0].id, state.activeProducts[0].id, 1)], false)
        }
        return ([], false)
    }

    // MARK: - Hedef için eksikler

    /// Hedefi hesaplamak için eksik olan bilgiler. Boşsa hesap yapılabilir.
    ///
    /// Yalnızca gerçekten gereken bilgiler sorulur: kullanıcının o kanalda
    /// sattığını söylediği SKU'lar. Her ürünü her kanalda satılıyor varsaymaz,
    /// yoksa kullanıcı hiç satmadığı ürün-kanal ikilileri için fiyat sorulur.
    func missingForTarget(month: MonthKey, today: DateKey = Dates.today()) -> [MissingSetupInfo] {
        var out: [MissingSetupInfo] = []
        let gun = max(today, Dates.monthStart(month))
        let (agirliklar, _) = targetMix(month: month)

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
        }

        if plannedFixedCosts(month: month) == 0 {
            out.append(MissingSetupInfo(.sabitGider, "Aylık sabit giderin girilmemiş"))
        }
        return out
    }

    /// Maliyeti girilmemiş ürünler. Set verilirse bileşenlerine iner:
    /// setin maliyeti bileşenlerden hesaplandığı için "set maliyeti" sorulmaz.
    func maliyetiEksikUrunler(_ productId: Id, asOf: DateKey) -> [Id] {
        guard let p = productsById[productId] else { return [] }
        if p.isBundle {
            let bilesenler = p.components.flatMap { maliyetiEksikUrunler($0.productId, asOf: asOf) }
            // Setin kendi ek maliyeti yoksa sorun değil; bileşenlerine bak
            return bilesenler
        }
        // Ambalaj maliyeti reçeteden gelir; burada aranan ÜRÜNÜN kendi
        // üretim maliyetidir. Toplama bakmak yanıltıcı olurdu: reçetesi olan
        // bir ürünün maliyeti hiç girilmemiş olsa bile toplam sıfırdan büyük çıkar.
        return cost(of: productId, asOf: asOf).intrinsic == 0 ? [productId] : []
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
