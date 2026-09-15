# Mirissa Finans App

Mirissa Lab için finans, kârlılık ve otomatik stok takibi yapan native iOS uygulaması.

**Mantık:** Ekle → Kaydet → Sistem hesaplasın.

---

## İlk kurulum

Uygulama ilk açıldığında yedi adımlık zorunlu bir sihirbaz çıkar: ürünler,
elindeki stok, birim maliyetler, ambalaj malzemeleri, malzeme stokları,
sabit giderler, satış kanalları. Tek ekranda tek soru.

**Başlangıç stoğu.** Şirket aylar önce faaliyete başladıysa eldeki stokların
çoğu geçmişte alınmıştır. "Şu anda 740 şampuanım var" dediğinde bu:

- mevcut stoğa eklenir
- maliyet hesabında kullanılır
- **bu ayın gideri veya nakit çıkışı olarak yazılmaz**
- **KDV kaydı oluşturmaz**

Eski faturaları veya geçmiş satın almaları tek tek girmen gerekmez.

Kurulumdan sonra günlük kullanım üç işlemden ibaret — ana sayfada yan yana:
**Satış Gir**, **Gider / Fatura Gir**, **Stok Alımı Gir**. Ana sayfadaki
**Ürünler ve Stoklar** alanından mevcut stoklara dokunup düzenleyebilirsin.

Sihirbazı Ayarlar'dan tekrar çalıştırabilirsin; kayıtların silinmez.

## Ne yapıyor

- Aylık satışları kanal bazında toplar (Trendyol / Shopify / Diğer)
- Gerçek ciro, toplam gider, gerçek kâr ve kâr marjını hesaplar
- Satış girdiğinde ürün ve **paketleme malzemelerini otomatik stoktan düşer**
- Stok alımında ortalama maliyeti günceller ve gideri kendiliğinden oluşturur
- Fire, kırık, numune ve sayım farklarını stok geçmişine işler
- Hangi malzemenin bitmek üzere olduğunu ve yaklaşık kaç siparişlik kaldığını gösterir
- Aylık / yıllık / kanal raporları üretir, CSV olarak dışa aktarır
- Gider ve stok alımlarına fatura fotoğrafı veya PDF eklenebilir
- Basit KDV takibi: hesaplanan / indirilecek / ödenecek veya devreden
- Basit alacak / ödenecek listesi

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

## Aylık hedef & ay sonu sonucu

Uygulama senden günlük satış girişi beklemez. Satışları ay sonunda tek
seferde girersin.

**Ay başında** ana sayfadaki **AYLIK SONUÇ** kartı hedefi gösterir. Satış
girilmediği sürece kâr/zarar rakamı gösterilmez — sadece gider girilmiş
olması o ay zarar edildiği anlamına gelmez:

```
AYLIK SONUÇ
Satış verisi henüz girilmedi
Kaydedilmiş gider        27.000 TL
Başa baş hedefi          yaklaşık 77 sipariş
Günlük ortalama hedef    3 sipariş

25.000 TL kâr hedefi    145 sipariş · günlük ortalama 5
50.000 TL kâr hedefi    212 sipariş · günlük ortalama 7
100.000 TL kâr hedefi   347 sipariş · günlük ortalama 12
```

Günlük rakam o ayın gerçek gün sayısına bölünür (30 gün, 31 gün, şubat 28).

**Ay sonunda** satışları girdiğinde aynı kart gerçek sonuca döner: başa baş
hedefi, gerçekleşen sipariş, gerçek ciro, gerçek gider, gerçek kâr/zarar,
kâr marjı ve başa baş hedefinin ne kadar üzerinde/altında kalındığı.

**Ara toplam isteğe bağlı ve gizli.** Normal kullanım ay sonunda tek seferde
satış girmektir. Ay bitmeden ara toplam girdiysen kartın altındaki
"Gelişmiş · Ara dönem verisi" bölümünden işaretlersin; sistem o zaman kalan
günü ve kalan sipariş hedefini hesaplar. İşaretlemezsen hiçbir tempo
tahmini yapılmaz.

### Hedef nereden çıkıyor

Sipariş başına ortalama katkı, **son tamamlanmış ayın** gerçek Trendyol /
Shopify ve ürün dağılımından hesaplanır ve sonuç "yaklaşık" olarak
gösterilir; hangi aya dayandığı kartta yazar. Bütün siparişler aynı
kârlılıktaymış gibi varsayılmaz.

