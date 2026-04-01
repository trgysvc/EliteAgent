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

### TEST 11: Hardware Stress & Thermal Throttling
**Kapsam**: `ProcessInfo.thermalState`, `Adaptive Throttling`, `Recovery Logic`.

> "Ajan, şu anki termal durumunu (`get_system_telemetry`) analiz et. Eğer sistem 'Nominal' ise, yerel zekandan (Titan) çok uzun bir teknik makale yazmasını ve bu sırada GPU görselleştirmesini (Neural Sight) %100 kapasiteye çekmesini iste. Yazım sırasında sistem ısınırsa, 'Adaptive Throttling'in devreye girip girmediğini termal loglardan (`~/Library/Logs/EliteAgent`) teyit et."

---

### TEST 12: Neural Sight "Awaken" States & Integrity
**Kapsam**: `ModelSetupManager`, `SHA-256`, `Triple Buffering Sync`.

> "Titan Engine'in uyanış sürecini test et:
> 1. Model dosyalarının bütünlüğünü `ModelSetupManager` üzerinden SHA-256 ile doğrula.
> 2. Doğrulama sırasında Neural Sight'ın 'Verifying' (Glitch/Jitter) efektini gösterip göstermediğini kontrol et.
> 3. `InferenceActor` yüklendiğinde 'Stable Glow' durumuna geçişi onayla."

---

### TEST 13: Titan v7.0 Offline Reasoning
**Kapsam**: `MLXLLM.ModelContainer`, `ChatML`, `Context Clarity`.

> "Internetini kapat (Offline) ve şu mantıksal problemi Titan Engine ile çöz: 'Bir kutuda 3 kırmızı, 2 mavi top var. Gözü kapalı en az kaç top çekersen kesinlikle aynı renkten 2 topun olur?' Qwen 2.5'in ChatML formatını (system/user/assistant) doğru işleyip işlemediğini ham log çıktılarıyla doğrula."

---

### TEST 14: Chroma CENS Cover Detection (v7.1)
**Kapsam**: `ChromaEngine.createCENS`, `L1-Smooth-L2 Normalization`, `Fingerprinting`.

> "Müzik koleksiyonumdaki bir şarkıyı ve onun cover versiyonunu (veya remixini) `MusicDNATool` ile analiz et.
> 1. Her iki parça için **Chroma CENS** parmak izlerini oluştur.
> 2. Enerji normalize edilmiş bu verileri (L1 -> Smooth -> L2) karşılaştırarak aralarındaki harmonik benzerlik skorunu hesapla.
> 3. CENS'in ses seviyesi farklarından etkilenmediğini 'EliteAudio Card' üzerinde teknik olarak kanıtla."

---

### TEST 15: pYIN Vocal Pitch Stability (Phase 1.5)
**Kapsam**: `pYINEngine`, `Viterbi Decoding`, `Octave Jump Suppression`.

> "Bir vokal kaydını (acapella) analiz et.
> 1. Standart YIN yerine **Probabilistic YIN (pYIN)** kullanarak temel frekans (F0) takibini yap.
> 2. Viterbi algoritmasının oktav atlamalarını (octave jumps) nasıl engellediğini ve geçişlerin ne kadar pürüzsüz olduğunu raporla.
> 3. Pitch eğrisini `~/Documents/AI Works/vocal_dna.json` olarak kaydet."

---

### TEST 16: Time Stretch & Pitch Shift Quality (Phase 1.5)
**Kapsam**: `PhaseVocoder`, `Transient Preservation`, `Elastic Audio`.

> "Seçtiğim bir ses dosyasını kalitesini bozmadan %80 hızına düşür (Time Stretch) ve 2 yarım ses (semitones) yukarı kaydır (Pitch Shift).
> 1. **Phase Vocoder** motorunun 'phase locking' özelliğini kullanarak transient'lerin keskinliğini koruduğunu doğrula.
> 2. İşlenmiş dosyayı `~/Desktop/Elite_Stretched.wav` olarak dışa aktar ve sonucun 'Librosa' kalitesinde olduğunu onayla."

---
*EliteAgent Core · v7.1 Audio Intelligence · 2026*
