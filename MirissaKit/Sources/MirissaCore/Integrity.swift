import Foundation

/// Veri bütünlüğü denetimi.
///
/// Giriş ekranları hatalı veriyi zaten engeller. Bu denetim ikinci savunma
/// hattıdır: elle düzenlenmiş bir yedek, yarım kalmış bir göç veya ileride
/// eklenen bir kod yolu imkânsız bir duruma yol açarsa, sistem sessizce
/// yanlış rakam üretmek yerine bunu açıkça bildirir.
public struct IntegrityIssue: Identifiable, Hashable, Sendable {
    public enum Severity: String, Sendable, Hashable {
        /// Hesap sonucu güvenilmez
        case bozuk
        /// Hesap yapılabiliyor ama veri şüpheli
        case supheli
    }

    public var severity: Severity
    public var area: String
    public var message: String
    public var recordId: Id?

    public var id: String { "\(area)-\(message)-\(recordId ?? "-")" }

    public init(_ severity: Severity, _ area: String, _ message: String, recordId: Id? = nil) {
        self.severity = severity
        self.area = area
        self.message = message
        self.recordId = recordId
    }
}

public enum Integrity {

    public static func check(_ s: AppState) -> [IntegrityIssue] {
        var out: [IntegrityIssue] = []
        out += kimlikler(s)
        out += urunler(s)
        out += kanallar(s)
        out += satislar(s)
        out += giderVeAlimlar(s)
        out += stokHareketleri(s)
        out += fiyatVeMaliyetTarihleri(s)
        out += girisTutarliligi(s)
        return out
    }

    // MARK: Girilen rakamların birbirini tutması

