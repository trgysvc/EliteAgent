# Sistem Kararlılığı ve Self-Healing

EliteAgent, yerel modellerin kısıtlı kaynaklarını yönetmek ve hata durumlarında otonom olarak toparlanmak için gelişmiş motorlarla donatılmıştır.

## 1. Kendi Kendine İyileşen (Self-Healing) Motorlar
Sistem, bir hata oluştuğunda durmak yerine çözüm üretmeye odaklanır:
- **ToolLoopDetector v2:** LLM'in aynı hatalı döngüye girmesini (ping-pong, polling) SHA-256 hash takibi ile tespit eder. Kritik seviyede (30 adım) devreyi keserek orkestratörü farklı bir stratejiye zorlar.
- **AutoRecoveryEngine:** Özellikle OOM (Out Of Memory) durumlarında, VRAM'i boşaltıp sistemi `reload: true` flag'i ile otomatik olarak yeniden başlatır.
- **SelfHealingEngine (Shell):** Shell komutu hatalarında hatayı analiz eder (örneğin eksik bir paket) ve çözüm önerisini (örneğin `brew install`) planlayarak tekrar dener.

## 2. Dinamik Bağlam Yönetimi
Bellek basıncını ve bağlam penceresini (context window) yönetme stratejileri:
- **ContextWindowGuard:** 
  - **%70 Doluluk:** Kullanıcıyı uyarır ve planlamayı optimize eder.
  - **%85 Doluluk:** `ContextCompactionEngine`'i tetikler.
- **ContextCompactionEngine:** Bağlamı daraltırken "Must-Preserve" listesindeki kritik verileri (dosya yolları, UUID'ler, TODO'lar) koruyarak özetleme yapar.
- **AdaptiveTaskChunker:** Çok büyük iş yüklerini (örneğin 100+ dosya analizi), donanım durumunu (`HardwareMonitor`) ve `ContextBudget`'i gözeterek küçük, yönetilebilir parçalara böler. Her parça, bağlamın sürekliliğini sağlamak için bir önceki parçanın özetini taşır.

## 3. Donanım Duyarlı Koruma (Thermal Guard)
- macOS'un `ProcessInfo.thermalState` API'si ile entegre çalışır.
- Sistem ısındığında (Serious/Critical), inference döngüsüne otonom `Task.sleep` gecikmeleri ekleyerek GPU yükünü ve ısıyı düşürür.
