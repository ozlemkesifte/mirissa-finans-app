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
        // Reçete / set içeriği değiştiyse geçmiş aylar eski haliyle hesaplanır
        s.receteGecmisiniKoru(eski: state, bugun: Dates.today())
        s.kanalArsivDonemleriniKoru(eski: state, buAy: Dates.currentMonth())
        s.malzemeGecmisiniKoru(eski: state, bugun: Dates.today())
        let kayit = DegisiklikGunlugu.fark(eski: state, yeni: s)
        if !kayit.isEmpty {
            s.changeLog = Array((s.changeLog + kayit).suffix(DegisiklikGunlugu.enFazla))
        }
        // KDV beyanı verilip kilitlenen aya dokunan değişiklik yapılmaz. Yeni motor bir kez kurulur:
        // kilit kontrolünün hesapladıkları, değişiklik uygulanınca da kullanılır.
        let yeniMotor = Engine(s)
        if let engel = AyKilidi.ihlal(eski: state, yeni: s, eskiMotor: engine, yeniMotor: yeniMotor) {
            sonHata = engel
            return
        }
        sonHata = nil
        apply(s, motor: yeniMotor)
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
        // Yedekte olmayan eski ekler diskte kalmasın
        pruneAttachments()
    }

    public func replace(_ s: AppState) { apply(s) }

    private func apply(_ s: AppState, motor: Engine? = nil) {
        state = s
        engine = motor ?? Engine(s)
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

    /// Satıştan kaldır: geçmiş satışlar, stok ve raporlar olduğu gibi kalır;
    /// ürün listelerde, hedeflerde ve yeni girişlerde görünmez. Geri alınabilir.
    public func setProductArchived(_ id: Id, _ arsiv: Bool) {
        mutate { s in
            if let i = s.products.firstIndex(where: { $0.id == id }) { s.products[i].archived = arsiv }
        }
    }

    public func setChannelArchived(_ id: Id, _ arsiv: Bool) {
        mutate { s in
            if let i = s.channels.firstIndex(where: { $0.id == id }) { s.channels[i].archived = arsiv }
        }
    }

    public func setMaterialArchived(_ id: Id, _ arsiv: Bool) {
        mutate { s in
            if let i = s.materials.firstIndex(where: { $0.id == id }) { s.materials[i].archived = arsiv }
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
            // Stopaj ayarı dönemlere işlenir: değişiklik bu aydan başlar, geçmiş aylar korunur
            if eski.stopajAcik != c.stopajAcik || eski.stopajPct != c.stopajPct
                || eski.stopajBaslangic != c.stopajBaslangic {
                yeni.stopajDonemleri = StopajDonemi.guncelle(eski: eski, yeni: c, buAy: Dates.currentMonth())
            }
            let tabanDegisti = (eski.komisyonKdvHaric ?? false) != (c.komisyonKdvHaric ?? false)
                || (eski.odemeKesintisiBsmv ?? false) != (c.odemeKesintisiBsmv ?? false)
            let kdvDegisti = eski.resolvedFeeVatRate != c.resolvedFeeVatRate
                || eski.resolvedFeesIncludeVat != c.resolvedFeesIncludeVat
            let ayarDegisti = tabanDegisti || kdvDegisti
            let oranDegisti = Self.oranlarDegisti(eski, c)
            if ayarDegisti || oranDegisti {
                // Tarihçe korunur, değişiklik bugünden başlar; geçmiş aylar değişmez. Kanal hiç
                // kurulmamışsa ilk girilen ayarlar baştan geçerlidir (kurulum akışı da böyle yapar).
                var gecmis = eski
                var kayit = eski.currentRates
                kayit.id = Ids.make(.channelRate)
                kayit.from = eski.hicKurulmamis ? "1970-01-01" : Dates.today()
                if oranDegisti {
                    kayit.commissionPct = c.commissionPct
                    kayit.paymentPct = c.paymentPct
                    kayit.shippingPerOrder = c.shippingPerOrder
                    kayit.serviceFeePerOrder = c.serviceFeePerOrder
                    kayit.platformFeeMonthly = c.platformFeeMonthly
                    kayit.otherDeductionPct = c.otherDeductionPct
                    kayit.otherDeductionMonthly = c.otherDeductionMonthly
                }
                if ayarDegisti {
                    kayit.komisyonKdvHaric = c.komisyonKdvHaric ?? false
                    kayit.odemeKesintisiBsmv = c.odemeKesintisiBsmv ?? false
                    kayit.feeVatRate = c.resolvedFeeVatRate
                    kayit.feesIncludeVat = c.resolvedFeesIncludeVat
                }
                gecmis.setRates(kayit)
                if ayarDegisti {
                    // Önceki kayıtlar kanalın eski ayarını kalıcı olarak taşır; yoksa yeni ayarı devralırlardı
                    gecmis.rateHistory = gecmis.rateHistory?.map { $0.ayarlariSabitle(eski) }
                }
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

    /// Hakediş farkını "diğer kesinti" olarak kaydeder: beklenen yatan tutara eşitlenir
    public func hakedisFarkiniKesintiyeYaz(month: MonthKey, channelId: Id) {
        guard let k = engine.hakedis(month: month, channelId: channelId), k.fark != 0 else { return }
        let r = engine.channelResult(channelId: channelId, month: month)
        var cm = state.channelMonth(month: month, channelId: channelId)
            ?? ChannelMonth(month: month, channelId: channelId)
        let mevcut = cm.otherDeductionActual ?? engine.kesintiBrut(r.otherDeduction.amount, channelId: channelId, month: month)
        cm.otherDeductionActual = max(mevcut + engine.kesintiGirisi(brutFark: k.fark, channelId: channelId, month: month), 0)
        upsertChannelMonth(cm)
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

    /// "Her ay" girilmiş ama aslında yılda bir ödenen gider: tutar yıllık ödeme sayılır,
    /// kâra her ay 1/12'si yazılır. Yalnızca ödeme aylarına (yıldönümü) ait aya özel tutarlar korunur.
    public func giderYillikYap(_ id: Id) {
        mutate { s in
            guard let i = s.expenses.firstIndex(where: { $0.id == id }),
                  s.expenses[i].recurrence == .aylik else { return }
            let e = s.expenses[i]
            s.expenses[i].recurrence = .yillik
            s.expenses[i].overrides = e.overrides.filter { e.yillikOdemeAyi($0.key) == $0.key }
        }
    }

    /// Tek seferlik gideri kâra `ay` aya bölerek yazar (1 = tamamı ödendiği ay)
    public func giderAylaraBol(_ id: Id, ay: Int) {
        mutate { s in
            guard let i = s.expenses.firstIndex(where: { $0.id == id }),
                  s.expenses[i].recurrence == .tek else { return }
            s.expenses[i].yayilanAy = ay > 1 ? ay : nil
        }
    }

    /// Düzenli giderin değişikliği `ay`dan itibaren geçerli olsun: eski gider bir önceki ayda
    /// biter, yenisi o aydan başlar; geçmiş aylar değişmez. Yeni giderin kimliğini döndürür.
    @discardableResult
    public func giderGuncelleAydanItibaren(_ yeni: Expense, ay: MonthKey) -> Id {
        var sonuc = yeni.id
        mutate { s in
            guard let i = s.expenses.firstIndex(where: { $0.id == yeni.id }) else { return }
            var eski = s.expenses[i]
            // Başlangıç ayından itibaren değişiyorsa bölmeye gerek yok: tamamı yeni haliyle
            guard eski.isRecurring, ay > eski.startMonth else {
                s.expenses[i] = yeni
                return
            }
            // Durdurulmuş gider: o aydan sonra ayı yok. Geçmiş değişmesin diye yalnızca
            // hesaba girmeyen bilgiler (tedarikçi, fatura no) güncellenir.
            if let son = eski.endMonth, son < ay {
                eski.vendor = yeni.vendor
                eski.invoiceNo = yeni.invoiceNo
                s.expenses[i] = eski
                return
            }
            // Hesaba giren hiçbir şey değişmediyse bölmeye gerek yok (ad, tedarikçi gibi bilgiler yerinde güncellenir)
            if yeni.amount == eski.amount, yeni.resolvedVatRate == eski.resolvedVatRate,
               yeni.resolvedVatIncluded == eski.resolvedVatIncluded, yeni.category == eski.category,
               yeni.scope == eski.scope, yeni.resolvedBehavior == eski.resolvedBehavior,
               yeni.recurrence == eski.recurrence {
                var guncel = yeni
                guncel.date = eski.date
                s.expenses[i] = guncel
                return
            }
            var yeniHali = yeni
            yeniHali.endMonth = eski.endMonth
            let parca = eski.bol(ay: ay, yeniHali: yeniHali)
            s.expenses[i] = parca.eski
            s.expenses.append(parca.devam)
            sonuc = parca.devam.id
        }
        return sonuc
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
                ov.attachment = name
                s.expenses[i].overrides[month] = ov
            } else {
                s.expenses[i].attachment = name
            }
        }
        eskiFaturalariTemizle(yeni: name)
    }

    /// Fatura değiştikten sonra: değişiklik reddedildiyse (kilitli ay) yeni dosya silinir; kabul
    /// edildiyse hiçbir kayda bağlı olmayan eski dosyalar temizlenir. Eski dosya kayıt kaydedilmeden
    /// silinmez ve başka bir kayıt (bölünmüş giderin geçmiş parçası) hâlâ kullanıyorsa kalır.
    private func eskiFaturalariTemizle(yeni name: String) {
        if !state.attachmentNames.contains(name) {
            AttachmentStore.delete(name)
        } else {
            pruneAttachments()
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
            s.purchases[i].attachment = name
        }
        eskiFaturalariTemizle(yeni: name)
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

    /// Durdurulan gideri yeniden başlatır. Aradaki aylar geriye dönük eklenmez:
    /// durdurulduğu ay geçtiyse gider bu aydan itibaren devam eden yeni bir kayıt olur.
    public func resumeExpense(_ id: Id, buAy: MonthKey = Dates.currentMonth()) {
        mutate { s in
            // Devamı olan (bölünmüş) parça yeniden başlatılmaz; devamı silindiyse başlatılabilir
            guard let i = s.expenses.firstIndex(where: { $0.id == id }),
                  !s.expenses.contains(where: { $0.id == s.expenses[i].devamId }),
                  let son = s.expenses[i].endMonth else { return }
            s.expenses[i].devamId = nil
            // Yıllık gider ödenmiş yılın içinde yeniden başlatılıyorsa eski düzenle devam eder:
            // o yıl zaten ödendi, bir sonraki ödeme yıldönümünde (bu aya yeni ödeme yazılmaz)
            let e = s.expenses[i]
            if e.recurrence == .yillik, buAy <= Dates.addMonths(e.yillikOdemeAyi(son), 11) {
                s.expenses[i].endMonth = nil
                return
            }
            if son >= Dates.addMonths(buAy, -1) {
                s.expenses[i].endMonth = nil
                return
            }
            // Yıllık giderde bir sonraki ödeme bu aydan başlar; durdurulduğu ay korunur
            var devamHali = s.expenses[i]
            devamHali.endMonth = nil
            var parca = s.expenses[i].bol(ay: buAy, yeniHali: devamHali)
            parca.eski.endMonth = son
            s.expenses[i] = parca.eski
            s.expenses.append(parca.devam)
        }
    }

    /// Sadece bir ayın tutarını değiştirir, diğer aylar etkilenmez.
    public func overrideExpense(_ id: Id, month: MonthKey, amount: Kurus?, skipped: Bool = false,
                                vatRate: VatRate? = nil, vatIncluded: Bool? = nil, name: String? = nil) {
        mutate { s in
            guard let i = s.expenses.firstIndex(where: { $0.id == id }) else { return }
            var ov = s.expenses[i].overrides[month] ?? ExpenseOverride()
            ov.amount = amount
            if let name { ov.name = name == s.expenses[i].name ? nil : name }
            ov.skipped = skipped
            ov.vatRate = vatRate
            ov.vatIncluded = vatIncluded
            s.expenses[i].overrides[month] = ov.isEmpty ? nil : ov
        }
    }

    // MARK: - Stok

    public func addPurchase(_ p: StockPurchase) { mutate { $0.purchases.append(p) } }

    /// Vadeli alımın taksiti ödendi (ya da ödeme geri alındı: tarih nil)
    public func taksitOdendi(purchaseId: Id, taksitId: Id, tarih: DateKey?) {
        mutate { s in
            guard let i = s.purchases.firstIndex(where: { $0.id == purchaseId }),
                  let j = s.purchases[i].odeme?.taksitler.firstIndex(where: { $0.id == taksitId }) else { return }
            s.purchases[i].odeme?.taksitler[j].odemeTarihi = tarih
        }
    }

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

    public func updateCount(_ c: StockCount) {
        mutate { s in
            guard let i = s.counts.firstIndex(where: { $0.id == c.id }) else { return }
            s.counts[i] = c
        }
    }

    /// İşletmenin adı (ana ekranın başlığı). Boş bırakılırsa değişmez.
    public func setCompanyName(_ ad: String) {
        let temiz = ad.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !temiz.isEmpty else { return }
        mutate { $0.settings.companyName = temiz }
    }

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
    /// Sonradan eklenen ayarları değiştirir (vergi, nakit, kilit, hatırlatma…)
    public func ekAyarla(_ block: (inout EkAyarlar) -> Void) {
        mutate { block(&$0.settings.ek) }
    }

    /// KDV beyanı verilen ayı kilitler ya da kilidi açar
    public func ayKilidi(_ month: MonthKey, kilitli: Bool) {
        var s = state
        var liste = Set(s.settings.ek.kilitliAylar ?? [])
        if kilitli { liste.insert(month) } else { liste.remove(month) }
        s.settings.ek.kilitliAylar = liste.isEmpty ? nil : liste.sorted()
        s.changeLog = Array((s.changeLog + [ChangeLogEntry(
            zaman: ISO8601DateFormatter().string(from: Date()), tur: .degisti, alan: "Ay kilidi",
            aciklama: "\(Dates.displayMonth(month)) " + (kilitli ? "kilitlendi" : "kilidi açıldı"))])
            .suffix(DegisiklikGunlugu.enFazla))
        apply(s)
    }

    /// Ay sonu listesinde elle işaretlenen madde
    public func aySonuIsaretle(_ month: MonthKey, _ madde: String, _ tamam: Bool) {
        ekAyarla { ek in
            var liste = Set(ek.aySonuIsaretleri?[month] ?? [])
            if tamam { liste.insert(madde) } else { liste.remove(madde) }
            var hepsi = ek.aySonuIsaretleri ?? [:]
            hepsi[month] = liste.isEmpty ? nil : liste.sorted()
            ek.aySonuIsaretleri = hepsi.isEmpty ? nil : hepsi
        }
    }

    /// İçe aktarılan raporu kaydeder. Aynı kanalın aynı aylarındaki eski satışlar
    /// raporla değiştirilir (aynı rapor iki kez aktarılırsa satışlar ikiye katlanmasın).
    public func raporuKaydet(_ sonuc: RaporIceAktarma.Sonuc, kanalId: Id) {
        // Daha önce rapor aktarılmış aylarda eski satışlar silinmez, yeni siparişler eklenir
        let aylar = Set(sonuc.aylarListesi).subtracting(sonuc.eklenenAylar)
        mutate { s in
            s.sales.removeAll { $0.channelId == kanalId && aylar.contains($0.month) }
            // Kanalın satırları ay + ürün başına bir kez dizinlenir (her kalem için bütün satışlar taranmaz)
            var dizin: [String: [Int]] = [:]
            for i in s.sales.indices where s.sales[i].channelId == kanalId {
                dizin["\(s.sales[i].month)|\(s.sales[i].productId)", default: []].append(i)
            }
            func satirlar(_ e: SalesEntry) -> [Int] { dizin["\(e.month)|\(e.productId)"] ?? [] }
            // Eklenen aylarda aynı ürünün satırı varsa onunla birleştirilir (ayrı satır "iki kez
            // girilmiş olabilir" uyarısı verirdi); aynı KDV oranında olmayan satır ayrı kalır
            for yeni in sonuc.satislar {
                if sonuc.eklenenAylar.contains(yeni.month),
                   let i = satirlar(yeni).first(where: {
                       s.sales[$0].resolvedVatRate == yeni.resolvedVatRate
                           && s.sales[$0].resolvedVatIncluded == yeni.resolvedVatIncluded
                   }) {
                    s.sales[i].qty += yeni.qty
                    s.sales[i].grossSales += yeni.grossSales
                    s.sales[i].discount += yeni.discount
                    s.sales[i].returnsQty += yeni.returnsQty
                    s.sales[i].returnsAmount += yeni.returnsAmount
                } else {
                    s.sales.append(yeni)
                    dizin["\(yeni.month)|\(yeni.productId)", default: []].append(s.sales.count - 1)
                }
            }
            // Önceki aktarımda alınıp sonradan iade edilen siparişlerin iadesi aynı ay ve ürüne eklenir
            for g in sonuc.iadeEklenecek {
                guard let i = satirlar(g).max(by: { s.sales[$0].qty < s.sales[$1].qty }) else { continue }
                s.sales[i].returnsQty = min(s.sales[i].returnsQty + g.returnsQty, s.sales[i].qty)
                s.sales[i].returnsAmount = min(s.sales[i].returnsAmount + g.returnsAmount,
                                               s.sales[i].grossSales - s.sales[i].discount)
            }
            // Önceki aktarımda alınıp sonradan iptal edilen siparişler aynı ay ve üründen düşülür
            for g in sonuc.geriAlinacak {
                var adet = g.qty, tutar = g.grossSales, indirim = g.discount
                for i in satirlar(g).sorted(by: { s.sales[$0].qty > s.sales[$1].qty }) where adet > 0 || tutar > 0 {
                    let a = min(adet, s.sales[i].qty), t = min(tutar, s.sales[i].grossSales)
                    let d = min(indirim, s.sales[i].discount)
                    s.sales[i].qty -= a; s.sales[i].grossSales -= t; s.sales[i].discount -= d
                    s.sales[i].discount = min(s.sales[i].discount, s.sales[i].grossSales)
                    adet -= a; tutar -= t; indirim -= d
                }
            }
            if !sonuc.geriAlinacak.isEmpty {
                s.sales.removeAll { $0.channelId == kanalId && $0.qty == 0 && $0.grossSales == 0
                    && $0.returnsQty == 0 && $0.returnsAmount == 0 }
            }
            for cm in sonuc.aylar {
                if let i = s.channelMonths.firstIndex(where: { $0.month == cm.month && $0.channelId == kanalId }) {
                    s.channelMonths[i] = cm
                } else {
                    s.channelMonths.append(cm)
                }
            }
        }
    }

    public func restartSetup() { mutate { $0.settings.setupCompleted = false } }

    /// "Değişiklik yok" — fiyatlara dokunmaz, yalnızca son kontrol gününü işaretler.
    public func markPriceCheck(_ day: DateKey = Dates.today()) {
        mutate { $0.settings.lastPriceCheck = day }
    }

    public func setYearlyProfitGoal(_ amount: Kurus?, for year: Int, vergiSonrasi: Bool = false) {
        mutate { s in
            if let a = amount, a > 0 {
                s.settings.yearlyProfitGoals["\(year)"] = a
                s.settings.ek.vergiSonrasiHedef = (s.settings.ek.vergiSonrasiHedef ?? [:]).merging(["\(year)": vergiSonrasi]) { $1 }
            } else {
                s.settings.yearlyProfitGoals["\(year)"] = nil
                s.settings.ek.vergiSonrasiHedef?["\(year)"] = nil
            }
        }
    }

    /// Bir çeyreğin gerçekten ödenen geçici vergisi. nil = ödeme kaydı yok (ödenmemiş)
    public func geciciVergiOdemesi(yil: Int, ceyrek: Int, _ odeme: VergiOdemesi?) {
        mutate { s in
            var d = s.settings.ek.geciciVergiOdemeleri ?? [:]
            d["\(yil)-\(ceyrek)"] = odeme.flatMap { $0.tutar > 0 ? $0 : nil }
            s.settings.ek.geciciVergiOdemeleri = d
        }
    }

    /// Yıllık gelir/kurumlar vergisi beyanı için gerçekten ödenen tutar. nil = ödeme kaydı yok
    public func yillikVergiOdemesi(yil: Int, _ odeme: VergiOdemesi?) {
        mutate { s in
            var d = s.settings.ek.geciciVergiOdemeleri ?? [:]
            d["\(yil)-yillik"] = odeme.flatMap { $0.tutar > 0 ? $0 : nil }
            s.settings.ek.geciciVergiOdemeleri = d
        }
    }

    /// Vergi hesabı için yıllık tutarlar (KKEG ek, geçmiş yıl zararı, istisna/indirim). nil = girilmedi.
    public func vergiTutarlari(yil: Int, kkegEk: Kurus?, gecmisZarar: Kurus?, istisna: Kurus?) {
        mutate { s in
            let k = "\(yil)"
            var a = s.settings.ek.kkegEk ?? [:]; a[k] = kkegEk.map { max($0, 0) }; s.settings.ek.kkegEk = a
            var b = s.settings.ek.gecmisYilZarari ?? [:]; b[k] = gecmisZarar.map { max($0, 0) }; s.settings.ek.gecmisYilZarari = b
            var c = s.settings.ek.istisnaIndirim ?? [:]; c[k] = istisna.map { max($0, 0) }; s.settings.ek.istisnaIndirim = c
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
    public func setProfitGoal(_ amount: Kurus?, for month: MonthKey, vergiSonrasi: Bool = false) {
        mutate { s in
            if let a = amount, a > 0 {
                s.settings.profitGoals[month] = a
                s.settings.ek.vergiSonrasiHedef = (s.settings.ek.vergiSonrasiHedef ?? [:]).merging([month: vergiSonrasi]) { $1 }
            } else {
                s.settings.profitGoals[month] = nil
                s.settings.ek.vergiSonrasiHedef?[month] = nil
            }
        }
    }

    /// Doğrudan uygulanan (değişiklik akışından geçmeyen) büyük işlemler de günlüğe yazılır
    private static func gunlugeYaz(_ s: inout AppState, onceki: [ChangeLogEntry], _ aciklama: String) {
        s.changeLog = Array((onceki + [ChangeLogEntry(
            zaman: ISO8601DateFormatter().string(from: Date()), tur: .silindi, alan: "Veriler",
            aciklama: aciklama)]).suffix(DegisiklikGunlugu.enFazla))
    }

    public func resetToSeed() {
        var s = SeedData.initialState()
        Self.gunlugeYaz(&s, onceki: state.changeLog, "Başlangıç verisine sıfırlandı")
        apply(s)
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
        Self.gunlugeYaz(&s, onceki: s.changeLog, "Bütün satış, gider, alım ve stok kayıtları silindi")
        apply(s)
        pruneAttachments()
    }

    public func exportJSON() throws -> Data { try Persistence.encode(state) }

    public func importJSON(_ data: Data) throws {
        var s = try Persistence.decode(data)
        Self.gunlugeYaz(&s, onceki: s.changeLog + state.changeLog.filter { k in !s.changeLog.contains { $0.id == k.id } },
                        "Dosyadan içe aktarıldı (önceki kayıtların yerine)")
        apply(s)
    }
}