İlk ayda geçmiş veri yoksa uydurma rakam verilmez — kartta kanal, ürün ve
ortalama sipariş tutarını soran küçük bir alan çıkar; hesap bu varsayıma
dayandığı açıkça yazılır ve ilk gerçek ay tamamlanınca kendiliğinden gerçek
veriye geçer.

```
katkı            = net satış − komisyon − kargo − hizmet bedeli
                              − ürün maliyeti − ambalaj − satışa bağlı giderler
sipariş başına   = katkı ÷ sipariş sayısı
başa baş         = sabit giderler ÷ sipariş başına katkı
X TL kâr için    = (sabit giderler + X) ÷ sipariş başına katkı
günlük ortalama  = gereken sipariş ÷ ayın gün sayısı
```

**Sabit ile değişken ayrımını sen belirlersin.** Her giderde "satış arttıkça
artar mı?" seçeneği var. Reklam varsayılan olarak **satışa bağlı** sayılır;
sabit bütçeyle çalışıyorsan "Sabit gider" seçersin. Ajans, muhasebeci, aylık
Shopify ücreti sabittir ve başa baş noktasını yukarı iter. Bu seçim **kârı
asla değiştirmez**, sadece başa baş noktasını değiştirir.

**Nakit çıkışı kâr değildir.** 500 koliye bu ay 5.000 TL ödemek, o tutarı bu
ayın kârından düşmek anlamına gelmez — kâra yalnızca o ay gerçekten satılan
ürünlerin maliyeti girer. Ödenen tutar ayrıca "bu ay ödenen (nakit çıkışı)"
olarak gösterilir. Başa baş hesabı kâr tarafını kullanır.

---

## KDV

Her satış, gider ve stok alımında **KDV oranı** (%20 / %10 / %1 / yok) ve
**tutar KDV dahil mi** seçilir. Sistem tutarı net ve KDV olarak ayırır.

**Kârlılık her zaman KDV hariç hesaplanır.** KDV ne gelir ne giderdir:

- Ciro, gider, kâr, kanalda kalan, başa baş — hepsi KDV hariç
- Stok maliyeti de KDV hariç: indirilecek KDV ödenecek KDV'den mahsup
  edildiği için ürün maliyetine yazılırsa kârlılık yanlış çıkar
- Nakit çıkışı KDV dahil kalır — cepten gerçekten o kadar para çıkar

Pazaryeri kesintileri satış fiyatının KDV dahil hali üzerinden alınır; kesinti
tutarının KDV'si indirilecek KDV'ye, net kısmı gidere gider.

Aylık raporda açılır **KDV durumu** kartı: hesaplanan KDV, indirilecek KDV,
önceki aydan devreden ve tahmini ödenecek KDV. İndirilecek fazlaysa
**sonraki aya devreden KDV** olarak taşınır ve ertesi ay mahsup edilir.
Bu bir tahmindir, beyanname değildir.

KDV oranı **her kayıtta ayrı ayrı** seçilir — %20 yalnızca varsayılandır ve
Ayarlar'dan değiştirilebilir. Pazaryeri kesintilerinin KDV oranı da her kanal
için ayrı tutulur ve kanal ayarlarından değiştirilebilir; sabit %20 varsayımı
yoktur. Bir kanalda kesinti KDV oranı girilmemişse KDV kartı uyarır.

İndirilecek KDV hiçbir yerde "geri alınacak para" veya şirket alacağı olarak
gösterilmez. Kullanılan tek ifadeler: **hesaplanan KDV**, **indirilecek KDV**,
**tahmini ödenecek KDV**, **sonraki aya devreden KDV**. Devreden KDV alacak
listesine girmez.

KDV takibi Ayarlar'dan kapatılabilir; kapalıyken hiçbir ekranda görünmez.

## Alacak / Ödenecek

Aylık raporda ikinci bir açılır kart: kanal ödemeleri, tedarikçi faturaları
ve diğer ödenecekler elle girilir; tahmini KDV otomatik eklenir. Cari hesap
değil, "kim bana borçlu, ben kime borçluyum" listesi.

---

## Ekran önizlemesi (Xcode'suz)

```bash
cd MirissaKit && swift run MirissaPreview ../onizleme
```

Bütün ekranları iPhone ölçüsünde PNG olarak `onizleme/` klasörüne çizer.
Tasarımı telefona kurmadan önce görmek için kullanılır.
