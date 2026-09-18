import Foundation

/// "Aylık gerçek tutarı ben gireceğim" denen kesintilerin, ayın gerçek giriş
/// alanlarıyla eşlenmesi. Kurulum akışı bu kesintileri etiketle kaydeder
/// ("Komisyon", "Kargo" …); her etiket ayın TEK bir gerçek alanına bağlanır.
enum AylikKesinti {
    enum Alan: Hashable { case komisyon, kargo, hizmet, reklam, diger }

    /// Etiketi küçük harfe çevirir. Türkçe büyük "I" küçülünce "ı" olur;
    /// "KOMISYON" da eşleşsin diye "ı" "i" sayılır.
    private static func sade(_ s: String) -> String {
        s.lowercased(with: Locale(identifier: "tr_TR")).replacingOccurrences(of: "ı", with: "i")
    }

    static func alan(_ f: ChannelExtraFee) -> Alan {
        let ad = sade(f.label)
        if ad.contains("kargo") { return .kargo }
        if ad.contains("hizmet") { return .hizmet }
        if ad.contains("komisyon") { return .komisyon }
        if ad.contains("reklam") { return .reklam }
        return .diger
    }

    static func kargoMu(_ f: ChannelExtraFee) -> Bool { alan(f) == .kargo }
    static func komisyonMu(_ f: ChannelExtraFee) -> Bool { alan(f) == .komisyon }
    static func hizmetMu(_ f: ChannelExtraFee) -> Bool { alan(f) == .hizmet }

    /// Kargo ve hizmet bedeli sipariş başına, komisyon ve diğerleri ciroya orantılı
    static func siparisBasiMi(_ f: ChannelExtraFee) -> Bool {
        let a = alan(f)
        return a == .kargo || a == .hizmet
    }

    /// Bu kesintinin o aydaki gerçek tutarı (girilmemişse nil; 0 girildiyse 0)
    static func tutar(_ f: ChannelExtraFee, _ cm: ChannelMonth?) -> Kurus? {
        tutar(alan(f), cm)
    }

    static func tutar(_ a: Alan, _ cm: ChannelMonth?) -> Kurus? {
        guard let cm else { return nil }
        switch a {
        case .komisyon: return cm.commissionActual
        case .kargo: return cm.shippingActual
        case .hizmet: return cm.serviceFeeActual
        case .reklam: return cm.adsActual
        case .diger: return cm.otherDeductionActual
        }
    }
}

/// Aylık girilen kesintilerin geçmiş aylardan tahmini.
/// Tahmin edilen alan, kanal ayarındaki aynı alanın yerine geçer (üstüne eklenmez):
/// ayın gerçek tutarı da hesapta o alanın yerine geçiyor.
struct AylikKesintiTahmini {
    /// KDV dahil sipariş değerinin yüzdesi (komisyon + ödeme yerine)
    var komisyonYuzde: Double?
    /// Sipariş başı kargo (ayardaki kargonun yerine)
    var kargoSiparisBasi: Double?
    /// Sipariş başı hizmet bedeli
    var hizmetSiparisBasi: Double?
    /// Diğer kesinti yüzdesi (ayardaki diğer kesinti yüzdesinin yerine)
    var digerYuzde: Double?
    var tahmin: [String] = []
    var eksik: [String] = []

    func degistirir(_ a: AylikKesinti.Alan) -> Bool {
        switch a {
        case .komisyon: return komisyonYuzde != nil
        case .kargo: return kargoSiparisBasi != nil
        case .hizmet: return hizmetSiparisBasi != nil
        case .diger: return digerYuzde != nil
        case .reklam: return false
        }
    }
}
