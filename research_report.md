# Yüksek Performanslı Ajan Mimari Analizi (Niyet ve Orkestrasyon)

Talebiniz üzerine, belirttiğiniz 3 farklı repodaki (`openclaw`, `learn-coding-agent`, `claurst`) "Niyet Analizi" (Intent Detection) ve "Araç Orkestrasyonu" metodolojilerini inceledim. Amacımız; "Sohbet mi, İşlem mi?" ayrımını bu projelerin nasıl yönettiğini anlayıp, EliteAgent için geliştirdiğimiz öz mimari ile karşılaştırmaktır.

## 1. OpenClaw: "Gateway Tabanlı Dinamik Enjeksiyon"

`openclaw` projesi (`/src/gateway/` altındaki dosyalar) araç kullanımı kararlarını sabit bir prompt'tan ziyade **dinamik HTTP Gateway kurallarıyla** yönetiyor:

*   **Enjeksiyon Mantığı:** `openresponses-http.ts` dosyasında, kullanıcının talebine (veya API kurallarına) göre sisteme `extraSystemPrompt` (Ek Sistem İstemi) enjekte ediliyor.
*   **Zorunlu Yönlendirme Katmanı:** Eğer sistem `tool_choice=required` bayrağı alırsa, LLM'in promptuna anında şu satır ekleniyor: `"You must call one of the available tools before responding."` (Yanıt vermeden önce mevcut araçlardan birini kullanmalısın).
*   **Avantajı/Çözümü:** LLM'in kararına tamamen bırakmak yerine, aracı sistem (Gateway), "Eğer dış müdahale lazımsa, LLM'e kesin emir ver ve kaçış yolu bırakma" mimarisini kullanıyor.

## 2. learn-coding-agent: "Parçalı Prompt ve Anti-Gevezelik (Anti-Comment) Güvenliği"

Bu proje, EliteAgent'ta az önce yaşadığımız "iş yapmak yerine yaptığı işi anlatma" (gevezelik) sorununu derinlemesine tecrübe etmiş ve sistemleştirmiş.

*   **fetchSystemPromptParts():** Tüm sistem kuralları dev bir metin yerine parçalara ayrılmış durumda (İzinler, Araçlar, Hafıza).
*   **Model-Spesifik Aşırı Yorum (Over-commenting) Koruması:** Belgelerde (Örn: `02-hidden-features-and-codenames.md`) özellikle Capybara (Claude) gibi bazı modellerin gereksiz yere açıklama yapma eğilimi olduğu belirtilmiş. Bunu çözmek için `constants/prompts.ts` içinde özel **anti-over-commenting prompt** (Aşırı açıklama yapmayı engelleyen özel talimatlar) yazılmış.
*   **Avantajı/Çözümü:** Ajanın kararsızlık anında sohbet moduna geçip öğretici tavırlar sergilemesine karşı özel prompt yamaları ("Sadece kodu yaz, açıklama yapma") uygulanmış. Bizim `SystemPrompts.swift` içerisine eklediğimiz "Gevezelik yapma, doğrudan JSON üret" kuralıyla %100 örtüşüyor.

## 3. Claurst (Rust Tabanlı Ajan): "Koordinatör / İşçi Ayrımı (Hard-Routing)"

`claurst` (`crates/query/src/coordinator.rs`), kararı LLM'in otonomisine bırakmanın risklerini en aza indirmek için **Fiziksel Rol Bölünmesi** uyguluyor.

*   **Coordinator Mode (Orkestratör):** LLM, eğer `Coordinator` olarak başlatılmışsa, ona tüm araçlar verilmiyor. Araç listesi filtreleniyor (`filter_tools_for_mode`). Koordinatöre sadece alt-ajan yaratma (`Agent`, `SendMessage`) yetkisi veriliyor. Kod çalıştırma (`Bash`) aracı açıkça yasaklı (`COORDINATOR_BANNED_TOOLS`).
*   **Kısıtlayıcı Prompt (coordinator_system_prompt):** Prompt şeması şöyledir: *"Sen bir orkestratörsün. İşleri Paralel alt ajanlara pasla."*
*   **Avantajı/Çözümü:** EliteAgent'ta "Mod Çakışması" yaşamıştık (Hem asistan olup hem işlem motoru olmaya çalışmak). Claurst bu çakışmayı "Orkestratör çalışmaz, sadece delege eder" diyerek kökten çözmüş. Hata payı sıfıra indirilmiş, otonomi rollere dağıtılmış.

---

## 🎯 Sonuç ve EliteAgent İçin Çıkarımlar

Araştırdığım bu 3 modern proje, LLM temelli sistemlerin şu doğasını kanıtlıyor: **"LLM'ler hem dost canlısı asistan hem de kusursuz bir terminal komutçusu rolünü tek bir odakta iyi oynayamaz."**

1.  **OpenClaw** bu sorunu dinamik prompt enjeksiyonu (`extraSystemPrompt`) ile çözmüş.
2.  **Learn-coding-agent** bu sorunu "Gevezeliği Yasaklayan Kural Setleri" ile çözmüş.
3.  **Claurst** bu sorunu ajanların rolünü donanımsal olarak bölerek çözmüş.

**EliteAgent İçin Ne İfade Ediyor?**
Biz de `SystemPrompts.swift` dosyasında aslında bu üç sistemin bir sentezini uyguladık:
*   *Learn-coding-agent gibi:* Gevezeliği yasaklayan kesin anti-comment kuralları koyduk.
*   *OpenClaw gibi:* İhtiyaç duyduğunda JSON üretmek dışında bir opsiyonu olmadığını enjekte ettik ("Araç Kullanım Durumu").

Araştırma tamamlandı. Bu 3 sistemin tasarımları ışığında, EliteAgent'ın şu anki güncel durumunu nasıl yönlendirmek istersiniz? Tartışmaya hazırım.
