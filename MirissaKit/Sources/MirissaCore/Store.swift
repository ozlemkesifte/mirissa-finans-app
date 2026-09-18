import Foundation
import Observation

/// Uygulamanın tek veri kaynağı.
///
/// Her değişiklikten sonra motor yeniden kurulur; bütün ekranlar
/// anında ve kendiliğinden doğru rakamı gösterir. Kayıt diske
/// gecikmeli ve atomik olarak yazılır.
@MainActor
@Observable
public final class AppStore {
    public private(set) var state: AppState
    public private(set) var engine: Engine
    public private(set) var loadError: String?

    private let file: FileStore
    private var saveTask: Task<Void, Never>?
    private let saveDelay: Duration

    /// Fatura eklerinin temizlik yapılacağı klasör. nil = uygulamanın klasörü.
    /// Testlerde her depo kendi klasörünü kullanır; aksi halde paralel çalışan
    /// testler birbirinin dosyalarını silebilir.
    private let ekKlasoru: URL?

    public init(file: FileStore = FileStore(), saveDelay: Duration = .milliseconds(400),
                attachmentsDirectory: URL? = nil) {
        self.file = file
        self.saveDelay = saveDelay
        // Veri dosyası uygulamanın kendi yerinde değilse (testler, yedek açma)
        // ekler de o dosyanın yanındaki klasörde aranır; ortak klasöre dokunulmaz.
        let dosyaKlasoru = file.url.deletingLastPathComponent()
        self.ekKlasoru = attachmentsDirectory
            ?? (file.url.standardizedFileURL == Persistence.defaultFile().standardizedFileURL
                ? nil : dosyaKlasoru)
        let loaded = file.load()
        self.loadError = loaded.error
        self.acilisHatasiYok = loaded.error == nil
        let s = loaded.state ?? SeedData.initialState()
        self.state = s
        self.engine = Engine(s)
        // Yalnızca dosya hiç yoksa başlangıç verisi yazılır. Dosya okunamadıysa
        // üstüne örnek veri yazılmaz: kullanıcı önce ne olduğunu görmeli.
        if loaded.state == nil && loaded.error == nil { scheduleSave() }
    }

    /// Testler için diske hiç dokunmayan sürüm
    public static func inMemory(_ s: AppState = SeedData.initialState()) -> AppStore {
        let kok = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mirissa-test-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(file: FileStore(url: kok.appendingPathComponent("veri.json")),
                             attachmentsDirectory: kok)
        store.replace(s)
        return store
    }

    // MARK: - Değişiklik

    public func mutate(_ block: (inout AppState) -> Void) {
        var s = state
        block(&s)
        guard s != state else { return }
        // KDV beyanı verilip kilitlenen aya dokunan değişiklik yapılmaz
        if let engel = AyKilidi.ihlal(eski: state, yeni: s) {
            sonHata = engel
            return
        }
        sonHata = nil
        let kayit = DegisiklikGunlugu.fark(eski: state, yeni: s)
        if !kayit.isEmpty {
            s.changeLog = Array((s.changeLog + kayit).suffix(DegisiklikGunlugu.enFazla))
        }
        apply(s)
    }

    /// Son değişiklik neden yapılamadı (ör. kilitli ay). Ekranda gösterilir.
    public var sonHata: String?
    public func hatayiKapat() { sonHata = nil }

    // MARK: - Yedek

    private var yedekKlasoru: URL {
        ekKlasoru.map { $0.appendingPathComponent("Yedekler", isDirectory: true) } ?? Backup.varsayilanKlasor()
    }

    private func ekURL(_ ad: String) -> URL {
        ekKlasoru.map { $0.appendingPathComponent("ekler").appendingPathComponent(ad) } ?? AttachmentStore.url(ad)
    }

    /// Bütün kayıtlar ve fatura ekleri tek dosyada
    public func yedekPaketi() throws -> Data { try Backup.paket(state, ekURL: ekURL) }

    /// Yedek dosyası telefon dışına kaydedildi (paylaşıldı)
    public func yedekPaylasildi(_ gun: DateKey = Dates.today()) {
        mutate { $0.settings.ek.sonYedekPaylasim = gun }
    }

