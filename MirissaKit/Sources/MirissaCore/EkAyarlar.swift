import Foundation

/// Sonradan eklenen ayarlar. Hepsi isteğe bağlıdır; boşken hiçbir hesap değişmez.
public struct EkAyarlar: Codable, Hashable, Sendable {
    // Yedek
    /// Yedeğin telefon dışına en son kaydedildiği (paylaşıldığı) gün
    public var sonYedekPaylasim: DateKey?
    /// Otomatik yedeğin en son alındığı gün
    public var sonOtomatikYedek: DateKey?

    // Vergi karşılığı
    /// "sahis" (gelir vergisi) ya da "sirket" (kurumlar vergisi)
    public var vergiTuru: String?
    /// Muhasebecinin söylediği yaklaşık oran (%). Girilmemişse vergi tahmini yapılmaz.
    public var vergiOrani: Double?

    // Nakit
    /// Kasa + banka bakiyesi ve girildiği gün
    public var kasaBakiye: Kurus?
    public var kasaTarih: DateKey?
    /// Kanal → satıştan kaç gün sonra para hesaba geçiyor (hakediş gecikmesi)
    public var hakedisGecikmesi: [Id: Int]?

    // Kilit
    /// KDV beyanı verilip kilitlenen aylar: bu aylara ait kayıt değiştirilemez
    public var kilitliAylar: [MonthKey]?

    // Hatırlatma
    public var hatirlatmalarAcik: Bool?

    // Ay sonu: elle işaretlenen maddeler (ay → madde kodları)
    public var aySonuIsaretleri: [MonthKey: [String]]?

    // Kâr hedefinin türü: anahtar ay ("2026-09") ya da yıl ("2026"). true = vergi sonrası net kâr.
    // Kayıt yoksa hedef vergi öncesidir (eski hedefler böyle hesaplanıyordu).
    public var vergiSonrasiHedef: [String: Bool]?

    // Vergi hesabı için kullanıcının girdiği yıllık tutarlar (anahtar yıl). Girilmemişse "girilmedi".
    /// Elle eklenen kanunen kabul edilmeyen giderler (KKEG işaretli giderlere ek olarak)
    public var kkegEk: [String: Kurus]?
    /// Mahsup edilecek geçmiş yıl zararları
    public var gecmisYilZarari: [String: Kurus]?
    /// İstisna ve indirimler (ör. Ar-Ge, bağış)
    public var istisnaIndirim: [String: Kurus]?
    /// Şirketin kuruluş yılı: yurt içi asgari kurumlar vergisi ilk üç hesap döneminde uygulanmaz
    public var kurulusYili: Int?
    /// Gerçekten ödenen geçici vergiler (anahtar "2026-1" … "2026-4"). Kayıt yoksa ödenmemiş sayılır.
    public var geciciVergiOdemeleri: [String: VergiOdemesi]?
    /// %5 vergiye uyumlu mükellef indirimi şartları: "evet" (muhasebeci doğruladı), "hayir"; nil = bilmiyorum
    public var uyumIndirimi: String?
    /// Muhasebeci uygulaması: geçmiş yıl zararı asgari kurumlar vergisi matrahından da düşülsün
    /// (Danıştay 3. D. E.2024/5700 K.2025/4831; kesinleşmesi doğrulanmadı). nil/false = düşülmez
    public var asgariZararIndirimi: Bool?

    public init() {}

    public var kilitli: Set<MonthKey> { Set(kilitliAylar ?? []) }
    public func gecikme(_ kanal: Id) -> Int { hakedisGecikmesi?[kanal] ?? 0 }
}

/// Gerçekleşmiş bir vergi ödemesi
public struct VergiOdemesi: Codable, Hashable, Sendable {
    public var tutar: Kurus
    public var tarih: DateKey
    public init(tutar: Kurus, tarih: DateKey) { self.tutar = tutar; self.tarih = tarih }
}

/// Değişiklik günlüğü satırı
public struct ChangeLogEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Tur: String, Codable, Sendable { case eklendi, degisti, silindi, geriYuklendi }
    public var id: Id
    public var zaman: String
    public var tur: Tur
    public var alan: String
    public var aciklama: String

    public init(id: Id = UUID().uuidString, zaman: String, tur: Tur, alan: String, aciklama: String) {
        self.id = id
        self.zaman = zaman
        self.tur = tur
        self.alan = alan
        self.aciklama = aciklama
    }
}
