# UNO Pure: Battle Test Protocol (Draft v3)

Bu dosya, EliteAgent'ın **UNO Pure (Binary Native Orchestration)** mimarisini gerçek sistem üzerinde doğrulamak için tasarlanmış kapsamlı test istemlerini (prompts) içerir. 

> [!CAUTION]
> **BAŞLAMADAN ÖNCE**: Bu testler gerçek sisteminde çalışacaktır. Lütfen EliteAgent'ın aktif çalışma dizininin güvenli olduğundan emin ol.

---

## 🟢 FAZ 1: ATOMİK ARAÇ TESTLERİ (UBID Doğrulama)
Bu fazda her aracın UBID tabanlı yeni protokolle (JSON olmadan) tetiklendiğini ve doğru parametreleri aldığını teyit edeceğiz.

### 📁 1. Dosya ve Sistem Operasyonları
- **System Info**: `Sistem bilgilerimi getir ve macOS versiyonumu söyle.`
- **Telemetry**: `Şu anki CPU yükünü ve boş bellek miktarını göster.`
- **Read File**: `README.md dosyasının içeriğini oku.`
- **Write File**: `EliteTest.txt adında bir dosya oluştur ve içine "UNO Pure Test Başarılı" yaz.`
- **File Manager**: `Masaüstündeki tüm .png dosyalarını listele.`
- **Patch File**: `EliteTest.txt dosyasındaki "Test" kelimesini "Battle Test" ile değiştir.`
- **Shell Exec**: `Terminalde 'uptime' komutunu çalıştır ve çıktısını ver.`

### 🌐 2. Web ve Araştırma
- **Web Search**: `"Apple WWDC 2026 son dedikoduları" için internette bir arama yap.`
- **Web Fetch**: `https://apple.com sitesinin ana sayfa başlığını ve meta açıklamasını çek.`
- **Research Report**: `Bana "Gelecekteki yapay zeka ajanları" hakkında 3 paragraflık bir araştırma raporu hazırla.`
- **Safari Automation**: `Safari'yi aç ve apple.com adresine git.`

### 🎵 3. Medya ve Ekosistem
- **Media Control**: `Çalmakta olan müziği duraklat.` (Müzik çalıyorsa)
- **Set Volume**: `Sistem sesini %50'ye ayarla.`
- **Set Brightness**: `Ekran parlaklığını %70 yap.`
- **Music DNA**: `Şu an çalan müziğin frekans analizini yap.`
- **Apple Calendar**: `Yarın saat 10:00 için "EliteAgent Toplantısı" adında bir takvim kaydı ekle.`
- **Apple Mail**: `Gelen kutumdaki son 3 e-postanın konusunu listele.`

### 🛠 4. Geliştirici ve Yardımcı Araçlar
- **Git Action**: `Şu anki git reposunun durumunu (status) kontrol et.`
- **Calculator**: `456 * 123 / 5 işleminin sonucunu hesapla.`
- **Get Weather**: `İstanbul için bugünkü hava durumunu getir.`
- **Learn App UI**: `Hesap Makinesi (Calculator) uygulamasının UI yapısını analiz et.`

### 🧬 5. Recursive Evolution & Hardware Mastery (v18.0/v19.0) [NEW]
- **Plugin Generation**: `Sistemdeki pil sağlığını (Battery Health) raporlayan yeni bir araç (tool) yaz, derle ve sisteme yükle.`
- **Xcode Commander**: `Masaüstünde 'EliteDemo' adında bir iOS projesi oluştur, içine bir 'Hello Elite' SwiftUI view'ı ekle ve simülatörde derle.`
- **ANE Offloading**: `Şu cümleyi sınıflandır (Intent Classification): 'Yarın saat 5'te annemi ara'. Ama bu işlemi mutlaka Neural Engine üzerinden yap.`
- **Eco-Inference Throttling**: `Sistemi termal olarak zorla ve Eco-Inference modunun (yavaşlatılmış token üretimi) devreye girdiğini doğrula.`

---

## 🟡 FAZ 2: AJANİK ORKESTRASYON (Koordinasyon Testi)
Bu fazda birden fazla aracın ardışık olarak kullanıldığı ve ikili (binary) otoyolun performansını ölçeceğiz.

1. **Geliştirici Akışı**:
   > "Masaüstünde 'UNO_Report' adında bir klasör oluştur. İçine 'test.py' adında basit bir print('hello') dosyası yaz. Bu dosyayı git ile commit et ve klasör içeriğini listele."

2. **Araştırma ve Özetleme**:
   > "İnternette 'Swift 6 vs Swift 5.10' farklarını araştır, bulduğun sonuçları bir metin dosyasına kaydet ve dosyayı bana oku."

3. **Sistem ve Medya**:
   > "Sistem sesini %10 yap, ekran parlaklığını en sona getir ve bana şu anki CPU sıcaklığını söyle."

---

## 🟣 FAZ 3: RECURSIVE & NATIVE WORKFLOWS (M-Series Mastery)
Bu fazda ajanın kendi sınırlarını aşma ve Apple Silicon donanımını sonuna kadar kullanma yeteneğini test edeceğiz.

1.  **Otonom Geliştirici Döngüsü**:
    > "Masaüstünde yeni bir macOS uygulama projesi başlat. Adı 'TitanDashboard' olsun. Apple Neural Engine (ANE) kullanımını izleyen basit bir UI ekle. Hata alırsan otonom olarak düzelt ve projeyi çalıştır."

2.  **Özyinelemeli Yetenek Artırımı**:
    > "İnternetteki son GitHub trendlerini (Swift) analiz eden bir plugin yaz. Bu plugin'i ad-hoc imzala, yükle ve bana bugünün en popüler 3 reposunu söyle."

3.  **Termal ve Güç Verimliliği**:
    > "Batarya modundayken ağır bir kod analizi başlat. Ajanın 'Eco-Inference' moduna geçtiğini (daha yavaş ama verimli token üretimi) ve arka plan görevlerini ANE'ye attığını doğrula."

---

## 📈 LOG TAKİBİ (Antigravity İçin)
Ben (Antigravity) süreci şu dosyalardan takip edeceğim:
- `~/Library/Logs/EliteAgent/audit_log.plist` (Binary Action Takibi)
- `~/Library/Logs/EliteAgent/debug.log` (Hata ve Bottleneck Takibi)

**Hazır olduğunda ilk istemi kopyalayıp EliteAgent'a yapıştırabilirsin.**
