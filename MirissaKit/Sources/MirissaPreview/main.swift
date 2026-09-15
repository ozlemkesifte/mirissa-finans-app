import SwiftUI
import AppKit
import MirissaCore
import MirissaUI

/// Ekranları PNG olarak üretir — Xcode kurulu olmadan tasarımı görmek için.
/// Kullanım: swift run MirissaPreview <çıktı-klasörü>

@MainActor
func demoState() -> AppState {
    var s = SeedData.initialState()
    s.products[0].costLines = [CostLine(id: "c1", label: "Üretim", amount: Money.fromTL(132))]
    s.products[1].costLines = [CostLine(id: "c2", label: "Üretim", amount: Money.fromTL(139))]

    // Fiyat geçmişi: eylülde 699, 20 eylülde 749
    if let i = s.products.firstIndex(where: { $0.id == SeedData.P.sampuan }) {
        s.products[i].setPrice(Money.fromTL(650), channelId: nil, from: "2026-09-01")
        s.products[i].setPrice(Money.fromTL(699), channelId: ChannelIds.trendyol,
                               from: "2026-09-01")
        s.products[i].setPrice(Money.fromTL(749), channelId: ChannelIds.trendyol,
                               from: "2026-09-20")
    }
    if let i = s.products.firstIndex(where: { $0.id == SeedData.P.serum }) {
        s.products[i].setPrice(Money.fromTL(890), channelId: nil, from: "2026-09-01")
    }

    // Yarım kalmış bir kanal kurulumu — kart görünsün
    if let d = WizardDraft.make(kind: .kanalKurulumu, subjectId: ChannelIds.trendyol,
                                title: "Trendyol kurulumu", step: 7, totalSteps: 12,
                                updatedAt: "2026-09-14", state: ["adim": "kargoVarMi"]) {
        s.drafts.append(d)
    }

    func esik(_ id: Id, _ min: Double, _ kritik: Double) {
        if let i = s.materials.firstIndex(where: { $0.id == id }) {
            s.materials[i].minQty = min
            s.materials[i].criticalQty = kritik
        }
    }
    esik(SeedData.M.koli, 150, 80)
    esik(SeedData.M.kirilmazEtiket, 300, 150)
    esik(SeedData.M.dolguKirpigi, 3000, 1500)
    esik(SeedData.M.tesekkurKarti, 200, 100)

    func al(_ id: String, _ d: DateKey, _ item: ItemRef, _ q: Double, _ u: UnitCode, _ tl: Double) {
        s.purchases.append(StockPurchase(id: id, date: d, item: item, qty: q, unit: u,
                                         totalPaid: Money.fromTL(tl)))
    }
    al("p1", "2026-03-02", .material(SeedData.M.koli), 500, .adet, 5000)
    al("p2", "2026-06-20", .material(SeedData.M.koli), 500, .adet, 6000)
    al("p3", "2026-03-02", .material(SeedData.M.sampuanKutu), 600, .adet, 4800)
    al("p4", "2026-03-02", .material(SeedData.M.serumKutu), 500, .adet, 4000)
    al("p5", "2026-03-02", .material(SeedData.M.setKutu), 150, .adet, 2250)
    al("p6", "2026-03-02", .material(SeedData.M.patpat), 900, .adet, 1800)
    al("p7", "2026-03-02", .material(SeedData.M.kirilmazEtiket), 1200, .adet, 600)
    al("p8", "2026-03-02", .material(SeedData.M.dolguKirpigi), 12, .kg, 2400)
    al("p9", "2026-03-02", .material(SeedData.M.tesekkurKarti), 700, .adet, 1050)
    al("p10", "2026-03-03", .product(SeedData.P.sampuan), 600, .adet, 79200)
    al("p11", "2026-03-03", .product(SeedData.P.serum), 500, .adet, 69500)
    al("p12", "2026-06-20", .material(SeedData.M.sampuanKutu), 400, .adet, 3400)
    al("p13", "2026-06-20", .material(SeedData.M.serumKutu), 300, .adet, 2550)
    al("p14", "2026-06-20", .material(SeedData.M.patpat), 600, .adet, 1320)
    al("p15", "2026-06-20", .material(SeedData.M.kirilmazEtiket), 1000, .adet, 550)
    al("p16", "2026-06-21", .material(SeedData.M.dolguKirpigi), 10, .kg, 2200)
    al("p17", "2026-06-20", .material(SeedData.M.tesekkurKarti), 500, .adet, 800)
    al("p18", "2026-06-25", .product(SeedData.P.sampuan), 300, .adet, 40800)
    al("p19", "2026-06-25", .product(SeedData.P.serum), 250, .adet, 35500)

    s.channels[0].commissionPct = 20
    s.channels[0].shippingPerOrder = Money.fromTL(60)
    s.channels[1].paymentPct = 3
    s.channels[1].shippingPerOrder = Money.fromTL(70)
    s.channels[1].platformFeeMonthly = Money.fromTL(1500)

    func sat(_ id: String, _ m: MonthKey, _ ch: Id, _ p: Id, _ q: Double, _ tl: Double,
             ind: Double = 0, iade: Double = 0, iadeAdet: Double = 0) {
        s.sales.append(SalesEntry(id: id, month: m, channelId: ch, productId: p, qty: q,
                                  grossSales: Money.fromTL(tl), discount: Money.fromTL(ind),
                                  returnsAmount: Money.fromTL(iade), returnsQty: iadeAdet))
    }
    // Nisan–Eylül arası gerçekçi bir gidişat
    let aylar: [(MonthKey, Double, Double, Double)] = [
        ("2026-04", 42, 28, 12),
        ("2026-05", 55, 33, 15),
        ("2026-06", 61, 40, 18),
        ("2026-07", 70, 44, 22),
        ("2026-08", 74, 47, 26),
        ("2026-09", 80, 50, 30),
    ]
    for (i, a) in aylar.enumerated() {
        sat("s\(i)a", a.0, ChannelIds.trendyol, SeedData.P.sampuan, a.1, a.1 * 699,
            ind: a.1 * 12, iade: i == 5 ? 1398 : 0, iadeAdet: i == 5 ? 2 : 0)
        sat("s\(i)b", a.0, ChannelIds.trendyol, SeedData.P.serum, a.2, a.2 * 750)
        sat("s\(i)c", a.0, ChannelIds.shopify, SeedData.P.set, a.3, a.3 * 1500)
        s.channelMonths.append(ChannelMonth(id: "cm\(i)t", month: a.0,
                                            channelId: ChannelIds.trendyol,
                                            orderCount: Int(a.1 + a.2)))
        s.channelMonths.append(ChannelMonth(id: "cm\(i)s", month: a.0,
                                            channelId: ChannelIds.shopify,
                                            orderCount: Int(a.3)))
    }

    s.expenses = [
        Expense(id: "e1", date: "2026-04-01", name: "Muhasebeci", amount: Money.fromTL(5000),
                category: .sabit, recurrence: .aylik),
        Expense(id: "e2", date: "2026-04-01", name: "Ajans", amount: Money.fromTL(20000),
                category: .sabit, recurrence: .aylik),
        Expense(id: "e3", date: "2026-04-01", name: "Klaviyo", amount: Money.fromTL(2000),
                category: .sabit, recurrence: .aylik),
        Expense(id: "e4", date: "2026-09-10", name: "Trendyol reklamı", amount: Money.fromTL(5000),
                category: .reklam, scope: .channel(ChannelIds.trendyol)),
        Expense(id: "e5", date: "2026-09-12", name: "Meta reklam", amount: Money.fromTL(12000),
                category: .reklam, scope: .channel(ChannelIds.shopify)),
        Expense(id: "e6", date: "2026-09-15", name: "Influencer iş birliği",
                amount: Money.fromTL(8000), category: .influencer),
    ]
    s.adjustments = [
        StockAdjustment(id: "a1", date: "2026-09-18", item: .material(SeedData.M.koli),
                        qty: 10, unit: .adet, reason: .hasarli)
    ]
    // KDV: satışlar, giderler ve alımlar %20 KDV dahil girilmiş
    for i in s.sales.indices { s.sales[i].vatRate = .yirmi; s.sales[i].vatIncluded = true }
    for i in s.expenses.indices { s.expenses[i].vatRate = .yirmi; s.expenses[i].vatIncluded = true }
    for i in s.purchases.indices { s.purchases[i].vatRate = .yirmi; s.purchases[i].vatIncluded = true }
    for i in s.channels.indices { s.channels[i].feeVatRate = .yirmi; s.channels[i].feesIncludeVat = true }
    s.balances = [
        BalanceItem(id: "b1", kind: .alacak, source: .kanal,
                    name: "Trendyol Eylül hakedişi", amount: Money.fromTL(46_500),
                    dueDate: "2026-10-05"),
        BalanceItem(id: "b2", kind: .alacak, source: .kanal,
                    name: "Shopify bekleyen ödeme", amount: Money.fromTL(12_400)),
        BalanceItem(id: "b3", kind: .odenecek, source: .tedarikci,
                    name: "Kutu tedarikçisi faturası", amount: Money.fromTL(18_000),
                    dueDate: "2026-10-15"),
        BalanceItem(id: "b4", kind: .odenecek, source: .diger,
                    name: "Influencer ödemesi", amount: Money.fromTL(8000)),
    ]
    return s
}