    /// Günde bir otomatik yedek. Veri dosyası açılamadıysa alınmaz (boş veriyi yedeklemesin).
    public func otomatikYedekGerekirse(_ gun: DateKey = Dates.today()) {
        guard acilisHatasiYok, state.settings.ek.sonOtomatikYedek != gun else { return }
        guard (try? Backup.otomatikYedekAl(state, ekURL: ekURL, klasor: yedekKlasoru, gun: gun)) != nil else { return }
        var s = state
        s.settings.ek.sonOtomatikYedek = gun
        apply(s)
    }

    public var otomatikYedekler: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: yedekKlasoru, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("mirissa-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    public func yedegiOku(_ data: Data) throws -> BackupPreview { try Backup.oku(data) }

    /// Yedeği geri yükler. Önce şu anki verinin bir kopyası alınır; geri alınabilsin.
    public func geriYukle(_ p: BackupPreview, gun: DateKey = Dates.today()) throws {
        try Backup.otomatikYedekAl(state, ekURL: ekURL, klasor: yedekKlasoru, gun: gun,
                                   onEk: "geri-yukleme-oncesi", sakla: 5)
        let hedef = ekKlasoru.map { $0.appendingPathComponent("ekler", isDirectory: true) }
            ?? AttachmentStore.directory()
        try FileManager.default.createDirectory(at: hedef, withIntermediateDirectories: true)
        for (ad, veri) in p.ekler {
            try veri.write(to: hedef.appendingPathComponent(ad), options: .atomic)
        }
        var s = p.state
        s.changeLog = Array((s.changeLog + [ChangeLogEntry(
            zaman: ISO8601DateFormatter().string(from: Date()), tur: .geriYuklendi, alan: "Yedek",
            aciklama: "Yedekten geri yüklendi (\(p.gun ?? "tarihsiz"))")]).suffix(DegisiklikGunlugu.enFazla))
        apply(s)
    }

    public func replace(_ s: AppState) { apply(s) }

    private func apply(_ s: AppState) {
        state = s
        engine = Engine(s)
        kullaniciDegistirdi = true
        scheduleSave()
    }

    /// Açılıştan beri kullanıcı bir şey değiştirdi mi. Dosya okunamadıysa,
    /// kullanıcı bir şey yapmadan dosyanın üstüne yazılmaz.
    private var kullaniciDegistirdi = false

    // MARK: - Kayıt

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = state
        saveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.saveDelay)
            guard !Task.isCancelled else { return }
            self.writeNow(snapshot)
        }
    }

    /// Uygulama arka plana geçerken beklemeden yaz
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        // Veri dosyası açılamadıysa ve kullanıcı henüz bir şey girmediyse,
        // arka plana geçerken örnek veri asıl dosyanın üstüne yazılmaz.
        guard acilisHatasiYok || kullaniciDegistirdi else { return }
        writeNow(state)
    }

    private var acilisHatasiYok = true

    private func writeNow(_ s: AppState) {
        do { try file.save(s) } catch { loadError = String(describing: error) }
    }

    public var storageURL: URL { file.url }

    // MARK: - Malzeme

    public func addMaterial(_ m: StockMaterial) {
        var yeni = m
        if yeni.perOrder == nil, StockMaterial.koliMi(yeni.name) { yeni.perOrder = true }
        mutate { $0.materials.append(yeni) }
    }

    public func updateMaterial(_ m: StockMaterial) {
        mutate { s in
            if let i = s.materials.firstIndex(where: { $0.id == m.id }) { s.materials[i] = m }
        }
    }

    /// Malzemeyi siler ve ona bağlı reçete satırları ile hareketleri temizler.
    public func deleteMaterial(_ id: Id) {
        mutate { s in
            s.materials.removeAll { $0.id == id }
            for i in s.products.indices { s.products[i].recipe.removeAll { $0.materialId == id } }
            s.purchases.removeAll { $0.item == .material(id) }
            s.adjustments.removeAll { $0.item == .material(id) }
            s.counts.removeAll { $0.item == .material(id) }
        }
    }

    // MARK: - Ürün

    public func addProduct(_ p: Product) { mutate { $0.products.append(p) } }

    public func updateProduct(_ p: Product) {
        mutate { s in
            if let i = s.products.firstIndex(where: { $0.id == p.id }) { s.products[i] = p }
        }
    }

    public func deleteProduct(_ id: Id) {
        mutate { s in
            s.products.removeAll { $0.id == id }
            for i in s.products.indices { s.products[i].components.removeAll { $0.productId == id } }
            s.sales.removeAll { $0.productId == id }
            s.purchases.removeAll { $0.item == .product(id) }
            s.adjustments.removeAll { $0.item == .product(id) }
            s.counts.removeAll { $0.item == .product(id) }
        }
    }

    // MARK: - Kanal

    public func addChannel(_ c: Channel) { mutate { $0.channels.append(c) } }

    /// Kanal düzenlemesi. Kesinti oranlarının tek bir gerçek kaynağı vardır:
    /// tarihçe. Düz alanlar üzerinden bir oran değiştirilirse bu, bugünden
    /// geçerli yeni bir tarihçe kaydına çevrilir — aksi halde ekranda yeni
    /// oran görünürken motor eskisini kullanmaya devam ederdi.
    public func updateChannel(_ c: Channel) {
        mutate { s in
            guard let i = s.channels.firstIndex(where: { $0.id == c.id }) else { return }
            let eski = s.channels[i]
            var yeni = c
            if Self.oranlarDegisti(eski, c) {
                // Tarihçeyi koru, değişikliği bugünden başlat. Tarihçe hiç yoksa
                // eski oranlar başlangıç kaydı olarak saklanır; geçmiş aylar değişmez.
                var gecmis = eski
                let bugunku = eski.currentRates
                gecmis.setRates(ChannelRates(
                    from: Dates.today(),
                    commissionPct: c.commissionPct,
                    paymentPct: c.paymentPct,
                    shippingPerOrder: c.shippingPerOrder,
                    serviceFeePerOrder: c.serviceFeePerOrder,
                    platformFeeMonthly: c.platformFeeMonthly,
                    otherDeductionPct: c.otherDeductionPct,
                    otherDeductionMonthly: c.otherDeductionMonthly,
                    extras: bugunku.extras,
                    unknownFields: bugunku.unknownFields
                ))
                yeni.rateHistory = gecmis.rateHistory
                yeni.commissionPct = gecmis.commissionPct
                yeni.paymentPct = gecmis.paymentPct
                yeni.shippingPerOrder = gecmis.shippingPerOrder
                yeni.serviceFeePerOrder = gecmis.serviceFeePerOrder
                yeni.platformFeeMonthly = gecmis.platformFeeMonthly
                yeni.otherDeductionPct = gecmis.otherDeductionPct
                yeni.otherDeductionMonthly = gecmis.otherDeductionMonthly
            }
            s.channels[i] = yeni
        }
    }

    private static func oranlarDegisti(_ a: Channel, _ b: Channel) -> Bool {
        a.commissionPct != b.commissionPct
            || a.paymentPct != b.paymentPct
            || a.shippingPerOrder != b.shippingPerOrder
            || a.serviceFeePerOrder != b.serviceFeePerOrder
            || a.platformFeeMonthly != b.platformFeeMonthly
            || a.otherDeductionPct != b.otherDeductionPct
            || a.otherDeductionMonthly != b.otherDeductionMonthly
    }

    public func deleteChannel(_ id: Id) {
        mutate { s in
            s.channels.removeAll { $0.id == id }
            s.sales.removeAll { $0.channelId == id }
            s.channelMonths.removeAll { $0.channelId == id }
            for i in s.expenses.indices where s.expenses[i].scope.channelId == id {
                s.expenses[i].scope = .ortak
            }
        }
    }

    public func upsertChannelMonth(_ cm: ChannelMonth) {
        mutate { s in
            if let i = s.channelMonths.firstIndex(where: {
                $0.month == cm.month && $0.channelId == cm.channelId
            }) {
                if cm.isEmpty { s.channelMonths.remove(at: i) } else { s.channelMonths[i] = cm }
            } else if !cm.isEmpty {
                s.channelMonths.append(cm)
            }
        }
    }

    // MARK: - Satış

    public func addSale(_ e: SalesEntry) { mutate { $0.sales.append(e) } }

    public func updateSale(_ e: SalesEntry) {
        mutate { s in
            if let i = s.sales.firstIndex(where: { $0.id == e.id }) { s.sales[i] = e }
        }
    }

    public func deleteSale(_ id: Id) { mutate { $0.sales.removeAll { $0.id == id } } }

    // MARK: - Gider

    public func addExpense(_ e: Expense) { mutate { $0.expenses.append(e) } }

    public func updateExpense(_ e: Expense) {
        mutate { s in
            if let i = s.expenses.firstIndex(where: { $0.id == e.id }) { s.expenses[i] = e }
        }
    }

    public func deleteExpense(_ id: Id) {
        mutate { $0.expenses.removeAll { $0.id == id } }
        pruneAttachments()
    }

    /// Faturayı kaydeder ve gidere bağlar. Düzenli giderlerde `month` verilirse
    /// fatura sadece o aya bağlanır.
    public func attachInvoice(data: Data, ext: String, toExpense id: Id, month: MonthKey? = nil) {
        guard let name = try? AttachmentStore.save(data: data, suggestedExtension: ext) else { return }
        mutate { s in
            guard let i = s.expenses.firstIndex(where: { $0.id == id }) else { return }
            if let month, s.expenses[i].isRecurring {
                var ov = s.expenses[i].overrides[month] ?? ExpenseOverride()
                AttachmentStore.delete(ov.attachment)
                ov.attachment = name
                s.expenses[i].overrides[month] = ov
            } else {
                AttachmentStore.delete(s.expenses[i].attachment)
                s.expenses[i].attachment = name
            }
        }
    }

    public func removeInvoice(fromExpense id: Id, month: MonthKey? = nil) {
        mutate { s in
            guard let i = s.expenses.firstIndex(where: { $0.id == id }) else { return }
            if let month, var ov = s.expenses[i].overrides[month], ov.attachment != nil {
                ov.attachment = nil
                s.expenses[i].overrides[month] = ov.isEmpty ? nil : ov
            } else {
                s.expenses[i].attachment = nil
            }
        }
        pruneAttachments()
    }

    public func attachInvoice(data: Data, ext: String, toPurchase id: Id) {
        guard let name = try? AttachmentStore.save(data: data, suggestedExtension: ext) else { return }
        mutate { s in
            guard let i = s.purchases.firstIndex(where: { $0.id == id }) else { return }
            AttachmentStore.delete(s.purchases[i].attachment)
            s.purchases[i].attachment = name
        }
    }

    public func removeInvoice(fromPurchase id: Id) {
        mutate { s in
            if let i = s.purchases.firstIndex(where: { $0.id == id }) { s.purchases[i].attachment = nil }
        }
        pruneAttachments()
    }

    /// Hiçbir kayda bağlı olmayan fatura dosyalarını temizler
    public func pruneAttachments() {
        AttachmentStore.prune(keeping: state.attachmentNames, in: ekKlasoru)
    }

    /// Düzenli gideri durdurur: geçmiş aylar olduğu gibi kalır.
    public func stopExpense(_ id: Id, lastMonth: MonthKey) {
        mutate { s in
            if let i = s.expenses.firstIndex(where: { $0.id == id }) { s.expenses[i].endMonth = lastMonth }
        }
    }

    public func resumeExpense(_ id: Id) {
        mutate { s in
            if let i = s.expenses.firstIndex(where: { $0.id == id }) { s.expenses[i].endMonth = nil }
        }
    }

    /// Sadece bir ayın tutarını değiştirir, diğer aylar etkilenmez.
    public func overrideExpense(_ id: Id, month: MonthKey, amount: Kurus?, skipped: Bool = false,
                                vatRate: VatRate? = nil, vatIncluded: Bool? = nil) {
        mutate { s in
            guard let i = s.expenses.firstIndex(where: { $0.id == id }) else { return }
            var ov = s.expenses[i].overrides[month] ?? ExpenseOverride()
            ov.amount = amount
            ov.skipped = skipped
            ov.vatRate = vatRate
            ov.vatIncluded = vatIncluded
            s.expenses[i].overrides[month] = ov.isEmpty ? nil : ov
        }
    }

    // MARK: - Stok

    public func addPurchase(_ p: StockPurchase) { mutate { $0.purchases.append(p) } }

    public func updatePurchase(_ p: StockPurchase) {
        mutate { s in
            if let i = s.purchases.firstIndex(where: { $0.id == p.id }) { s.purchases[i] = p }
        }
    }

    public func deletePurchase(_ id: Id) {
        mutate { $0.purchases.removeAll { $0.id == id } }
        pruneAttachments()
    }

    public func addAdjustment(_ a: StockAdjustment) { mutate { $0.adjustments.append(a) } }

    public func updateAdjustment(_ a: StockAdjustment) {
        mutate { s in
            if let i = s.adjustments.firstIndex(where: { $0.id == a.id }) { s.adjustments[i] = a }
        }
    }

    public func deleteAdjustment(_ id: Id) { mutate { $0.adjustments.removeAll { $0.id == id } } }

    public func addCount(_ c: StockCount) { mutate { $0.counts.append(c) } }

    public func deleteCount(_ id: Id) { mutate { $0.counts.removeAll { $0.id == id } } }

    /// Bir hareketi kaynağından siler (geçmiş ekranındaki "sil" için)
    public func deleteMovementSource(_ row: LedgerRow) {
        switch row.movement.source {
        case .purchase: deletePurchase(row.movement.sourceId)
        case .adjustment: deleteAdjustment(row.movement.sourceId)
        case .count: deleteCount(row.movement.sourceId)
        case .sales: deleteSale(row.movement.sourceId)
        case .opening: break
        }
    }

    // MARK: - Alacak / Ödenecek

    public func addBalance(_ b: BalanceItem) { mutate { $0.balances.append(b) } }

    public func updateBalance(_ b: BalanceItem) {
        mutate { s in
            if let i = s.balances.firstIndex(where: { $0.id == b.id }) { s.balances[i] = b }
        }
    }

    public func deleteBalance(_ id: Id) { mutate { $0.balances.removeAll { $0.id == id } } }

    /// Tahsil edildi / ödendi olarak işaretler
    public func settleBalance(_ id: Id, settled: Bool = true) {
        mutate { s in
            if let i = s.balances.firstIndex(where: { $0.id == id }) { s.balances[i].settled = settled }
        }
    }

    public func setVatEnabled(_ on: Bool) { mutate { $0.settings.vatEnabled = on } }

    public func completeSetup() { mutate { $0.settings.setupCompleted = true } }

    /// Sihirbazı yeniden çalıştırmak için (Ayarlar'dan)
    public func restartSetup() { mutate { $0.settings.setupCompleted = false } }

    /// "Değişiklik yok" — fiyatlara dokunmaz, yalnızca son kontrol gününü işaretler.
    public func markPriceCheck(_ day: DateKey = Dates.today()) {
        mutate { $0.settings.lastPriceCheck = day }
    }

    public func setYearlyProfitGoal(_ amount: Kurus?, for year: Int) {
        mutate { s in
            if let a = amount, a > 0 { s.settings.yearlyProfitGoals["\(year)"] = a }
            else { s.settings.yearlyProfitGoals["\(year)"] = nil }
        }
    }

    /// Kanalı ekler veya günceller. Oran tarihçesi korunur.
    public func upsertChannel(_ c: Channel) {
        mutate { s in
            if let i = s.channels.firstIndex(where: { $0.id == c.id }) { s.channels[i] = c }
            else { s.channels.append(c) }
        }
    }

    /// Kanala yeni tarihli kesinti seti ekler; eski oranlar silinmez.
    /// `soldProductIds` verilirse o kanalda satılan SKU listesi de kaydedilir —
    /// sistem böylece satılmayan ürün-kanal ikilileri için fiyat sormaz.
    public func applyChannelRates(_ channelId: Id, _ rates: ChannelRates,
                                  soldProductIds: [Id]? = nil) {
        mutate { s in
            guard let i = s.channels.firstIndex(where: { $0.id == channelId }) else { return }
            var c = s.channels[i]
            c.setRates(rates)
            c.setupCompleted = true
            c.archived = false
            if let soldProductIds { c.soldProductIds = soldProductIds }
            s.channels[i] = c
        }
    }

    // MARK: - Yarım kalan akışlar

    /// Her adımda çağrılır. Aynı akışın önceki kaydının üzerine yazar,
    /// başka akışların kaydına dokunmaz.
    public func saveDraft(_ d: WizardDraft) {
        mutate { s in
            if let i = s.drafts.firstIndex(where: { $0.id == d.id }) { s.drafts[i] = d }
            else { s.drafts.append(d) }
        }
    }

    public func draft(_ kind: WizardKind, subjectId: Id? = nil) -> WizardDraft? {
        let anahtar = "\(kind.rawValue)#\(subjectId ?? "-")"
        return state.drafts.first { $0.id == anahtar }
    }

    /// Akış tamamlandığında veya kullanıcı sildiğinde çağrılır.
    public func clearDraft(_ kind: WizardKind, subjectId: Id? = nil) {
        let anahtar = "\(kind.rawValue)#\(subjectId ?? "-")"
        guard state.drafts.contains(where: { $0.id == anahtar }) else { return }
        mutate { $0.drafts.removeAll { $0.id == anahtar } }
    }

    public func clearDraft(id: String) {
        guard state.drafts.contains(where: { $0.id == id }) else { return }
        mutate { $0.drafts.removeAll { $0.id == id } }
    }

    /// Yaklaşık satış dağılımı — yalnızca kullanıcı onayladığında kaydedilir.
    public func setSalesMix(_ mix: SalesMix) {
        mutate { $0.settings.salesMix = mix }
    }

    public func setAdKeepPerOrder(_ tutar: Kurus?) {
        mutate { $0.settings.adKeepPerOrder = tutar }
    }

    public func setPriceCheckInterval(_ i: PriceCheckInterval) {
        mutate { $0.settings.priceCheckInterval = i }
    }

    public func setVatDefaults(rate: VatRate, included: Bool) {
        mutate { s in
            s.settings.defaultVatRate = rate
            s.settings.defaultVatIncluded = included
        }
    }

    // MARK: - Ayarlar ve yedekleme

    public func updateSettings(_ s: AppSettings) { mutate { $0.settings = s } }

    /// "Satışlar şu tarihe kadar girildi" işareti. `nil` işareti kaldırır
    /// ve girilen satışlar ayın tamamı sayılır.
    public func setProgressAsOf(_ date: DateKey?, for month: MonthKey) {
        mutate { s in
            if let d = date { s.settings.progressAsOf[month] = d }
            else { s.settings.progressAsOf[month] = nil }
        }
    }

    public func setExpectedMix(_ mix: ExpectedMix?) {
        mutate { $0.settings.expectedMix = mix }
    }

    /// Aya özel kâr hedefi. `nil` hedefi kaldırır.
    public func setProfitGoal(_ amount: Kurus?, for month: MonthKey) {
        mutate { s in
            if let a = amount, a > 0 { s.settings.profitGoals[month] = a }
            else { s.settings.profitGoals[month] = nil }
        }
    }

    public func resetToSeed() {
        apply(SeedData.initialState())
        pruneAttachments()
    }

    public func eraseAllData() {
        var s = state
        s.sales = []
        s.expenses = []
        s.purchases = []
        s.adjustments = []
        s.counts = []
        s.channelMonths = []
        s.balances = []
        apply(s)
        pruneAttachments()
    }

    public func exportJSON() throws -> Data { try Persistence.encode(state) }

    public func importJSON(_ data: Data) throws {
        apply(try Persistence.decode(data))
    }
}