    /// Tek tek geçerli görünen ama birlikte yanlış sonuç veren girişler.
    /// Hiçbiri sessizce düzeltilmez; kullanıcıya ne olduğu söylenir.
    private static func girisTutarliligi(_ s: AppState) -> [IntegrityIssue] {
        var out: [IntegrityIssue] = []
        let buAy = Dates.currentMonth()
        func ad(_ kanal: Id) -> String { s.channel(kanal)?.name ?? "Kanal" }

        for e in s.sales {
            let urun = s.product(e.productId)?.name ?? "Ürün"
            if e.qty == 0 && e.grossSales != 0 {
                out.append(IntegrityIssue(.supheli, "Satışlar",
                    "\(e.month) \(ad(e.channelId)) \(urun) satışında adet girilmemiş; ürün, ambalaj, "
                        + "koli ve kargo maliyeti hesaplanamıyor, kâr olduğundan yüksek görünür", recordId: e.id))
            }
            if e.qty > 0 && e.grossSales == 0 {
                out.append(IntegrityIssue(.supheli, "Satışlar",
                    "\(e.month) \(ad(e.channelId)) \(urun) satışında tutar 0; satış tutarı girilmemiş olabilir",
                    recordId: e.id))
            }
            if e.month > buAy {
                out.append(IntegrityIssue(.supheli, "Satışlar",
                    "\(urun) satışı ileri bir aya (\(e.month)) girilmiş; stok bugünden düşüyor",
                    recordId: e.id))
            }
        }

        // Ay kayıtları: sipariş sayısı, 3+ sipariş, eksi tutarlar, tekrar eden kayıt
        var gorulen = Set<String>()
        for cm in s.channelMonths {
            let anahtar = "\(cm.month)|\(cm.channelId)"
            if !gorulen.insert(anahtar).inserted {
                out.append(IntegrityIssue(.bozuk, "Kanallar",
                    "\(ad(cm.channelId)) \(cm.month) için iki ayrı ay kaydı var; yalnızca biri hesaba giriyor",
                    recordId: cm.id))
            }
            let adet = s.sales.filter { $0.month == cm.month && $0.channelId == cm.channelId }
                .reduce(0.0) { $0 + $1.qty }
            if let o = cm.orderCount, o > 0 {
                if adet == 0 {
                    out.append(IntegrityIssue(.supheli, "Kanallar",
                        "\(ad(cm.channelId)) \(cm.month): \(o) sipariş girilmiş ama o ay satış yok; "
                            + "kargo ve hizmet bedeli satışsız aya yazılıyor", recordId: cm.id))
                } else if Double(o) > adet {
                    out.append(IntegrityIssue(.supheli, "Kanallar",
                        "\(ad(cm.channelId)) \(cm.month): sipariş sayısı (\(o)) satılan üründen "
                            + "(\(Int(adet))) fazla; kargo fazla hesaplanıyor olabilir", recordId: cm.id))
                }
                if let b = cm.bigOrderCount, b > o {
                    out.append(IntegrityIssue(.supheli, "Kanallar",
                        "\(ad(cm.channelId)) \(cm.month): 3+ ürünlü sipariş (\(b)) toplam siparişten fazla",
                        recordId: cm.id))
                }
            }
            let eksiler = [("komisyon", cm.commissionActual), ("kargo", cm.shippingActual),
                           ("hizmet bedeli", cm.serviceFeeActual), ("diğer kesinti", cm.otherDeductionActual),
                           ("reklam", cm.adsActual)]
                .filter { ($0.1 ?? 0) < 0 }.map(\.0)
            if !eksiler.isEmpty {
                out.append(IntegrityIssue(.bozuk, "Kanallar",
                    "\(ad(cm.channelId)) \(cm.month) için eksi tutar girilmiş (\(eksiler.joined(separator: ", "))); "
                        + "gider gelir gibi sayılıyor", recordId: cm.id))
            }
        }

        // Kanal oranlarında eksi kesinti
        for ch in s.channels {
            let kayitlar = (ch.rateHistory ?? []) + [ch.currentRates]
            let eksi = kayitlar.contains { r in
                r.commissionPct < 0 || r.paymentPct < 0 || r.otherDeductionPct < 0
                    || r.shippingPerOrder < 0 || r.serviceFeePerOrder < 0
                    || r.platformFeeMonthly < 0 || r.otherDeductionMonthly < 0
                    || r.extras.contains { $0.value < 0 }
            }
            if eksi {
                out.append(IntegrityIssue(.bozuk, "Kanallar",
                    "\(ch.name) kesinti ayarlarında eksi değer var; kesinti gelir gibi sayılıyor",
                    recordId: ch.id))
            }
        }

        // Gider: aya özel eksi tutar
        for g in s.expenses {
            for (ay, ov) in g.overrides where (ov.amount ?? 0) < 0 {
                out.append(IntegrityIssue(.bozuk, "Giderler",
                    "\(g.name) \(ay) için eksi tutar girilmiş; gider gelir gibi sayılıyor", recordId: g.id))
            }
        }

        // Vadeli alım: peşinat + taksitler ödenen toplamı (KDV dahil) vermeli
        for p in s.purchases {
            guard let plan = p.odeme else { continue }
            let brut = p.landedSplit.net + p.landedSplit.vat
            if plan.toplam != brut {
                out.append(IntegrityIssue(.supheli, "Alımlar",
                    "\(s.itemName(p.item)) alımının ödeme planı (\(Money.format(plan.toplam))) "
                        + "ödenecek tutarı (\(Money.format(brut))) tutmuyor", recordId: p.id))
            }
        }

        // Alım: adetsiz para, eksi nakliye, sete yapılan stok kaydı
        for p in s.purchases {
            if p.qty == 0 && p.landedTotal != 0 {
                out.append(IntegrityIssue(.supheli, "Alımlar",
                    "\(s.itemName(p.item)) alımında miktar 0 ama para ödenmiş; tutar stoğa ve maliyete girmiyor",
                    recordId: p.id))
            }
            if p.shippingCost < 0 {
                out.append(IntegrityIssue(.bozuk, "Alımlar",
                    "\(s.itemName(p.item)) alımında nakliye eksi girilmiş", recordId: p.id))
            }
        }
        let setler = Set(s.products.filter(\.isBundle).map(\.id))
        let setKayitlari = s.purchases.map(\.item) + s.adjustments.map(\.item) + s.counts.map(\.item)
        for sid in setler where setKayitlari.contains(.product(sid)) {
            out.append(IntegrityIssue(.supheli, "Stok",
                "\(s.product(sid)?.name ?? "Set") bir set ama alım, düzeltme ya da sayım kaydı var; "
                    + "setin kendi stoğu tutulmaz, bu kayıtlar gizli bir stok oluşturuyor", recordId: sid))
        }

        // Satılan set: bileşeninin maliyeti bilinmiyorsa set kârı şişer
        let e = Engine(s)
        let satilanSetler = Set(s.sales.map(\.productId)).intersection(setler)
        for sid in satilanSetler {
            let eksik = e.maliyetiEksikUrunler(sid, asOf: Dates.today())
            if !eksik.isEmpty {
                let adlar = eksik.compactMap { s.product($0)?.name }.joined(separator: ", ")
                out.append(IntegrityIssue(.supheli, "Maliyet",
                    "\(s.product(sid)?.name ?? "Set") satılıyor ama içindeki \(adlar) maliyeti bilinmiyor; "
                        + "set kârı olduğundan yüksek görünür", recordId: sid))
            }
        }
        return out
    }

