# Mirissa Finans App

Mirissa Lab için finans, kârlılık ve otomatik stok takibi yapan native iOS uygulaması.

**Mantık:** Ekle → Kaydet → Sistem hesaplasın.

---

## Ne yapıyor

- Aylık satışları kanal bazında toplar (Trendyol / Shopify / Diğer)
- Gerçek ciro, toplam gider, gerçek kâr ve kâr marjını hesaplar
- Satış girdiğinde ürün ve **paketleme malzemelerini otomatik stoktan düşer**
- Stok alımında ortalama maliyeti günceller ve gideri kendiliğinden oluşturur
- Fire, kırık, numune ve sayım farklarını stok geçmişine işler
- Hangi malzemenin bitmek üzere olduğunu ve yaklaşık kaç siparişlik kaldığını gösterir
- Aylık / yıllık / kanal raporları üretir, CSV olarak dışa aktarır

Veriler **sadece telefonda** saklanır, internet gerektirmez.

---

## Proje yapısı

```
MirissaKit/          Swift paketi — Xcode olmadan derlenir ve test edilir
  Sources/MirissaCore    Veri modeli + bütün hesaplamalar (saf Swift)
  Sources/MirissaUI      SwiftUI ekranları
  Tests/                 70 birim testi
App/                 iOS uygulama kabuğu (Info.plist, ikon, giriş noktası)
project.yml          XcodeGen tanımı — .xcodeproj bundan üretilir
.github/workflows/   GitHub Actions: derle → TestFlight'a yükle
```

`MirissaFinans.xcodeproj` depoya konmaz; `xcodegen generate` ile her zaman
yeniden üretilir. Böylece proje dosyası hiç bozulmaz.

---

## Geliştirme (Xcode gerekmeden)

```bash
./runtests.sh      # hesaplama motorunun 70 testini çalıştırır
./build-check.sh   # bütün kaynak kodu derler (ekranlar dahil)
```

Bunlar macOS SDK'sı üzerinden çalışır; Xcode kurulu olmasına gerek yoktur.

Xcode kuruluysa:

```bash
xcodegen generate && open MirissaFinans.xcodeproj
```

---

## TestFlight'a yayınlama

`main` dalına her gönderim otomatik olarak derlenip TestFlight'a yüklenir.
Elle başlatmak için: GitHub → **Actions** → **TestFlight** → **Run workflow**.

### Bir kereye mahsus kurulum

**1. App Store Connect'te uygulamayı oluştur**

- appstoreconnect.apple.com → **Apps** → **+** → **New App**
- Platform: iOS
- Ad: `Mirissa Finans App`
- Bundle ID: `com.mirissalab.finans` — listede yoksa önce
  developer.apple.com → Identifiers → **+** ile bu kimliği kaydet
- SKU: `mirissa-finans`

**2. App Store Connect API anahtarı oluştur**

- App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API**
- **+** ile yeni anahtar, rol: **App Manager**
- `.p8` dosyasını indir (bir kez indirilebilir, sakla)
- **Key ID** ve **Issuer ID** değerlerini not al

**3. Team ID'yi al**

developer.apple.com → **Membership** → 10 karakterlik **Team ID**

**4. GitHub'a gizli anahtarları ekle**

Depo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

| Secret adı | Değeri |
|---|---|
| `ASC_KEY_ID` | Anahtarın Key ID'si |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_PRIVATE_KEY` | `.p8` dosyasının **tüm içeriği** (`-----BEGIN PRIVATE KEY-----` satırı dahil) |
| `APPLE_TEAM_ID` | 10 karakterlik Team ID |

**5. Kendini test kullanıcısı yap**

App Store Connect → uygulaman → **TestFlight** → **Internal Testing** →
grup oluştur → kendini ekle. Internal testte Apple incelemesi beklenmez.

### Sonrası

Her yeni sürümde build numarası otomatik artar. Yükleme bittikten birkaç
dakika sonra telefonundaki **TestFlight** uygulamasında güncelleme görünür.

---

## Hesaplama mantığı — kısa not

**Stok saklanmaz, hesaplanır.** Bütün alım, satış, fire ve sayım kayıtları
tarih sırasına dizilip baştan katlanır. Bu yüzden geçmişteki bir kaydı
düzelttiğinde veya sildiğinde bütün sonraki rakamlar kendiliğinden doğru olur.

**Ortalama maliyet.** 500 koli 10 TL'den, sonra 500 koli 12 TL'den alınırsa
birim maliyet 11 TL olur. Satışta bu maliyet kullanılır.

**Çifte sayım koruması.** Bir kanala işaretlenen gider (ör. Trendyol reklamı)
sadece o kanalın kârlılığından düşülür, ortak giderlere tekrar eklenmez.
Stok alımı ise gider olarak değil, ürün satıldıkça maliyet olarak yansır;
kasadan çıkan tutar ayrıca "nakit çıkışı" olarak gösterilir.

```
GERÇEK KÂR = Σ(kanalda kalan) − ortak şirket giderleri
```

---

## Başa baş & hedef

Ana sayfadaki **"Bu ay neredeyiz?"** kartı şunu hesaplar: bu ayki sabit
giderleri karşılamak için kaç sipariş gerekiyor, kaç sipariş kaldı ve kalan
günlerde günde kaç sipariş çıkması lazım. Her açılışta yeniden hesaplanır,
geride kalındıkça günlük hedef kendini yukarı çeker.

**Sipariş başına kazanç** o ayın gerçek kanal ve ürün karışımından çıkar —
bütün siparişler aynı kârlılıktaymış gibi varsayılmaz. Trendyol'un komisyonu
ile Shopify'ın ödeme komisyonu ayrı hesaplanır, ürün maliyetleri satılan
karışıma göre ağırlıklanır.

```
katkı            = net satış − komisyon − kargo − hizmet bedeli
                              − ürün maliyeti − ambalaj
sipariş başına   = katkı ÷ sipariş sayısı
başa baş         = sabit giderler ÷ sipariş başına katkı
X TL kâr için    = (sabit giderler + X) ÷ sipariş başına katkı
```

**Sabit ile değişken ayrımı önemli:** aylık Shopify ücreti, reklam, ajans,
muhasebeci gibi kalemler sipariş adedinden bağımsızdır ve başa baş noktasını
yukarı iter. Komisyon ve kargo ise her siparişle birlikte artar.

**Nakit çıkışı kâr değildir.** 500 koliye bu ay 5.000 TL ödemek, o 5.000 TL'yi
bu ayın kârından düşmek anlamına gelmez — kâra yalnızca o ay gerçekten satılan
ürünlerin ambalaj maliyeti girer. Ödenen tutar ayrıca "bu ay ödenen (nakit
çıkışı)" olarak gösterilir. Başa baş hesabı kâr tarafını kullanır.

Veri eksikse uydurma kesin rakam verilmez; hangi verinin eksik olduğu yazılır
(satış yok, sabit gider girilmemiş, ürün maliyeti yok, sipariş sayısı tahmini).
Sipariş başına kazanç eksiyse başa baş hesaplanmaz — satış arttıkça zarar da
artacağı söylenir.

---

## Ekran önizlemesi (Xcode'suz)

```bash
cd MirissaKit && swift run MirissaPreview ../onizleme
```

Bütün ekranları iPhone ölçüsünde PNG olarak `onizleme/` klasörüne çizer.
Tasarımı telefona kurmadan önce görmek için kullanılır.