/// Başa başın altında kalınan bir ay — uyarı ve günlük hedef bandını görmek için
@MainActor
func demoZarar() -> AppState {
    var s = demoState()
    // Eylül satışlarını üçte birine indir
    for i in s.sales.indices where s.sales[i].month == "2026-09" {
        s.sales[i].qty = (s.sales[i].qty / 3).rounded()
        s.sales[i].grossSales = s.sales[i].grossSales / 3
        s.sales[i].discount = s.sales[i].discount / 3
        s.sales[i].returnsAmount = 0
        s.sales[i].returnsQty = 0
    }
    for i in s.channelMonths.indices where s.channelMonths[i].month == "2026-09" {
        s.channelMonths[i].orderCount = (s.channelMonths[i].orderCount ?? 0) / 3
    }
    s.settings.profitGoals["2026-09"] = Money.fromTL(75_000)
    return s
}

@MainActor
func render(_ view: AnyView, to url: URL, size: CGSize, koyu: Bool = false) -> Bool {
    // ImageRenderer kaydırılabilir içeriği çizemiyor; gerçek bir pencerede
    // yerleşim yaptırıp katmanı yakalıyoruz.
    let hosting = NSHostingView(rootView: AnyView(
        view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, koyu ? .dark : .light)
    ))
    hosting.frame = CGRect(origin: .zero, size: size)

    let window = NSWindow(
        contentRect: hosting.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hosting
    window.isOpaque = true
    window.backgroundColor = koyu ? .black : .white
    window.appearance = NSAppearance(named: koyu ? .darkAqua : .aqua)
    window.orderFrontRegardless()

    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.45))
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    window.orderOut(nil)
    do { try png.write(to: url); return true } catch { return false }
}

