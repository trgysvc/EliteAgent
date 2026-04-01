# 🧪 EliteAgent: Tam Kapsamlı Test Protokolü (v7.0 Master Protocol)

Bu döküman, EliteAgent'ın tüm çekirdek, zeka ve araç katmanlarını hatasız doğrulamak için hazırlanmış **nihai** test protokolüdür. Lütfen bu promptları sırayla chat penceresine kopyalayarak testi başlatınız.

---

### TEST 1: Sistem Mimarisi, XPC ve HIG Uyumluluğu
**Kapsam**: `PathConfiguration`, `EliteAgentXPC`, `WriteFileTool` (Absolute Path), `ReadFileTool`.

> "EliteAgent, şu adımları hatasız uygula:
> 1. `~/Library/Application Support/EliteAgent` klasöründeki konfigürasyonu kontrol et.
> 2. `~/Documents/AI Works/system_architect.txt` adıyla 'XPC + HIG Success: v7.0' yazan bir dosya oluştur.
> 3. Bu dosyayı `read_file` ile oku ve içeriğini doğrula.
> 4. Sistem loglarının doğru HIG klasöründe (`~/Library/Logs/EliteAgent`) oluştuğunu teyit et."

---

### TEST 2: Titan Yerel Zeka ve Hibrit Akıl Yürütme
**Kapsam**: `InferenceActor`, `MLX Provider` (4-bit), `Hybrid Switch`, `Neural Sight (Metal)`.

> "Ajan, internet bağlantını simüle olarak kes (Titan Offline mode) ve şu soruyu yerel zekanla (Titan) cevapla: 'EliteAgent mimarisindeki SignalBus yapısı, sistem darboğazını nasıl yönetir?' Cevabını verirken **Neural Sight** (nokta bulutu) görselleştirmesini en yüksek yoğunlukta başlat ve Metal shader'larının performansını chatte onayla."

---

### TEST 3: Donanım Koruma ve Termal Watchdog
**Kapsam**: `System Watchdog`, `ThermalState`, `MemoryPressure`, `HardwareProtectionReflex`.

> "Sistemimin tüm donanım telemetrisini (`get_system_telemetry`) analiz et. Şu anki CPU ısınma durumunu ve RAM baskısını raporla. Ardından, kasıtlı olarak yoğun bir işlem (örneğin ağır bir MIR analizi) başlatıldığında 'Hardware Protection Reflex'in sistemi nasıl koruyacağını teknik detaylarıyla anlat."

---

### TEST 4: Music DNA — Biyolojik Spektral Analiz (EliteMIR)
**Kapsam**: `STFTEngine`, `MelFilterBank`, `CQTEngine`, `YINEngine`, `HPSSEngine`, `MFCCEngine`, `RhythmEngine`, `StructureEngine`.

> "Masaüstündeki bir müzik dosyasını `MusicDNATool` ile derinlemesine analiz et.
> 1. **EliteMIR Engine** kullanarak BPM, Key (YIN), CQT spektrumu ve Harmonik/Perküsif (HPSS) oranlarını hesapla.
> 2. Şarkının yapısal bölümlerini (Verse, Chorus, Bridge) `StructureEngine` ile tespit et.
> 3. `~/Documents/AI Works` klasörüne tüm spektral verileri içeren 'Full Biologic Report' oluştur."

---

### TEST 5: Forensic DNA (Adli Röntgen)
**Kapsam**: `ForensicDNAEngine`, `mdls`, `afinfo`, `Standardized Reporting`.

> "Analiz ettiğin müzik dosyasının dijital parmak izini taranması için **Forensic Röntgen** motorunu çalıştır.
> 1. Dosyanın `WhereFroms` verisi (indirildiği URL) ve `Encoder` (LAME/iTunes) bilgilerini bul.
> 2. Dijital imzaların doğruluğunu raporla.
> 3. Bu adli verileri Music DNA raporuna entegre et ve sohbette 'Röntgen Card' arayüzünü göster."

---

### TEST 6: Otonom Kod Forge (Patch & Git)
**Kapsam**: `PatchTool` (Atomik Diff), `GitTool` (Autonomous Commit).

> "Proje dizinindeki `all_features.md` dosyasını oku. Dosyaya `PatchTool` kullanarak 'Verified: [Mevcut Tarih]' satırını ekle. İşlem başarılıysa `GitTool` kullanarak bu güncellemeyi 'feat: validated master feature audit' mesajıyla commit et ve repo statusunu bana raporla."

---

### TEST 7: Web Madenciliği ve PDF/DOCX Entegrasyonu
**Kapsam**: `BraveSearch`, `WebFetch` (MD Converter), `ReadFileTool` (Binary).

> "Brave Search üzerinden 'Next-gen MIR (Music Information Retrieval) architectures 2026' konusunu araştır. Bulduğun web sayfalarını Markdown'a çevirip oku. Eğer sistemde mevcutsa bir teknik PDF dökümanını da `read_file` ile analiz ederek turn-key bir piyasa araştırma raporu hazırla."

---

### TEST 8: WhatsApp ve İletişim Otomasyonu
**Kapsam**: `MessengerTool` (WhatsApp UI Automation), `MailTool`, `CalendarTool`.

> "Önce `apple_calendar` üzerinden bugünkü boşluklarımı kontrol et. Ardından `MessengerTool` kullanarak (WhatsApp) ['Baban' seçilen alıcıya] 'Baba, EliteAgent projesi v7.0 tam stabilite testlerinden başarıyla geçti. Akşam detayları konuşuruz.' mesajını otonom olarak gönder."

---

### TEST 9: Bilgisayarlı Görü (Vision Analyzer)
**Kapsam**: `ImageAnalysisTool`, `Vision OCR`, `UI Coordination`.

> "Sana verdiğim ekran görüntüsünü (veya o anki ekran kaydını) `ImageAnalysisTool` ile analiz et. Görseldeki tüm interaktif butonların koordinatlarını ve üzerindeki metinleri (OCR) çıkartarak bir 'UI Map' dosyası oluştur."

---

### TEST 10: Medya ve Sistem Kontrolü
**Kapsam**: `MediaController` (Apple Music), `AppDiscovery`, `System Performance`.

> "Apple Music üzerinde 'Epic Orchestral' bir parça çalmaya başla. Ses seviyesini %70'e getir. Ardından `AppDiscovery` kullanarak sistemdeki Xcode uygulamasının versiyonunu bul ve bu bilgileri içeren bir sistem özeti sun."

---
*EliteAgent Core · v7.0 Full Master Suite · 2026*
