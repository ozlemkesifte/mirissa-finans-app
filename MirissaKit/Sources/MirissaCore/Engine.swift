import Foundation

/// Tüm türetilmiş hesapları üreten motor.
///
/// Hiçbir sonuç saklanmaz; her şey `AppState`'ten yeniden hesaplanır.
/// Bir kayıt değiştiğinde yeni bir `Engine` kurulur ve bütün ekranlar
/// kendiliğinden doğru rakamı gösterir. Katman katman önbellekleme
/// sayesinde bu, tek bir karede biter.
public final class Engine {
    public let state: AppState

    public private(set) lazy var productsById: [Id: Product] =
        Dictionary(state.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    public private(set) lazy var materialsById: [Id: StockMaterial] =
        Dictionary(state.materials.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public private(set) lazy var movements: [Movement] = Movements.all(state)
    public private(set) lazy var ledger: LedgerResult = Ledger.fold(movements)

    /// Kalem başına (tarih, birim maliyet) geçmişi — geçmişe dönük maliyet için
    private lazy var costHistory: [Id: [(date: DateKey, cost: Double, qty: BaseQty)]] = {
        var out: [Id: [(DateKey, Double, BaseQty)]] = [:]
        for r in ledger.rows {
            // Katlama sırası effectiveDate'e göre: sayımlar ayın sonuna alınır.
            // Görünen tarihi kullanmak listeyi bozar ve ikili arama yanlış sonuç verir.
            out[r.item.id, default: []].append((r.movement.effectiveDate, r.unitCostAfter, r.balanceAfter))
        }
        return out
    }()

    /// Ay → kategori → satış dışında stoktan çıkan malın maliyeti (KDV hariç).
    ///
    /// Alınan mal alım anında gider yazılmaz, stoğa girer; satıldıkça ürün ve
    /// ambalaj maliyeti olarak kâra düşer. Kırılan, kaybolan, numune verilen ya da
    /// sayımda eksik çıkan malın maliyeti de kâra düşmeli — yoksa bu para hiçbir
    /// yerde gider olarak görünmez ve kâr olduğundan yüksek çıkar.
    ///  - Numune, influencer, PR → "Influencer" (pazarlama gideri)
    ///  - Kırık, hasarlı, fire, kayıp, iç kullanım, sayım farkı, diğer → "Fire, kayıp ve sayım farkı"
    ///  - Sayımda fazla çıkan mal bu gideri azaltır.
    ///  - Stok eksideyken yapılan sayım gider/gelir yazmaz: eksi stok kaydı eksik
    ///    bir alım ya da açılış stoğu demektir, gerçek bir kazanç değildir.
    private(set) lazy var stoktanGiderler: [MonthKey: [ExpenseCategory: Kurus]] = {
        var sonDeger: [Id: Kurus] = [:]
        var sonMiktar: [Id: BaseQty] = [:]
        var out: [MonthKey: [ExpenseCategory: Kurus]] = [:]
        for r in ledger.rows {
            let key = r.item.id
            // Eksi stoğu kapatan alımın fiyat farkı: stok yokken satılanların maliyet düzeltmesi
            // Maliyeti elle girilmiş ürün alımdan maliyetlenmez: onda fiyat farkı da yoktur
            if r.fiyatFarki != 0,
               r.item.kind == .material || cost(of: r.item.id, asOf: r.date).ownFromPurchases {
                let kat: ExpenseCategory = r.item.kind == .material ? .ambalaj : .urunUretimi
                out[Dates.month(of: r.date), default: [:]][kat, default: 0] += Money.roundHalfAwayFromZero(r.fiyatFarki)
            }
            let oncekiDeger = sonDeger[key] ?? 0
            let oncekiMiktar = sonMiktar[key] ?? 0
            sonDeger[key] = r.valueAfter
            sonMiktar[key] = r.balanceAfter
            guard r.kind == .duzeltme || r.kind == .sayim else { continue }
            if r.kind == .sayim, oncekiMiktar < 0 { continue }
            // Değer farkı, stok sıfırın altına inip kırpıldığında yanıltır.
            // Doğrusu: çıkan miktar × o andaki birim maliyet.
            var birim = oncekiMiktar > 0 ? Double(oncekiDeger) / oncekiMiktar : r.unitCostAfter
            // Maliyeti yalnız elle girilmiş (alımı, açılış stoğu olmayan) üründe stok değeri 0'dır;
            // fire yine de girilen maliyetle gider olmalı (satışta da o maliyet kullanılıyor)
            if birim <= 0, r.item.kind == .product {
                birim = Double(cost(of: r.item.id, asOf: r.date).intrinsic)
            }
            let tutar = Money.roundHalfAwayFromZero(-r.delta * birim)
            guard tutar != 0 else { continue }
            let kategori: ExpenseCategory
            switch r.movement.reason {
            case .numune, .influencer, .pr: kategori = .influencer
            default: kategori = .stokKaybi
            }
            out[Dates.month(of: r.date), default: [:]][kategori, default: 0] += tutar
        }
        return out
    }()

    /// Dönemde satış dışında stoktan çıkan malın bir kategoriye düşen maliyeti
    public func stoktanGider(from: MonthKey, to: MonthKey, category: ExpenseCategory) -> Kurus {
        Dates.monthRange(from: from, to: to).reduce(0) { $0 + (stoktanGiderler[$1]?[category] ?? 0) }
    }

    private var costCache: [String: CostBreakdown] = [:]
    private var tarihliUrunCache: [DateKey: [Id: Product]] = [:]
    private var tarihliMalzemeCache: [DateKey: [Id: StockMaterial]] = [:]
    /// Satışı girilmiş aylar
    lazy var satisliAylar: Set<MonthKey> = Set(state.sales.map(\.month))

    /// Ürün|kanal → satışların (ay, KDV oranı) listesi, aya göre sıralı: son satışın oranı bir kez taranır
    lazy var satisKdvDizini: [String: [(ay: MonthKey, oran: VatRate?)]] = {
        // Aynı ay içinde satış listesindeki sıra korunur (sıralama sıra numarasıyla kararlı)
        var d: [String: [(ay: MonthKey, sira: Int, oran: VatRate?)]] = [:]
        for (i, e) in state.sales.enumerated() {
            d["\(e.productId)|\(e.channelId)", default: []].append((e.month, i, e.vatRate))
        }
        return d.mapValues { $0.sorted { ($0.ay, $0.sira) < ($1.ay, $1.sira) }.map { ($0.ay, $0.oran) } }
    }()
    private lazy var receteGecmisiVar = state.products.contains { !($0.eskiReceteler ?? []).isEmpty }
    private lazy var malzemeGecmisiVar = state.materials.contains { !($0.eskiAyarlar ?? []).isEmpty }

    /// O gün geçerli ayarlarıyla malzemeler (geçmiş ay eski "sipariş başına" / paket ayarıyla)
    func malzemeler(asOf: DateKey?) -> [Id: StockMaterial] {
        guard let d = asOf, malzemeGecmisiVar else { return materialsById }
        if let c = tarihliMalzemeCache[d] { return c }
        let m = state.malzemelerTarihli(d)
        tarihliMalzemeCache[d] = m
        return m
    }

    /// O gün geçerli reçete ve set içerikleriyle ürünler (geçmiş ay eski reçeteyle hesaplanır)
    func urunler(asOf: DateKey?) -> [Id: Product] {
        guard let d = asOf, receteGecmisiVar else { return productsById }
        if let c = tarihliUrunCache[d] { return c }
        let u = state.urunlerTarihli(d)
        tarihliUrunCache[d] = u
        return u
    }
    private var companyCache: [MonthKey: CompanyMonthResult] = [:]
    private var expenseCache: [MonthKey: [ExpenseInstance]] = [:]
    var consumptionCache: [String: ConsumptionRate] = [:]
    private var vatCache: [MonthKey: VatStatus] = [:]
    var fiyatGuncelCache: [String: CompanyMonthResult?] = [:]

    func vatCacheGet(_ m: MonthKey) -> VatStatus? { vatCache[m] }
    func vatCacheSet(_ m: MonthKey, _ v: VatStatus) { vatCache[m] = v }

    public init(_ state: AppState) {
        self.state = state
    }

    // MARK: - Stok

    public func balance(_ item: ItemRef) -> ItemBalance { ledger.balance(item) }

    public func qty(_ item: ItemRef) -> BaseQty { ledger.balance(item).qty }

    public func history(_ item: ItemRef) -> [LedgerRow] {
        ledger.rows(for: item).reversed()
    }

    /// Güncel ağırlıklı ortalama birim maliyet (temel birim başına kuruş)
    public func unitCost(_ item: ItemRef) -> Double { ledger.balance(item).unitCost }

    /// Belirli bir tarihteki birim maliyet. O tarihe kadar hareket yoksa ilk bilinen maliyet.
    public func unitCost(_ item: ItemRef, asOf date: DateKey) -> Double {
        guard let h = costHistory[item.id], !h.isEmpty else { return 0 }
        var lo = 0, hi = h.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if h[mid].date <= date { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        // O gün maliyet bilinmiyorsa (stok eksideyken satış: alım sonradan girildi) ilk bilinen
        // pozitif maliyet kullanılır; yoksa o satışın maliyeti hiçbir ayda gider olmazdı.
        // Yalnızca stok o gün sıfır ya da eksiyse: elde maliyetsiz girilmiş stok varsa 0 kalır
        // (yoksa o stok hem 0 hem sonraki alımın fiyatıyla iki kez gider olurdu).
        if found < 0 { return h.first { $0.cost > 0 }?.cost ?? 0 }
        if h[found].cost > 0 { return h[found].cost }
        guard h[found].qty <= 0, let sonraki = h[found...].first(where: { $0.cost > 0 })?.cost else { return 0 }
        // Sonraki alımın fiyatı yalnızca eksik kalan (stok yokken satılan) adetlere uygulanır;
        // o hareketten önce elde olan maliyetsiz stok 0 TL kalır. Birim maliyet ikisinin ortalamasıdır.
        // Aynı gün (ör. ay sonu) birden çok satır olabilir: iki ürün aynı malzemeyi kullanır, her kanalın
        // koli satırı ayrıdır. Eksik payı o günün ilk hareketinden önceki bakiyeye göre hesaplanır.
        var ilk = found
        while ilk > 0, h[ilk - 1].date == h[found].date { ilk -= 1 }
        let onceki = ilk > 0 ? h[ilk - 1].qty : 0
        let tuketilen = onceki - h[found].qty
        guard tuketilen > 0 else { return sonraki }
        let eksik = min(tuketilen, -h[found].qty + min(onceki, 0))
        return sonraki * max(eksik, 0) / tuketilen
    }

    public var totalStockValue: Kurus {
        ledger.balances.values.reduce(0) { $0 + max($1.value, 0) }
    }

    // MARK: - Maliyet

    /// Ürün maliyeti dökümü. `asOf` verilirse o tarihteki malzeme maliyetleri kullanılır.
    public func cost(of productId: Id, asOf: DateKey? = nil) -> CostBreakdown {
        let key = "\(productId)|\(asOf ?? "now")"
        if let c = costCache[key] { return c }
        // Tarih verilmemişse bugün: ileri tarihli alımlar bugünün maliyetine karışmaz
        let gun = asOf ?? Dates.today()
        let lookup: (Id) -> Double = { [weak self] matId in
            self?.unitCost(.material(matId), asOf: gun) ?? 0
        }
        let urunAlimi: (Id) -> Double = { [weak self] urunId in
            self?.unitCost(.product(urunId), asOf: gun) ?? 0
        }
        let b = Costing.breakdown(
            products: urunler(asOf: asOf), materials: malzemeler(asOf: asOf),
            productId: productId, asOf: asOf, unitCostOf: lookup,
            purchasedUnitCostOf: urunAlimi
        )
        costCache[key] = b
        return b
    }

    /// Bir adet ürünün (ambalaj hariç) maliyeti, kuruşa yuvarlanmadan. Alımdan gelen maliyet adet
    /// başına yuvarlanıp çarpılırsa (3.000 adet 10.000 TL'ye alınıp satılınca) 10 TL kaybolurdu.
    func birimUrunMaliyeti(_ productId: Id, asOf: DateKey) -> Double {
        let b = cost(of: productId, asOf: asOf)
        guard b.ownFromPurchases else { return Double(b.intrinsic) }
        return Double(b.intrinsic - b.ownLines) + unitCost(.product(productId), asOf: asOf)
    }

    public func hasCycle(_ productId: Id) -> Bool {
        Costing.hasCycle(products: productsById, productId: productId)
    }

    // MARK: - Giderler

    public func expenseInstances(month: MonthKey) -> [ExpenseInstance] {
        if let c = expenseCache[month] { return c }
        let v = Expenses.instances(state, from: month, to: month)
        expenseCache[month] = v
        return v
    }

    public func expenseInstances(from: MonthKey, to: MonthKey) -> [ExpenseInstance] {
        Dates.monthRange(from: from, to: to).flatMap { expenseInstances(month: $0) }
    }

    // MARK: - Kanal kârlılığı

    public func channelResult(channelId: Id, month: MonthKey) -> ChannelMonthResult {
        companyMonth(month).channels.first { $0.channelId == channelId }
            ?? .empty(channelId: channelId, channelName: state.channel(channelId)?.name ?? "Kanal", month: month)
    }

    // MARK: - Şirket

    public func companyMonth(_ month: MonthKey) -> CompanyMonthResult {
        if let c = companyCache[month] { return c }
        let r = computeCompanyMonth(month)
        companyCache[month] = r
        return r
    }

    private func computeCompanyMonth(_ month: MonthKey) -> CompanyMonthResult {
        let asOf = Dates.monthEnd(month)
        let instances = expenseInstances(month: month)
        let salesOfMonth = state.sales.filter { $0.month == month }

        // Giderleri kapsamlarına göre ayır; sabit/satışa bağlı ayrımı korunur
        var ortakByCat: [ExpenseCategory: Kurus] = [:]
        var ortakDegisken: Kurus = 0
        var channelByCat: [Id: [ExpenseCategory: Kurus]] = [:]
        var channelDegiskenByCat: [Id: [ExpenseCategory: Kurus]] = [:]
        var kanalReklamNakit: [Id: Kurus] = [:]
        var stokAlimi: Kurus = 0
        var stokAlimiNakit: Kurus = 0
        var nakit: Kurus = 0
        var giderKdv: Kurus = 0

        for i in instances {
            nakit += i.cashAmount
            giderKdv += i.inputVat
            if i.capitalized {
                // Alımın değeri (KDV dahil) ve bu ay ödenen kısmı ayrı tutulur
                if i.sourceKind == .stokAlimi { stokAlimi += i.net + i.inputVat }
                stokAlimiNakit += i.cashAmount
                continue
            }
            guard i.expenseAmount != 0 else { continue }
            if let ch = i.scope.channelId {
                if i.category == .reklam { kanalReklamNakit[ch, default: 0] += i.cashAmount }
                channelByCat[ch, default: [:]][i.category, default: 0] += i.expenseAmount
                if i.behavior == .satisaBagli {
                    channelDegiskenByCat[ch, default: [:]][i.category, default: 0] += i.expenseAmount
                }
            } else {
                ortakByCat[i.category, default: 0] += i.expenseAmount
                if i.behavior == .satisaBagli { ortakDegisken += i.expenseAmount }
            }
        }

        // Satış dışında stoktan çıkan malın maliyeti (nakit çıkışı değildir: parası alımda ödendi)
        for (kategori, tutar) in stoktanGiderler[month] ?? [:] {
            ortakByCat[kategori, default: 0] += tutar
        }

        var results: [ChannelMonthResult] = []
        for ch in state.channels {
            let rows = salesOfMonth.filter { $0.channelId == ch.id }
            let catBucket = channelByCat[ch.id] ?? [:]
            // Satışı olmasa bile aylık sabit ücreti olan kanal o ayın gideridir:
            // mağaza aboneliği satış olmayan ayda da ödenir.
            let ucretVar = aylikSabitKanalUcreti(ch, month: month) > 0
            guard !rows.isEmpty || !catBucket.isEmpty
                    || state.channelMonth(month: month, channelId: ch.id) != nil
                    || ucretVar else {
                continue
            }
            results.append(computeChannel(
                ch, month: month, asOf: asOf, rows: rows,
                channelExpenses: catBucket,
                channelVariableExpenses: channelDegiskenByCat[ch.id] ?? [:]
            ))
        }
        // Satışı olmayan ama tanımlı kanallar da boş kartla görünsün.
        // Eksik bilgi uyarısı satış olup olmamasından bağımsızdır: kullanıcı
        // "bilmiyorum" dediyse o kanalın hesabı her ay yaklaşıktır.
        for ch in state.activeChannels where !results.contains(where: { $0.channelId == ch.id }) {
            var bos = ChannelMonthResult.empty(channelId: ch.id, channelName: ch.name, month: month)
            bos.eksikBilgiler = ch.rates(on: asOf).eksikler
            results.append(bos)
        }
        results.sort { a, b in
            let ia = state.channels.firstIndex { $0.id == a.channelId } ?? 99
            let ib = state.channels.firstIndex { $0.id == b.channelId } ?? 99
            return ia < ib
        }

        // Platformun kestiği tutarlar da nakit çıkışıdır
        // Platformun kestiği tutar KDV dahildir: net kısmı gider, KDV'si indirilecek KDV
        nakit += results.reduce(0) { $0 + $1.channelFees + $1.feeVat + $1.stopaj }
        // Elle girilen aylık reklam tutarının, gider kayıtlarını aşan kısmı da ödenmiştir
        for c in results where c.ads.isManual {
            nakit += max(c.ads.amount - (kanalReklamNakit[c.channelId] ?? 0), 0)
        }

        var breakdown = ortakByCat
        for c in results {
            breakdown[.komisyon, default: 0] += c.commission.amount
            breakdown[.kargo, default: 0] += c.shipping.amount + c.serviceFee.amount
            breakdown[.diger, default: 0] += c.otherDeduction.amount
            breakdown[.reklam, default: 0] += c.ads.amount
            breakdown[.urunUretimi, default: 0] += c.productCost
            breakdown[.ambalaj, default: 0] += c.packagingCost
            for (k, v) in c.otherChannelExpenses { breakdown[k, default: 0] += v }
        }
        breakdown = breakdown.filter { $0.value != 0 }

        return CompanyMonthResult(
            month: month,
            channels: results,
            ortakGider: ortakByCat.values.reduce(0, +),
            ortakGiderDegisken: ortakDegisken,
            stokAlimi: stokAlimi,
            stokAlimiNakit: stokAlimiNakit,
            nakitCikisi: nakit,
            giderKdv: giderKdv,
            expenseBreakdown: breakdown
        )
    }

    private func computeChannel(
        _ ch: Channel,
        month: MonthKey,
        asOf: DateKey,
        rows: [SalesEntry],
        channelExpenses: [ExpenseCategory: Kurus],
        channelVariableExpenses: [ExpenseCategory: Kurus]
    ) -> ChannelMonthResult {
        var r = ChannelMonthResult.empty(channelId: ch.id, channelName: ch.name, month: month)
        let cm = state.channelMonth(month: month, channelId: ch.id)

        var netSatisNet: Kurus = 0
        for e in rows {
            // Bütün satış tutarları KDV hariç tutulur: kârlılık net değerler üzerinden.
            let oran = e.resolvedVatRate, dahil = e.resolvedVatIncluded
            // Net satış satırın kendi bölmesinden gelir; brüt, indirim ve iade ayrı ayrı
            // yuvarlanınca "brüt − indirim − iade" ile net satış 1-2 kuruş kayabiliyordu.
            // Brüt, net satışla tutarlı olsun diye indirim ve iadenin üstüne eklenir.
            let indirimNet = Vat.net(e.discount, rate: oran, included: dahil)
            let iadeNet = Vat.net(e.returnsAmount, rate: oran, included: dahil)
            let satirNet = e.vatSplit.net
            r.grossSales += satirNet + indirimNet + iadeNet
            r.discount += indirimNet
            r.returnsAmount += iadeNet
            netSatisNet += satirNet
            // Kesintiler müşterinin ödediği KDV dahil tutar üzerinden alınır.
            // Satış "KDV hariç" girilmişse KDV'si eklenir; aksi halde komisyon eksik çıkar.
            let bolum = e.vatSplit
            r.netSalesIncVat += bolum.net + bolum.vat
            r.outputVat += bolum.vat
            r.units += e.qty
            r.returnedUnits += e.returnsQty
            let b = cost(of: e.productId, asOf: asOf)
            r.productCost += Money.roundHalfAwayFromZero(birimUrunMaliyeti(e.productId, asOf: asOf) * e.netQty)
            // Ambalaj brüt adet üzerinden gider: iade edilen siparişin kolisi geri gelmez
            r.packagingCost += Money.roundHalfAwayFromZero(Double(b.packaging) * e.qty)
        }
        r.netSales = netSatisNet
        // Birim maliyet (ürün + ambalaj) ayın ilk günüyle son günü arasında değiştiyse (yüzde eşiği yok), ay sonu
        // maliyetinin bütün aya uygulandığı açıkça söylenir: satışlar aylık toplam girildiği için hangi adedin
        // eski, hangisinin yeni maliyetle satıldığı bilinmez. Yalnızca kuruşa yuvarlanınca aynı kalan
        // (kuruş altı) farklar sayılmaz. Maliyeti ayın başında bilinmeyen (0) ürün değişmiş sayılmaz.
        let ayBasi = "\(month)-01"
        var bakilan = Set<Id>()
        for e in rows where e.netQty != 0 && bakilan.insert(e.productId).inserted {
            let bas = birimUrunMaliyeti(e.productId, asOf: ayBasi) + Double(cost(of: e.productId, asOf: ayBasi).packaging)
            let son = birimUrunMaliyeti(e.productId, asOf: asOf) + Double(cost(of: e.productId, asOf: asOf).packaging)
            if bas > 0, Money.roundHalfAwayFromZero(bas) != Money.roundHalfAwayFromZero(son) {
                r.maliyetiDegisenUrunler.append(productsById[e.productId]?.name ?? "Ürün")
            }
        }

        // Sipariş başına malzemeler (koli): ürün adedine değil gönderilen koli sayısına göre
        let siparisAmbalaji = OrderPackaging.hesapla(state, month: month, channelId: ch.id,
                                                    stokIcin: false)
        for k in siparisAmbalaji.kalemler {
            r.packagingCost += Money.roundHalfAwayFromZero(
                k.qty * unitCost(.material(k.materialId), asOf: asOf))
        }
        r.koliSayisi = siparisAmbalaji.koliSayisi
        r.koliTahmini = siparisAmbalaji.tahmini && !siparisAmbalaji.kalemler.isEmpty

        if let oc = cm?.orderCount, oc > 0 {
            r.orders = oc
            r.ordersIsEstimate = false
        } else {
            // İade edilen siparişin de gidiş kargosu ödendi: gönderilen adet sayılır (koli hesabıyla aynı)
            r.orders = Int(max(r.units, 0).rounded())
            r.ordersIsEstimate = true
        }

        // Pazaryeri kesintileri satış fiyatının KDV DAHİL hali üzerinden alınır.
        // Kesinti tutarının kendi KDV'si indirilecek KDV'ye gider, net kısmı gidere.
        let taban = Double(max(r.netSalesIncVat, 0))
        let kkdv = ch.kesintiKdv(on: Dates.monthEnd(month))
        var kesintiKdv: Kurus = 0
        func kesinti(_ manual: Kurus?, auto: Double) -> Figure {
            let ham = manual ?? Money.roundHalfAwayFromZero(auto)
            let bolum = Vat.split(ham, rate: kkdv.oran, included: kkdv.dahil)
            kesintiKdv += bolum.vat
            return Figure(bolum.net, manual: manual != nil)
        }

        // O ayda geçerli oranlar kullanılır: komisyon sonradan değişse bile
        // geçmiş ayın raporu değişmez.
        let oranlar = ch.rates(on: asOf ?? Dates.monthEnd(month))
        // Komisyon tabanı: bazı pazaryerleri KDV hariç fiyattan hesaplayıp üstüne KDV ekler
        let komisyonTabani = ch.komisyonKdvHaric(on: asOf ?? Dates.monthEnd(month))
            ? Double(max(r.netSales, 0)) * ch.kesintiKdvCarpani(on: Dates.monthEnd(month))
            : taban
        r.commission = kesinti(cm?.commissionActual,
                               auto: komisyonTabani * oranlar.commissionPct / 100 + taban * oranlar.paymentPct / 100)
        // E-ticaret stopajı: KDV hariç satış tutarının yüzdesi (komisyon, kargo düşülmez)
        if let oran = ch.stopajOrani(month: month) {
            r.stopaj = Money.roundHalfAwayFromZero(Double(max(r.netSales, 0)) * oran / 100)
        }
        r.shipping = kesinti(cm?.shippingActual,
                             auto: Double(oranlar.shippingPerOrder) * Double(r.orders))
        r.serviceFee = kesinti(cm?.serviceFeeActual,
                               auto: Double(oranlar.serviceFeePerOrder) * Double(r.orders))

        // Kullanıcının kendi eklediği kesintiler. "Bilmiyorum" işaretliler
        // hesaba katılmaz; sonuç yaklaşık olarak işaretlenir.
        var ekDegisken = 0.0
        for f in oranlar.extras where !f.unknown {
            // Kullanıcı o ayın gerçek komisyonunu (ya da kargosunu) girdiyse, aynı işi
            // gören ek kesinti tekrar eklenmez: elle girilen tutar onun da yerine geçer.
            if AylikKesinti.komisyonMu(f), cm?.commissionActual != nil { continue }
            if AylikKesinti.kargoMu(f), cm?.shippingActual != nil { continue }
            if AylikKesinti.hizmetMu(f), cm?.serviceFeeActual != nil { continue }
            switch f.basis {
            case .yuzde: ekDegisken += taban * f.value / 100
            case .siparisBasi: ekDegisken += f.value * Double(r.orders)
            case .aylikSabit: break   // aylikSabitKanalUcreti içinde
            case .elleAylik: break   // yalnızca elle girilen aylık tutardan gelir
            }
        }
        // Aylık sabit ücret yalnızca kanal başladıktan sonraki aylarda işler.
        // Kanala başlamadan önce girilmiş bir gider (ör. tanıtım reklamı) o aya ücret yazdırmaz.
        let sabitToplam = Double(aylikSabitKanalUcreti(ch, month: month))
        r.otherDeduction = kesinti(
            cm?.otherDeductionActual,
            auto: taban * oranlar.otherDeductionPct / 100 + sabitToplam + ekDegisken
        )
        r.feeVat = kesintiKdv
        r.eksikBilgiler = oranlar.eksikler
        // "Aylık gerçek tutarı ben gireceğim" denen kesintiler: o ay tutar girilmemişse
        // hesapta hiç görünmez. Sessizce 0 saymak yerine eksik olduğu söylenir.
        if r.units > 0 || r.orders > 0 || r.netSales != 0 {
            for f in oranlar.elleGirilecekler
            where AylikKesinti.alan(f) != .reklam && AylikKesinti.tutar(f, cm) == nil {
                r.eksikBilgiler.append("\(f.label.lowercased(with: Locale(identifier: "tr_TR"))) (aylık tutar girilmemiş)")
            }
        }
        // Aylık sabit kesintiler sipariş adedinden bağımsızdır; başa baş hesabı
        // için değişken kısımdan ayrı tutulur.
        r.fixedDeduction = min(
            Vat.net(Money.roundHalfAwayFromZero(sabitToplam),
                    rate: kkdv.oran, included: kkdv.dahil),
            r.otherDeduction.amount
        )
        let reklamToplam = channelExpenses[.reklam] ?? 0
        let reklamDegisken = channelVariableExpenses[.reklam] ?? 0
        r.ads = figure(cm?.adsActual, auto: Double(reklamToplam))
        // Elle aylık tutar girilmişse, altındaki giderlerin sabit/değişken
        // oranı korunur; hiç gider yoksa aylık rakam sabit sayılır.
        if let manual = cm?.adsActual {
            r.adsFixed = reklamToplam > 0
                ? manual - Money.roundHalfAwayFromZero(Double(manual) * Double(reklamDegisken) / Double(reklamToplam))
                : manual
        } else {
            r.adsFixed = reklamToplam - reklamDegisken
        }

        var others = channelExpenses
        others[.reklam] = nil
        r.otherChannelExpenses = others.filter { $0.value != 0 }
        r.otherChannelExpensesFixed = r.otherChannelExpenses.reduce(0) { acc, kv in
            acc + max(kv.value - (channelVariableExpenses[kv.key] ?? 0), 0)
        }
        return r
    }

    /// Kanalın bu ay için aylık sabit ücreti (abonelik, mağaza ücreti).
    ///
    /// Ücret yalnızca kanalın ilk izinden itibaren işler: ilk satışı ya da
    /// açıkça tarihli ilk ayar kaydı. Böylece sonradan eklenen bir kanalın
    /// ücreti, kanal henüz yokken geçen aylara geriye dönük yazılmaz ve
    /// geçmiş bir ayın kârı zamanla değişmez.
    func aylikSabitKanalUcreti(_ ch: Channel, month: MonthKey) -> Kurus {
        guard let baslangic = kanalBaslangicAyi(ch), month >= baslangic else { return 0 }
        // Arşivlenen kanal: son iz bıraktığı aydan sonrası için ücret işlemez,
        // ama geçmiş ayların raporu arşivlemekle değişmez.
        if let d = ch.kapaliDonemler {
            if d.contains(where: { $0.icinde(month) }) { return 0 }
        } else if ch.archived, let son = kanalSonAyi(ch), month > son {
            // Önceki sürümde arşivlenmiş (tarihsiz) kanal: eski kural
            return 0
        }
        let r = ch.rates(on: Dates.monthEnd(month))
        let ek = r.extras.filter { $0.basis == .aylikSabit && !$0.unknown }
            .reduce(0.0) { $0 + $1.value }
        return r.platformFeeMonthly + r.otherDeductionMonthly + Money.roundHalfAwayFromZero(ek)
    }

    /// Aylık girilen kesintiler için geçmiş aylardan tahmin.
    ///
    /// Kullanıcı "komisyonun aylık toplamını ben gireceğim" dediyse, ileriye dönük
    /// hesapta (başa baş, reklam hedefi) o kesinti bilinmiyor demektir. Geçmişte
    /// girilmiş gerçek tutarlardan oran çıkarılır ve sonuç "tahmini" işaretlenir;
    /// hiç veri yoksa açıkça eksik denir.
    func elleAylikTahmin(_ ch: Channel, on date: DateKey) -> AylikKesintiTahmini {
        var t = AylikKesintiTahmini()
        let ekler = ch.rates(on: date).elleGirilecekler
        guard !ekler.isEmpty else { return t }
        let buAy = Dates.month(of: date)
        // Aynı alana bağlı iki kesinti varsa alan bir kez tahmin edilir (çift sayım olmaz)
        var gorulen = Set<AylikKesinti.Alan>()
        for f in ekler {
            let alan = AylikKesinti.alan(f)
            // Reklam kanal kesintisi değildir; reklam hedefi zaten reklamdan öncesini ölçer
            guard alan != .reklam, gorulen.insert(alan).inserted else { continue }
            var bulundu = false
            for geri in 0...12 {
                let ay = Dates.addMonths(buAy, -geri)
                // 0 girildiyse de girilmiştir: "bu ay kargo ödemedim" geçerli bir cevaptır
                guard let cm = state.channelMonth(month: ay, channelId: ch.id),
                      let tutar = AylikKesinti.tutar(alan, cm) else { continue }
                let satirlar = state.sales.filter { $0.month == ay && $0.channelId == ch.id }
                let kdvDahil = satirlar.reduce(0) { toplam, e in
                    let b = e.vatSplit
                    return toplam + b.net + b.vat
                }
                // Gönderilen adet: iade edilenin de kargosu ödendi
                let adet = satirlar.reduce(0.0) { $0 + max($1.qty, 0) }
                let siparis = (cm.orderCount ?? 0) > 0 ? cm.orderCount! : Int(adet.rounded())
                switch alan {
                case .kargo, .hizmet:
                    guard siparis > 0 else { continue }
                    let deger = Double(tutar) / Double(siparis)
                    if alan == .kargo { t.kargoSiparisBasi = deger } else { t.hizmetSiparisBasi = deger }
                case .komisyon:
                    guard kdvDahil > 0 else { continue }
                    t.komisyonYuzde = Double(tutar) / Double(kdvDahil) * 100
                case .diger:
                    guard kdvDahil > 0 else { continue }
                    // Aylık sabit ücret ayrıca sabit gider sayılır; oranı şişirmesin
                    let sabit = aylikSabitKanalUcreti(ch, month: ay)
                    t.digerYuzde = Double(max(tutar - sabit, 0)) / Double(kdvDahil) * 100
                case .reklam:
                    continue
                }
                t.tahmin.append(f.label)
                bulundu = true
                break
            }
            if !bulundu { t.eksik.append(f.label) }
        }
        return t
    }

    func kanalSonAyi(_ ch: Channel) -> MonthKey? { state.kanalSonAyi(ch.id) }

    /// Kanalın ilk göründüğü ay: ilk satışı veya tarihli ilk ayar kaydı
    func kanalBaslangicAyi(_ ch: Channel) -> MonthKey? {
        let ilkSatis = state.sales.filter { $0.channelId == ch.id }.map(\.month).min()
        let ilkAyar = (ch.rateHistory ?? [])
            .map(\.from)
            .filter { $0 > "1970-01-01" }
            .min()
            .map { Dates.month(of: $0) }
        return [ilkSatis, ilkAyar].compactMap { $0 }.min()
    }

    private func figure(_ manual: Kurus?, auto: Double) -> Figure {
        if let m = manual { return Figure(m, manual: true) }
        return Figure(Money.roundHalfAwayFromZero(auto))
    }

    // MARK: - Yıl ve trend

    /// Yılın 12 ayı. Henüz gelmemiş aylar boş gelir: düzenli giderler ileriye
    /// yansıtılırsa yıllık gider şişer, kâr olduğundan kötü görünürdü.
    public func year(_ y: Int, today: DateKey = Dates.today()) -> YearResult {
        let buAy = Dates.month(of: today)
        return YearResult(year: y, months: (1...12).map { ay in
            let m = Dates.monthKey(y, ay)
            return m > buAy ? CompanyMonthResult.empty(m) : companyMonth(m)
        })
    }

    /// Bir dönemin bugüne kadarki toplamı (gelecek aylar sayılmaz)
    public func periodTotals(from: MonthKey, to: MonthKey, today: DateKey = Dates.today()) -> CompanyMonthResult {
        let son = min(to, Dates.month(of: today))
        guard son >= from else { return CompanyMonthResult.empty(to) }
        return companyTotals(from: from, to: son)
    }

    public func trend(endingAt month: MonthKey, months n: Int = 6) -> [TrendPoint] {
        let start = Dates.addMonths(month, -(n - 1))
        return Dates.monthRange(from: start, to: month).map {
            let r = companyMonth($0)
            return TrendPoint(month: $0, gelir: r.gercekCiro, gider: r.toplamGider, kar: r.gercekKar)
        }
    }

    public func channelTotals(from: MonthKey, to: MonthKey, channelId: Id) -> ChannelMonthResult {
        let name = state.channel(channelId)?.name ?? "Kanal"
        let list = Dates.monthRange(from: from, to: to).compactMap { m in
            companyMonth(m).channels.first { $0.channelId == channelId }
        }
        return list.aggregated(channelId: channelId, channelName: name, label: to)
    }

    public func companyTotals(from: MonthKey, to: MonthKey) -> CompanyMonthResult {
        let months = Dates.monthRange(from: from, to: to).map { companyMonth($0) }
        var out = CompanyMonthResult.empty(to)
        var byChannel: [Id: [ChannelMonthResult]] = [:]
        for m in months {
            out.ortakGider += m.ortakGider
            out.ortakGiderDegisken += m.ortakGiderDegisken
            out.stokAlimi += m.stokAlimi
            out.stokAlimiNakit += m.stokAlimiNakit
            out.nakitCikisi += m.nakitCikisi
            out.giderKdv += m.giderKdv
            for (k, v) in m.expenseBreakdown { out.expenseBreakdown[k, default: 0] += v }
            for c in m.channels { byChannel[c.channelId, default: []].append(c) }
        }
        out.channels = state.channels.compactMap { ch in
            guard let list = byChannel[ch.id], !list.isEmpty else { return nil }
            return list.aggregated(channelId: ch.id, channelName: ch.name, label: to)
        }
        return out
    }
}