@MainActor
func run() {
    let outDir = CommandLine.arguments.count > 1
        ? URL(fileURLWithPath: CommandLine.arguments[1])
        : URL(fileURLWithPath: "onizleme")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let store = AppStore.inMemory(demoState())
    let period = Period(month: "2026-09")
    let size = CGSize(width: 393, height: 852)   // iPhone 15/16 noktası

    var ok = 0
    for s in PreviewGallery.screens(store: store, period: period) {
        let url = outDir.appendingPathComponent("\(s.name).png")
        if render(s.view, to: url, size: size) { ok += 1; print("✓ \(s.title) → \(url.lastPathComponent)") }
        else { print("✗ \(s.title)") }
    }
    // Ekim: satış girilmemiş -> aylık hedef modu
    let hedefStore = AppStore.inMemory(demoState())
    if let ekran = PreviewGallery.screens(store: hedefStore, period: Period(month: "2026-10")).first {
        let u = outDir.appendingPathComponent("1b-ana-sayfa-hedef.png")
        if render(ekran.view, to: u, size: size) { ok += 1; print("✓ Ana Sayfa (aylık hedef) → \(u.lastPathComponent)") }
    }
    // Koyu mod: buton kontrastı ve gri tonlar
    let koyuEkran = outDir.appendingPathComponent("9-koyu-mod.png")
    if let ekran = PreviewGallery.screens(store: store, period: Period(month: "2026-09")).dropFirst(2).first,
       render(ekran.view, to: koyuEkran, size: size, koyu: true) {
        ok += 1; print("✓ Koyu mod (Giderler) → \(koyuEkran.lastPathComponent)")
    }

    // --- Ana sayfanın dört senaryosu ---
    func golden() -> AppState {
        // Önizleme için altın senaryonun sadeleştirilmiş hali
        var g = demoState()
        g.settings.companyName = "Mirissa Lab"
        return g
    }

    // 1) Hiç satış yok, tüm maliyetler ve fiyatlar tanımlı
    var s1 = golden()
    s1.sales = []
    s1.channelMonths = []
    for i in s1.products.indices where !s1.products[i].isBundle {
        s1.products[i].setPrice(Money.fromTL(1_200), channelId: ChannelIds.trendyol,
                                from: "2026-01-01")
        s1.products[i].setPrice(Money.fromTL(1_100), channelId: ChannelIds.shopify,
                                from: "2026-01-01")
    }
    s1.channels = s1.channels.filter { $0.id != ChannelIds.other }
    s1.settings.salesMix = SalesMix(
        channelShares: [ChannelIds.trendyol: 60, ChannelIds.shopify: 40],
        productShares: [SeedData.P.sampuan: 60, SeedData.P.serum: 40],
        confirmed: true, confirmedAt: "2026-09-01")
    let u1 = outDir.appendingPathComponent("s1-satis-yok.png")
    if render(PreviewGallery.homeScenario(store: AppStore.inMemory(s1), month: "2026-09"),
              to: u1, size: size) { ok += 1; print("✓ Senaryo 1 → \(u1.lastPathComponent)") }

    // 2) Geçmiş satış yok, yaklaşık dağılım henüz onaylanmamış
    var s2 = s1
    s2.settings.salesMix = nil
    let u2 = outDir.appendingPathComponent("s2-dagilim-sorulmamis.png")
    if render(PreviewGallery.homeScenario(store: AppStore.inMemory(s2), month: "2026-09"),
              to: u2, size: size) { ok += 1; print("✓ Senaryo 2 → \(u2.lastPathComponent)") }

    // 3) Gerçek satış girilmiş ay
    let u3 = outDir.appendingPathComponent("s3-satis-girilmis.png")
    if render(PreviewGallery.homeScenario(store: AppStore.inMemory(golden()), month: "2026-09"),
              to: u3, size: size) { ok += 1; print("✓ Senaryo 3 → \(u3.lastPathComponent)") }

    // 4) Başa baş için gerekli bilgi eksik (fiyatlar girilmemiş)
    var s4 = s1
    for i in s4.products.indices { s4.products[i].priceHistory = nil }
    let u4 = outDir.appendingPathComponent("s4-eksik-bilgi.png")
    if render(PreviewGallery.homeScenario(store: AppStore.inMemory(s4), month: "2026-09"),
              to: u4, size: size) { ok += 1; print("✓ Senaryo 4 → \(u4.lastPathComponent)") }

    // Rehberli akışlar — ilk soru ekranları
    var akisDurumu = demoState()
    akisDurumu.channels.removeAll { $0.id == ChannelIds.other }
    for f in PreviewGallery.guidedFlows(store: AppStore.inMemory(akisDurumu)) {
        let u = outDir.appendingPathComponent("\(f.name).png")
        if render(f.view, to: u, size: size) { ok += 1; print("✓ \(f.title) → \(u.lastPathComponent)") }
        else { print("✗ \(f.title)") }
    }

    // Kurulumun set/SKU adımları
    for adim in PreviewGallery.SetupPreviewStep.allCases {
        let st = AppStore.inMemory(demoState())
        let u = outDir.appendingPathComponent("k-\(adim.rawValue).png")
        if render(PreviewGallery.setupStep(store: st, adim), to: u, size: size) {
            ok += 1; print("✓ Kurulum: \(adim.rawValue) → \(u.lastPathComponent)")
        } else { print("✗ Kurulum: \(adim.rawValue)") }
    }

    // İlk kurulum sihirbazı — birkaç adım
    let bosStore = AppStore.inMemory(SeedData.initialState())
    let sihirbaz = outDir.appendingPathComponent("10-ilk-kurulum.png")
    if render(PreviewGallery.setupWizard(store: bosStore), to: sihirbaz, size: size) {
        ok += 1; print("✓ İlk kurulum → \(sihirbaz.lastPathComponent)")
    }

    let urunForm = outDir.appendingPathComponent("11-recete-sorulari.png")
    if render(PreviewGallery.productForm(store: hedefStore, productId: SeedData.P.sampuan),
              to: urunForm, size: size) { ok += 1; print("✓ Reçete soruları → \(urunForm.lastPathComponent)") }

    let kdvKart = outDir.appendingPathComponent("8-kdv-alacak.png")
    if render(PreviewGallery.vatAndBalance(store: hedefStore, month: "2026-09"),
              to: kdvKart, size: size) { ok += 1; print("✓ KDV + Alacak → \(kdvKart.lastPathComponent)") }

    let hedefDetay = outDir.appendingPathComponent("1c-hedef-detay.png")
    if render(PreviewGallery.breakevenCard(store: hedefStore, month: "2026-10"),
              to: hedefDetay, size: size) { ok += 1; print("✓ Hedef detayı → \(hedefDetay.lastPathComponent)") }

    // Başa başın altında kalınan bir ay sonucu
    let zararStore = AppStore.inMemory(demoZarar())
    let zarar = outDir.appendingPathComponent("1d-ay-sonucu-zarar.png")
    if render(PreviewGallery.breakevenCard(store: zararStore, month: "2026-09"),
              to: zarar, size: size) { ok += 1; print("✓ Ay sonucu (zarar) → \(zarar.lastPathComponent)") }

    let giderForm = outDir.appendingPathComponent("3b-gider-formu.png")
    if let rek = zararStore.state.expenses.first(where: { $0.category == .reklam }),
       render(PreviewGallery.expenseForm(store: zararStore, month: "2026-09", expenseId: rek.id),
              to: giderForm, size: size) {
        ok += 1; print("✓ Gider formu → \(giderForm.lastPathComponent)")
    }

    let detay = outDir.appendingPathComponent("6-malzeme-detay.png")
    if render(PreviewGallery.detail(store: store, period: period, materialId: SeedData.M.koli),
              to: detay, size: size) { ok += 1; print("✓ Malzeme detayı → \(detay.lastPathComponent)") }
    let udetay = outDir.appendingPathComponent("7-urun-detay.png")
    if render(PreviewGallery.productDetail(store: store, period: period, productId: SeedData.P.set),
              to: udetay, size: size) { ok += 1; print("✓ Ürün detayı → \(udetay.lastPathComponent)") }

    print("\n\(ok) ekran üretildi: \(outDir.path)")
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    run()
}
