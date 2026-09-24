import Foundation

/// Değişiklik günlüğü: hangi kayıt ne zaman eklendi, değişti ya da silindi.
public enum DegisiklikGunlugu {
    public static let enFazla = 1_000

    /// İki durum arasındaki farkları kayıt türü ve kimliğe göre çıkarır
    public static func fark(eski: AppState, yeni: AppState,
                            zaman: String = ISO8601DateFormatter().string(from: Date())) -> [ChangeLogEntry] {
        var out: [ChangeLogEntry] = []
        func karsilastir<T: Identifiable & Hashable>(_ alan: String, _ a: [T], _ b: [T],
                                                     _ ad: (T) -> String) where T.ID == Id {
            let eskiler = Dictionary(a.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
            let yeniler = Dictionary(b.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
            for (id, y) in yeniler {
                if let e = eskiler[id] {
                    if e != y { out.append(ChangeLogEntry(zaman: zaman, tur: .degisti, alan: alan, aciklama: ad(y))) }
                } else {
                    out.append(ChangeLogEntry(zaman: zaman, tur: .eklendi, alan: alan, aciklama: ad(y)))
                }
            }
            for (id, e) in eskiler where yeniler[id] == nil {
                out.append(ChangeLogEntry(zaman: zaman, tur: .silindi, alan: alan, aciklama: ad(e)))
            }
        }
        karsilastir("Satış", eski.sales, yeni.sales) { s in
            "\(s.month) \(yeni.channel(s.channelId)?.name ?? eski.channel(s.channelId)?.name ?? "") "
                + "\(yeni.product(s.productId)?.name ?? eski.product(s.productId)?.name ?? "") "
                + "\(Int(s.qty)) adet \(Money.format(s.grossSales))"
        }
        karsilastir("Gider", eski.expenses, yeni.expenses) { "\($0.name) \(Money.format($0.amount))" }
        karsilastir("Alım", eski.purchases, yeni.purchases) {
            "\($0.date) \(yeni.itemName($0.item)) \(Money.format($0.landedTotal))"
        }
        karsilastir("Stok düzeltme", eski.adjustments, yeni.adjustments) {
            "\($0.date) \(yeni.itemName($0.item)) \($0.reason.displayName)"
        }
        karsilastir("Sayım", eski.counts, yeni.counts) { "\($0.date) \(yeni.itemName($0.item))" }
        karsilastir("Kanal ayı", eski.channelMonths, yeni.channelMonths) {
            "\($0.month) \(yeni.channel($0.channelId)?.name ?? "")"
        }
        karsilastir("Ürün", eski.products, yeni.products) { $0.name }
        karsilastir("Malzeme", eski.materials, yeni.materials) { $0.name }
        karsilastir("Kanal", eski.channels, yeni.channels) { $0.name }
        karsilastir("Alacak / borç", eski.balances, yeni.balances) { "\($0.name) \(Money.format($0.amount))" }
        // KDV ayarları geçmiş ayların kârını ve KDV'sini değiştirebilir: günlüğe yazılır
        let e = eski.settings, y = yeni.settings
        if e.vatEnabled != y.vatEnabled || e.defaultVatRate != y.defaultVatRate
            || e.defaultVatIncluded != y.defaultVatIncluded {
            out.append(ChangeLogEntry(zaman: zaman, tur: .degisti, alan: "KDV ayarı", aciklama:
                (y.vatEnabled ? "KDV takibi açık" : "KDV takibi kapalı")
                + ", varsayılan \(y.defaultVatRate.displayName), tutarlar KDV "
                + (y.defaultVatIncluded ? "dahil" : "hariç")))
        }
        return out.sorted { ($0.alan, $0.aciklama) < ($1.alan, $1.aciklama) }
    }
}

/// KDV beyanı verilen ayların kilidi.
/// Kilitli bir aya ait satış, gider, alım, stok kaydı ya da o ayın KDV'si değişemez.
public enum AyKilidi {

    /// Değişiklik, verilen aya kadar olan bir kayda (ya da tarihli ürün/malzeme/kanal ayarına) mı ait?
    /// İleri tarihli yeni kayıtlar geçmişe dokunmaz sayılır.
    private static func gecmiseDokunuyor(eski: AppState, yeni: AppState, ay: MonthKey) -> Bool {
        let son = Dates.monthEnd(ay)
        func degisti<T: Hashable>(_ a: [T], _ b: [T], _ tarih: (T) -> DateKey) -> Bool {
            Set(a.filter { tarih($0) <= son }) != Set(b.filter { tarih($0) <= son })
        }
        if degisti(eski.purchases.map(\.beyanAlanlari), yeni.purchases.map(\.beyanAlanlari), { $0.date }) { return true }
        if degisti(eski.adjustments, yeni.adjustments, { $0.date }) { return true }
        if degisti(eski.counts, yeni.counts, { $0.date }) { return true }
        if Set(eski.sales.filter { $0.month <= ay }) != Set(yeni.sales.filter { $0.month <= ay }) { return true }
        if degisti(eski.expenses, yeni.expenses, { $0.date }) { return true }
        // Ürün maliyeti, reçete ve kanal oranları tarihlidir: değiştiyse geçmişe uzanıp uzanmadığına
        // ayın kâr rakamı karar verir
        return eski.products != yeni.products || eski.materials != yeni.materials || eski.channels != yeni.channels
    }
    /// Değişiklik kilitli bir ayı etkiliyorsa kullanıcıya gösterilecek açıklama
    /// `eskiMotor` / `yeniMotor` verilirse yeniden kurulmaz (mağaza zaten elinde tutuyor)
    public static func ihlal(eski: AppState, yeni: AppState,
                             eskiMotor: Engine? = nil, yeniMotor: Engine? = nil) -> String? {
        let aylar = eski.settings.ek.kilitli.intersection(yeni.settings.ek.kilitli)
        guard !aylar.isEmpty else { return nil }
        for ay in aylar.sorted() {
            // Dokunulmamış liste karşılaştırılmaz (aynı depolama: eşitlik hemen döner)
            func degisti<T: Hashable>(_ a: [T], _ b: [T], _ m: (T) -> MonthKey) -> Bool {
                a != b && Set(a.filter { m($0) == ay }) != Set(b.filter { m($0) == ay })
            }
            // Beyanı etkilemeyen bilgiler (hakediş, not, fatura dosyası, ad, tedarikçi) karşılaştırılmaz:
            // hakediş kilitten haftalar sonra gelir, fatura fotoğrafı sonradan eklenir
            if degisti(eski.sales, yeni.sales, \.month)
                || (eski.channelMonths != yeni.channelMonths
                    && degisti(eski.channelMonths.map(\.beyanAlanlari), yeni.channelMonths.map(\.beyanAlanlari), \.month))
                // Ödeme planı alımın ayına değil taksitin ödendiği aya aittir (aşağıda gider satırlarıyla bakılır)
                || (eski.purchases != yeni.purchases
                    && degisti(eski.purchases.map(\.beyanAlanlari), yeni.purchases.map(\.beyanAlanlari), { Dates.month(of: $0.date) }))
                || degisti(eski.adjustments, yeni.adjustments, { Dates.month(of: $0.date) })
                || degisti(eski.counts, yeni.counts, { Dates.month(of: $0.date) })
                // Taksit ve ayrı ödeme satırı yalnızca nakit hareketidir (KDV'si fatura/kayıt döneminde):
                // ödeme tarihini değiştirmek kilitli ayı bozmaz
                || Expenses.instances(eski, from: ay, to: ay).filter({ $0.sourceKind != .taksit && $0.sourceKind != .ayriOdeme }).map(\.beyanAlanlari)
                    != Expenses.instances(yeni, from: ay, to: ay).filter({ $0.sourceKind != .taksit && $0.sourceKind != .ayriOdeme }).map(\.beyanAlanlari) {
                return "\(Dates.displayMonth(ay)) kilitli (KDV beyanı verildi). Bu değişiklik o ayın kayıtlarını "
                    + "değiştiriyor; önce Raporlar → KDV kartından kilidi aç."
            }
        }
        // Kayıtlar aynı olsa da sonuç değişebilir: önceki ayın KDV'si devreden olarak kilitli aya geçer,
        // kanal ayarı ya da reçete geçmişe uzanabilir. Kilitli ayın beyan rakamları birebir korunur.
        // Yalnız beyan edilen KDV korunur: sonradan girilen bir alımın geçmiş satışa maliyet olarak
        // yansıması gibi KDV'yi değiştirmeyen düzeltmeler engellenmez.
        let e1 = eskiMotor ?? Engine(eski), e2 = yeniMotor ?? Engine(yeni)
        for ay in aylar.sorted() {
            if e1.vatStatus(ay) != e2.vatStatus(ay) {
                return "\(Dates.displayMonth(ay)) kilitli (KDV beyanı verildi). Bu değişiklik o ayın KDV'sini "
                    + "ya da sonucunu değiştiriyor (ör. önceki aydan devreden KDV); önce Finans & Vergiler → KDV'den kilidi aç."
            }
            // Kilitli ayın raporu da korunur: ortalama maliyet bütün geçmişten katlandığı için kilitli
            // aya kadar olan bir kaydı (ya da tarihli ürün/malzeme ayarını) düzenlemek o ayın satılan
            // malın maliyetini ve kârını değiştirir. KDV değişmese bile bu "geçmiş rapor değişmez"i bozar.
            // Sonradan girilen (ileri tarihli) bir alımın eksi stoğu maliyetlemesi bunun dışındadır:
            // o kayıt geçmişe dokunmaz, yalnız maliyeti bilinmeyen satışı maliyetler.
            guard gecmiseDokunuyor(eski: eski, yeni: yeni, ay: ay) else { continue }
            let r1 = e1.companyMonth(ay), r2 = e2.companyMonth(ay)
            if r1.gercekKar != r2.gercekKar || r1.toplamGider != r2.toplamGider || r1.gercekCiro != r2.gercekCiro {
                return "\(Dates.displayMonth(ay)) kilitli. Bu değişiklik o ayın kârını değiştiriyor "
                    + "(ör. daha eski bir alım ortalama maliyeti oynatıyor); önce Finans & Vergiler → KDV'den kilidi aç."
            }
        }
        return nil
    }
}
