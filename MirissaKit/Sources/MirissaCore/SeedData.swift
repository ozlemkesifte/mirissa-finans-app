import Foundation

/// İlk açılış verisi: yapı hazır, rakamlar sıfır.
/// Ürünler, malzemeler, kanallar ve paketleme reçeteleri tanımlı gelir;
/// maliyet, stok, satış ve gider rakamlarını kullanıcı kendi girer.
public enum SeedData {
    public enum M {
        public static let koli = "mat_koli"
        public static let sampuanKutu = "mat_sampuan_kutu"
        public static let serumKutu = "mat_serum_kutu"
        public static let setKutu = "mat_set_kutu"
        public static let patpat = "mat_patpat"
        public static let balonluPoset = "mat_balonlu_poset"
        public static let pelur = "mat_pelur"
        public static let kirilmazEtiket = "mat_kirilmaz_etiket"
        public static let sticker = "mat_sticker"
        public static let tesekkurKarti = "mat_tesekkur_karti"
        public static let kargoEtiketi = "mat_kargo_etiketi"
        public static let dolguKirpigi = "mat_dolgu_kirpigi"
        public static let kagitDolgu = "mat_kagit_dolgu"
        public static let bant = "mat_bant"
    }

    public enum P {
        public static let sampuan = "pro_sampuan"
        public static let serum = "pro_serum"
        public static let set = "pro_set"
    }

    public static func materials() -> [StockMaterial] {
        [
            StockMaterial(id: M.koli, name: "Kargo kolisi", category: .ambalaj, baseUnit: .adet, perOrder: true),
            StockMaterial(id: M.sampuanKutu, name: "Şampuan kutusu", category: .ambalaj, baseUnit: .adet),
            StockMaterial(id: M.serumKutu, name: "Serum kutusu", category: .ambalaj, baseUnit: .adet),
            StockMaterial(id: M.setKutu, name: "Set kutusu", category: .ambalaj, baseUnit: .adet),
            StockMaterial(id: M.patpat, name: "Patpat", category: .ambalaj, baseUnit: .adet),
            StockMaterial(id: M.balonluPoset, name: "Balonlu poşet", category: .ambalaj, baseUnit: .adet),
            StockMaterial(id: M.pelur, name: "Pelür", category: .ambalaj, baseUnit: .adet),
            StockMaterial(id: M.kirilmazEtiket, name: "Kırılmaz etiketi", category: .sarf, baseUnit: .adet),
            StockMaterial(id: M.sticker, name: "Sticker", category: .sarf, baseUnit: .adet),
            StockMaterial(id: M.tesekkurKarti, name: "Teşekkür kartı", category: .sarf, baseUnit: .adet),
            StockMaterial(id: M.kargoEtiketi, name: "Kargo etiketi", category: .sarf, baseUnit: .adet),
            StockMaterial(id: M.dolguKirpigi, name: "Dolgu kırpığı", category: .ambalaj, baseUnit: .gram),
            StockMaterial(id: M.kagitDolgu, name: "Kâğıt dolgu", category: .ambalaj, baseUnit: .gram),
            StockMaterial(id: M.bant, name: "Bant", category: .sarf, baseUnit: .adet),
        ]
    }

    /// Ortak paketleme kalemleri: koli, patpat, 2 kırılmaz etiket, teşekkür kartı
    private static func commonLines(_ prefix: String, dolguGram: Double) -> [RecipeLine] {
        [
            RecipeLine(id: "\(prefix)_koli", materialId: M.koli, qty: 1, unit: .adet),
            RecipeLine(id: "\(prefix)_patpat", materialId: M.patpat, qty: 1, unit: .adet),
            RecipeLine(id: "\(prefix)_etiket", materialId: M.kirilmazEtiket, qty: 2, unit: .adet),
            RecipeLine(id: "\(prefix)_dolgu", materialId: M.dolguKirpigi, qty: dolguGram, unit: .gram),
            RecipeLine(id: "\(prefix)_kart", materialId: M.tesekkurKarti, qty: 1, unit: .adet),
        ]
    }

    public static func products() -> [Product] {
        let sampuan = Product(
            id: P.sampuan, name: "Şampuan",
            costLines: [CostLine(id: "cst_sampuan_uretim", label: "Üretim", amount: 0)],
            recipe: [RecipeLine(id: "rcp_sampuan_kutu", materialId: M.sampuanKutu, qty: 1, unit: .adet)]
                + commonLines("rcp_sampuan", dolguGram: 20)
        )
        let serum = Product(
            id: P.serum, name: "Serum",
            costLines: [CostLine(id: "cst_serum_uretim", label: "Üretim", amount: 0)],
            recipe: [RecipeLine(id: "rcp_serum_kutu", materialId: M.serumKutu, qty: 1, unit: .adet)]
                + commonLines("rcp_serum", dolguGram: 20)
        )
        let set = Product(
            id: P.set, name: "Set", isBundle: true,
            components: [
                BundleComponent(productId: P.sampuan, qty: 1),
                BundleComponent(productId: P.serum, qty: 1),
            ],
            recipe: [RecipeLine(id: "rcp_set_kutu", materialId: M.setKutu, qty: 1, unit: .adet)]
                + commonLines("rcp_set", dolguGram: 30)
        )
        return [sampuan, serum, set]
    }

    public static func channels() -> [Channel] {
        [
            // Kesinti KDV oranı Türkiye'deki yaygın orandan başlar ama
            // sabit değildir: kanal ayarlarından her zaman değiştirilebilir.
            Channel(id: ChannelIds.trendyol, name: "Trendyol", kind: .marketplace,
                    feeVatRate: .yirmi, feesIncludeVat: true),
            Channel(id: ChannelIds.shopify, name: "Shopify", kind: .ownStore,
                    feeVatRate: .yirmi, feesIncludeVat: true),
            Channel(id: ChannelIds.other, name: "Diğer", kind: .other,
                    feeVatRate: .yirmi, feesIncludeVat: true),
        ]
    }

    /// İlk açılış durumu. Hiçbir finansal rakam doldurulmaz.
    public static func initialState() -> AppState {
        AppState(
            materials: materials(),
            products: products(),
            channels: channels()
        )
    }
}