    /// Hesapların güvenilmez olduğu durumlar
    public static func blocking(_ s: AppState) -> [IntegrityIssue] {
        check(s).filter { $0.severity == .bozuk }
    }

    // MARK: Aynı kimliğin iki kayıtta kullanılması

    private static func kimlikler(_ s: AppState) -> [IntegrityIssue] {
        var out: [IntegrityIssue] = []
        func tekrar<T>(_ items: [T], _ id: (T) -> Id, _ alan: String) {
            var gorulen = Set<Id>()
            for i in items {
                let k = id(i)
                if !gorulen.insert(k).inserted {
                    out.append(IntegrityIssue(.bozuk, alan,
                        "Aynı kimlik iki kayıtta kullanılmış: \(k)", recordId: k))
                }
            }
        }
        tekrar(s.products, { $0.id }, "Ürünler")
        tekrar(s.materials, { $0.id }, "Malzemeler")
        tekrar(s.channels, { $0.id }, "Kanallar")
        tekrar(s.sales, { $0.id }, "Satışlar")
        tekrar(s.expenses, { $0.id }, "Giderler")
        tekrar(s.purchases, { $0.id }, "Alımlar")
        tekrar(s.adjustments, { $0.id }, "Stok düzeltmeleri")
        tekrar(s.counts, { $0.id }, "Stok sayımları")
        tekrar(s.drafts, { $0.id }, "Yarım akışlar")
        return out
    }

    // MARK: Ürün ve set

