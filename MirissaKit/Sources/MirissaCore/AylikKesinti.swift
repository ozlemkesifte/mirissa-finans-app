import Foundation

/// "Aylık gerçek tutarı ben gireceğim" denen kesintilerin, ayın gerçek giriş
/// alanlarıyla eşlenmesi. Kurulum akışı bu kesintileri etiketle kaydeder.
enum AylikKesinti {
    static func kargoMu(_ f: ChannelExtraFee) -> Bool {
        f.label.lowercased(with: Locale(identifier: "tr_TR")).contains("kargo")
    }

    static func komisyonMu(_ f: ChannelExtraFee) -> Bool {
        let ad = f.label.lowercased(with: Locale(identifier: "tr_TR"))
        return ad.contains("komisyon") || ad.contains("hizmet")
    }

    /// Kargo ve hizmet bedeli sipariş başına, komisyon ve diğerleri ciroya orantılı
    static func siparisBasiMi(_ f: ChannelExtraFee) -> Bool { kargoMu(f) }

    /// Bu kesintinin o aydaki gerçek tutarı (girilmemişse nil)
    static func tutar(_ f: ChannelExtraFee, _ cm: ChannelMonth?) -> Kurus? {
        guard let cm else { return nil }
        if kargoMu(f) { return cm.shippingActual }
        if komisyonMu(f) { return cm.commissionActual ?? cm.serviceFeeActual }
        return cm.otherDeductionActual
    }
}