    private static func urunler(_ s: AppState) -> [IntegrityIssue] {
        var out: [IntegrityIssue] = []
        let byId = Dictionary(s.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let malzemeIdleri = Set(s.materials.map(\.id))

        for p in s.products {
            if Costing.hasCycle(products: byId, productId: p.id) {
                out.append(IntegrityIssue(.bozuk, "Ürünler",
                    "\(p.name) kendini içeriyor; maliyet hesaplanamaz", recordId: p.id))
            }
            if p.isBundle, p.components.isEmpty {
                out.append(IntegrityIssue(.supheli, "Ürünler",
                    "\(p.name) set olarak işaretli ama içinde ürün yok", recordId: p.id))
            }
            if p.isBundle, p.openingQty ?? 0 != 0 {
                out.append(IntegrityIssue(.supheli, "Ürünler",
                    "\(p.name) bir set; kendi başlangıç stoğu hesaba katılmaz", recordId: p.id))
            }
            for c in p.components where byId[c.productId] == nil {
                out.append(IntegrityIssue(.bozuk, "Ürünler",
                    "\(p.name) içinde olmayan bir ürün var", recordId: p.id))
            }
            for c in p.components where c.qty <= 0 {
                out.append(IntegrityIssue(.bozuk, "Ürünler",
                    "\(p.name) içindeki bileşen adedi sıfır veya eksi", recordId: p.id))
            }
            for line in p.recipe where malzemeIdleri.contains(line.materialId) == false {
                out.append(IntegrityIssue(.bozuk, "Reçeteler",
                    "\(p.name) reçetesinde olmayan bir malzeme var", recordId: p.id))
            }
            for line in p.recipe where line.qty < 0 {
                out.append(IntegrityIssue(.bozuk, "Reçeteler",
                    "\(p.name) reçetesinde eksi miktar var", recordId: p.id))
            }
            for line in p.costLines where line.amount < 0 {
                out.append(IntegrityIssue(.bozuk, "Ürünler",
                    "\(p.name) maliyet kalemi eksi", recordId: p.id))
            }
            if (p.openingQty ?? 0) < 0 {
                out.append(IntegrityIssue(.bozuk, "Ürünler",
                    "\(p.name) başlangıç stoğu eksi", recordId: p.id))
            }
        }
        for m in s.materials where (m.openingQty ?? 0) < 0 || (m.openingUnitCost ?? 0) < 0 {
            out.append(IntegrityIssue(.bozuk, "Malzemeler",
                "\(m.name) başlangıç miktarı veya maliyeti eksi", recordId: m.id))
        }
        return out
    }

    // MARK: Kanal

    private static func kanallar(_ s: AppState) -> [IntegrityIssue] {
        var out: [IntegrityIssue] = []
        for c in s.channels {
            var gorulenTarih = Set<DateKey>()
            for r in c.rateHistory ?? [] {
                if !gorulenTarih.insert(r.from).inserted {
                    out.append(IntegrityIssue(.bozuk, "Kanallar",
                        "\(c.name) için aynı tarihte iki farklı kesinti ayarı var",
                        recordId: c.id))
                }
                let toplamOran = r.commissionPct + r.paymentPct + r.otherDeductionPct
                    + r.extras.filter { $0.basis == .yuzde && !$0.unknown }
                        .reduce(0) { $0 + $1.value }
                if toplamOran > 100 {
                    out.append(IntegrityIssue(.bozuk, "Kanallar",
                        "\(c.name) kesinti oranları toplamı %100'ü aşıyor", recordId: c.id))
                }
                if toplamOran < 0 || r.shippingPerOrder < 0 || r.serviceFeePerOrder < 0 {
                    out.append(IntegrityIssue(.bozuk, "Kanallar",
                        "\(c.name) kesintilerinde eksi değer var", recordId: c.id))
                }
                if !gecerliTarih(r.from) {
                    out.append(IntegrityIssue(.bozuk, "Kanallar",
                        "\(c.name) kesinti ayarında geçersiz tarih: \(r.from)", recordId: c.id))
                }
            }
            for urunId in c.soldProductIds ?? []
            where !s.products.contains(where: { $0.id == urunId }) {
                out.append(IntegrityIssue(.bozuk, "Kanallar",
                    "\(c.name) satış listesinde olmayan bir ürün var", recordId: c.id))
            }
            let duz = c.commissionPct + c.paymentPct + c.otherDeductionPct
            if duz > 100 {
                out.append(IntegrityIssue(.bozuk, "Kanallar",
                    "\(c.name) kesinti oranları toplamı %100'ü aşıyor", recordId: c.id))
            }
        }
        return out
    }

    // MARK: Satış

    private static func satislar(_ s: AppState) -> [IntegrityIssue] {
        var out: [IntegrityIssue] = []
        let urunIdleri = Set(s.products.map(\.id))
        let kanalIdleri = Set(s.channels.map(\.id))
        for e in s.sales {
            if !urunIdleri.contains(e.productId) {
                out.append(IntegrityIssue(.bozuk, "Satışlar",
                    "Olmayan bir ürüne ait satış kaydı var", recordId: e.id))
            }
            if !kanalIdleri.contains(e.channelId) {
                out.append(IntegrityIssue(.bozuk, "Satışlar",
                    "Olmayan bir kanala ait satış kaydı var", recordId: e.id))
            }
            if e.qty < 0 || e.returnsQty < 0 {
                out.append(IntegrityIssue(.bozuk, "Satışlar",
                    "Satış veya iade adedi eksi", recordId: e.id))
            }
            if e.returnsQty > e.qty {
                out.append(IntegrityIssue(.bozuk, "Satışlar",
                    "İade adedi satılan adetten fazla", recordId: e.id))
            }
            if e.grossSales < 0 || e.discount < 0 || e.returnsAmount < 0 {
                out.append(IntegrityIssue(.bozuk, "Satışlar",
                    "Satış tutarlarında eksi değer var", recordId: e.id))
            }
            if e.netSales < 0 {
                out.append(IntegrityIssue(.bozuk, "Satışlar",
                    "İndirim ve iade toplamı satıştan fazla; net satış eksi çıkıyor",
                    recordId: e.id))
            }
            if !gecerliAy(e.month) {
                out.append(IntegrityIssue(.bozuk, "Satışlar",
                    "Geçersiz ay: \(e.month)", recordId: e.id))
            }
        }
        // Aynı ay + kanal + ürün birden çok kez
        var anahtarlar: [String: Int] = [:]
        for e in s.sales { anahtarlar["\(e.month)|\(e.channelId)|\(e.productId)", default: 0] += 1 }
        for (k, adet) in anahtarlar where adet > 1 {
            let parca = k.split(separator: "|")
            let urun = parca.count > 2 ? s.product(String(parca[2]))?.name ?? "ürün" : "ürün"
            out.append(IntegrityIssue(.supheli, "Satışlar",
                "\(Dates.displayMonth(String(parca[0]))) ayında \(urun) için \(adet) ayrı satır var; "
                    + "ay toplamı iki kez girilmiş olabilir"))
        }
        return out
    }

    // MARK: Gider ve alım

    private static func giderVeAlimlar(_ s: AppState) -> [IntegrityIssue] {
        var out: [IntegrityIssue] = []
        let kanalIdleri = Set(s.channels.map(\.id))
        let malzemeIdleri = Set(s.materials.map(\.id))
        let urunIdleri = Set(s.products.map(\.id))

        for e in s.expenses {
            if e.amount < 0 {
                out.append(IntegrityIssue(.bozuk, "Giderler",
                    "\(e.name) tutarı eksi", recordId: e.id))
            }
            if let ch = e.scope.channelId, !kanalIdleri.contains(ch) {
                out.append(IntegrityIssue(.bozuk, "Giderler",
                    "\(e.name) olmayan bir kanala işaretlenmiş", recordId: e.id))
            }
            if !gecerliTarih(e.date) {
                out.append(IntegrityIssue(.bozuk, "Giderler",
                    "\(e.name) geçersiz tarih: \(e.date)", recordId: e.id))
            }
            if let bitis = e.endMonth, bitis < Dates.month(of: e.date) {
                out.append(IntegrityIssue(.supheli, "Giderler",
                    "\(e.name) bitiş ayı başlangıcından önce", recordId: e.id))
            }
        }
        for p in s.purchases {
            let ref = p.item
            let var_ = ref.kind == .material ? malzemeIdleri.contains(ref.id)
                                             : urunIdleri.contains(ref.id)
            if !var_ {
                out.append(IntegrityIssue(.bozuk, "Alımlar",
                    "Olmayan bir kaleme ait alım kaydı var", recordId: p.id))
            }
            if p.qty < 0 || p.totalPaid < 0 {
                out.append(IntegrityIssue(.bozuk, "Alımlar",
                    "Alım miktarı veya tutarı eksi", recordId: p.id))
            }
            if !gecerliTarih(p.date) {
                out.append(IntegrityIssue(.bozuk, "Alımlar",
                    "Geçersiz tarih: \(p.date)", recordId: p.id))
            }
        }
        return out
    }

    // MARK: Stok hareketleri

    private static func stokHareketleri(_ s: AppState) -> [IntegrityIssue] {
        var out: [IntegrityIssue] = []
        for a in s.adjustments where a.qty < 0 {
            out.append(IntegrityIssue(.bozuk, "Stok düzeltmeleri",
                "Düzeltme miktarı eksi girilmiş", recordId: a.id))
        }
        for c in s.counts where c.countedQty < 0 {
            out.append(IntegrityIssue(.bozuk, "Stok sayımları",
                "Sayılan miktar eksi", recordId: c.id))
        }
        // Eksi stok: sessizce kabul edilmez, açıkça bildirilir
        let e = Engine(s)
        for p in s.products where p.tracksOwnStock {
            if e.qty(.product(p.id)) < 0 {
                out.append(IntegrityIssue(.supheli, "Stok",
                    "\(p.name) stoğu eksiye düştü; bir alım veya sayım eksik olabilir",
                    recordId: p.id))
            }
        }
        for m in s.materials where e.qty(.material(m.id)) < 0 {
            out.append(IntegrityIssue(.supheli, "Stok",
                "\(m.name) stoğu eksiye düştü; bir alım veya sayım eksik olabilir",
                recordId: m.id))
        }

        // Elde mal var ama maliyeti girilmemiş: stok değeri ve kâr eksik çıkar.
        // Sıfır maliyet gerçek bir rakam gibi gösterilmemeli.
        for p in s.products where p.tracksOwnStock {
            if e.qty(.product(p.id)) > 0, e.unitCost(.product(p.id)) == 0 {
                out.append(IntegrityIssue(.supheli, "Stok",
                    "\(p.name) stokta görünüyor ama birim maliyeti girilmemiş; "
                        + "stok değeri ve kâr olduğundan düşük çıkar", recordId: p.id))
            }
        }
        for m in s.materials {
            if e.qty(.material(m.id)) > 0, e.unitCost(.material(m.id)) == 0 {
                out.append(IntegrityIssue(.supheli, "Stok",
                    "\(m.name) stokta görünüyor ama birim maliyeti girilmemiş; "
                        + "ambalaj maliyeti eksik hesaplanır", recordId: m.id))
            }
        }

        // Stok bir dönem eksiye düşüp sonra düzelmişse, o dönemde satılan malın
        // maliyeti eksik hesaplanmış olabilir. Son bakiyeye bakmak bunu göstermez.
        for (_, b) in e.ledger.balances where b.wentNegative && b.qty >= 0 {
            out.append(IntegrityIssue(.supheli, "Stok",
                "\(s.itemName(b.item)) stoğu bir dönem eksiye düştü; o günlerin maliyeti "
                    + "eksik hesaplanmış olabilir. Eksik bir alım ya da açılış stoğu olabilir",
                recordId: b.item.id))
        }

        // Açılış stoğu maliyetsiz girilmişse ortalama maliyet olduğundan düşük çıkar
        for p in s.products where (p.openingQty ?? 0) > 0 && p.openingUnitCost == nil {
            out.append(IntegrityIssue(.supheli, "Stok",
                "\(p.name) açılış stoğu birim maliyeti girilmeden kaydedilmiş; "
                    + "ortalama maliyet ve kâr olduğundan iyi görünür", recordId: p.id))
        }
        for m in s.materials where (m.openingQty ?? 0) > 0 && m.openingUnitCost == nil {
            out.append(IntegrityIssue(.supheli, "Stok",
                "\(m.name) açılış stoğu birim maliyeti girilmeden kaydedilmiş; "
                    + "ambalaj maliyeti olduğundan düşük çıkar", recordId: m.id))
        }

        // Birimi artık çevrilemeyen kayıtlar sessizce hesaba girmez
        func cevrilemez(_ item: ItemRef, _ qty: Double, _ unit: UnitCode) -> Bool {
            Units.toBaseOrNil(qty: qty, unit: unit, baseUnit: s.itemBaseUnit(item),
                              packSizes: s.itemPackSizes(item)) == nil
        }
        for p in s.purchases where s.itemExists(p.item) && cevrilemez(p.item, p.qty, p.unit) {
            out.append(IntegrityIssue(.bozuk, "Stok",
                "\(s.itemName(p.item)) alımı \(p.unit.displayName) ile girilmiş ama malzemede "
                    + "bu birimin karşılığı yok; alım stoğa ve maliyete hiç girmiyor", recordId: p.id))
        }
        for a in s.adjustments where s.itemExists(a.item) && cevrilemez(a.item, a.qty, a.unit) {
            out.append(IntegrityIssue(.bozuk, "Stok",
                "\(s.itemName(a.item)) düzeltmesinin birimi (\(a.unit.displayName)) çevrilemiyor; "
                    + "kayıt hesaba girmiyor", recordId: a.id))
        }
        for c in s.counts where s.itemExists(c.item) && cevrilemez(c.item, c.countedQty, c.unit) {
            out.append(IntegrityIssue(.bozuk, "Stok",
                "\(s.itemName(c.item)) sayımının birimi (\(c.unit.displayName)) çevrilemiyor; "
                    + "sayım hesaba girmiyor", recordId: c.id))
        }
        for p in s.products {
            for line in p.recipe where s.material(line.materialId) != nil
            && cevrilemez(.material(line.materialId), line.qty, line.unit) {
                out.append(IntegrityIssue(.bozuk, "Reçeteler",
                    "\(p.name) reçetesinde \(s.itemName(.material(line.materialId))) "
                        + "\(line.unit.displayName) ile yazılmış ama bu birim artık tanımlı değil; "
                        + "ne stoktan düşüyor ne maliyete giriyor", recordId: p.id))
            }
        }

        // Girilen ürün maliyeti ile gerçek alım ortalaması birbirini tutmuyor:
        // kâr hesabı girilen rakamı kullanır, ama ödenen para farklıysa kâr yanlış çıkar.
        for p in s.products where p.tracksOwnStock && !p.isBundle && !p.archived {
            let girilen = p.costLines(on: nil).reduce(0) { $0 + $1.amount }
            let alim = e.unitCost(.product(p.id))
            guard girilen > 0, alim > 0 else { continue }
            let fark = abs(Double(girilen) - alim) / alim
            guard fark > 0.02 else { continue }
            out.append(IntegrityIssue(.supheli, "Maliyet",
                "\(p.name) maliyeti \(Money.format(girilen)) girilmiş ama alımlardan ortalama "
                    + "\(Money.format(Money.roundHalfAwayFromZero(alim))) çıkıyor. Kâr hesabında "
                    + "\(Money.format(girilen)) kullanılıyor; gerçek maliyet farklıysa ürün maliyetini güncelle",
                recordId: p.id))
        }

        // Ambalaj: satılan her ürün koli, patpat, dolgu gibi malzemeler harcar.
        // Reçete yoksa ya da malzemenin maliyeti bilinmiyorsa ambalaj maliyeti
        // sessizce 0 sayılır ve kâr olduğundan yüksek çıkar.
        let satilanlar = Set(s.sales.filter { $0.qty > 0 }.map(\.productId))
        var maliyetsizMalzeme = Set<Id>()
        for p in s.products where satilanlar.contains(p.id) && !p.archived {
            let maliyetliSatirlar = p.recipe.filter {
                ($0.resolvedAddsCost || $0.resolvedConsumesStock) && $0.qty > 0
            }
            if maliyetliSatirlar.isEmpty {
                out.append(IntegrityIssue(.supheli, "Ambalaj",
                    "\(p.name) satılıyor ama ambalaj reçetesi yok; koli, patpat, dolgu gibi "
                        + "malzemeler bu ürünün maliyetine eklenmiyor", recordId: p.id))
                continue
            }
            for line in maliyetliSatirlar where line.resolvedAddsCost {
                guard let m = s.material(line.materialId),
                      e.qty(.material(m.id)) <= 0,       // stokta varsa yukarıda uyarıldı
                      e.unitCost(.material(m.id)) == 0,
                      maliyetsizMalzeme.insert(m.id).inserted else { continue }
                out.append(IntegrityIssue(.supheli, "Ambalaj",
                    "\(m.name) \(p.name) paketlemesinde kullanılıyor ama maliyeti bilinmiyor "
                        + "(hiç alım girilmemiş); ambalaj maliyeti 0 sayılıyor", recordId: m.id))
            }
        }
        return out
    }

    // MARK: Fiyat ve maliyet tarihçesi

    private static func fiyatVeMaliyetTarihleri(_ s: AppState) -> [IntegrityIssue] {
        var out: [IntegrityIssue] = []
        for p in s.products {
            var gorulen = Set<String>()
            for nokta in p.priceHistory ?? [] {
                let anahtar = "\(nokta.channelId ?? "-")|\(nokta.from)"
                if !gorulen.insert(anahtar).inserted {
                    out.append(IntegrityIssue(.bozuk, "Fiyatlar",
                        "\(p.name) için aynı tarihte iki farklı fiyat var", recordId: p.id))
                }
                if nokta.amount < 0 {
                    out.append(IntegrityIssue(.bozuk, "Fiyatlar",
                        "\(p.name) fiyatı eksi", recordId: p.id))
                }
                if let bitis = nokta.to, bitis < nokta.from {
                    out.append(IntegrityIssue(.bozuk, "Fiyatlar",
                        "\(p.name) fiyatının bitişi başlangıcından önce", recordId: p.id))
                }
                if !gecerliTarih(nokta.from) {
                    out.append(IntegrityIssue(.bozuk, "Fiyatlar",
                        "\(p.name) fiyatında geçersiz tarih: \(nokta.from)", recordId: p.id))
                }
            }
            for line in p.costLines {
                if let f = line.validFrom, let t = line.validTo, t < f {
                    out.append(IntegrityIssue(.bozuk, "Maliyetler",
                        "\(p.name) maliyet kaleminin bitişi başlangıcından önce", recordId: p.id))
                }
            }
            // Aynı anda geçerli iki aynı adlı maliyet kalemi = çift sayım
            let aktif = p.costLines(on: nil)
            let adlar = Dictionary(grouping: aktif, by: { $0.label.trimmingCharacters(in: .whitespaces) })
            for (ad, liste) in adlar where liste.count > 1 && !ad.isEmpty {
                out.append(IntegrityIssue(.supheli, "Maliyetler",
                    "\(p.name) için \"\(ad)\" adlı maliyet kalemi \(liste.count) kez geçerli; "
                        + "maliyet iki kez sayılıyor olabilir", recordId: p.id))
            }
        }
        return out
    }

    // MARK: Tarih biçimi

    private static func gecerliTarih(_ d: DateKey) -> Bool {
        let p = d.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let g = Int(p[2]),
              y >= 1970, y <= 2200, (1...12).contains(m) else { return false }
        return g >= 1 && g <= Dates.daysInMonth(year: y, month: m)
    }

    private static func gecerliAy(_ m: MonthKey) -> Bool {
        let p = m.split(separator: "-")
        guard p.count == 2, let y = Int(p[0]), let ay = Int(p[1]),
              y >= 1970, y <= 2200, (1...12).contains(ay) else { return false }
        return true
    }
}
