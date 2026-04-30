# Mimari Genel Bakış

EliteAgent, Apple ekosistemi üzerinde **Swift 6** ve **Native Sistemler** kullanılarak inşa edilmiş, yüksek performanslı ve modüler bir yapay zeka orkestrasyon sistemidir.

## 1. Modüler Yapı (Swift Package Manager)

Proje, sorumlulukların net bir şekilde ayrıldığı çoklu target yapısına sahiptir:

- **EliteAgent (App):** SwiftUI tabanlı ana uygulama katmanı. Kullanıcı arayüzünü ve uygulama yaşam döngüsünü yönetir.
- **EliteAgentCore:** Sistemin kalbidir. LLM yönetimi, Agent Engine (Orchestrator, Planner, Executor), hafıza yönetimi ve güvenlik protokollerini içerir.
- **EliteAgentUI:** Uygulama genelinde kullanılan ortak UI bileşenlerini barındıran kütüphane.
- **EliteAgentXPC:** Güvenlik ve performans için izole edilmiş süreçler arası iletişim (Inter-Process Communication) sağlayan XPC executable.
- **Elite (CLI):** Sistemin komut satırı arayüzü.
- **UMA-Bench:** Apple Silicon üzerinde Unified Memory Architecture (UMA) performansını ölçen araç.

## 2. Swift 6 ve Concurrency

Sistem, Swift 6'nın getirdiği **Strict Concurrency** kurallarına tam uyumlu olarak tasarlanmıştır:
- **Actors & Distributed Actors:** `InferenceActor`, `InternalMonologueActor` gibi bileşenler veri yarışlarını (data races) önlemek için Actor modelini kullanır.
- **Async/Await:** Tüm asenkron operasyonlar modern Swift concurrency yapısıyla yönetilir, `DispatchQueue` yerine yapılandırılmış asenkronluk tercih edilmiştir.

## 3. Yerel Güç: Apple Silicon & MLX

EliteAgent, üçüncü parti bulut servislerine bağımlılığı minimize eder:
- **MLX Swift:** Apple Silicon (M-serisi) çiplerin Neural Engine ve GPU güçlerini doğrudan kullanan yerel çıkarım (local inference) motoru.
- **Unified Memory Architecture (UMA):** Bellek yönetiminde Apple Silicon'un ortak bellek yapısından maksimum verim alacak şekilde optimize edilmiştir.

## 4. UNO (Unified Native Orchestration)

Sistemin iletişim omurgası olan UNO, geleneksel JSON tabanlı iletişim yerine **Binary-Native** bir yol izler:
- **XPC Services:** Modüller arası iletişim Apple'ın XPC teknolojisiyle izole ve güvenli şekilde yapılır.
- **Binary Only:** Performans kaybını önlemek için veriler sistem içinde binary formatta taşınır.

- **SecuritySentinel:** Biyometrik doğrulama ve veri sızıntısı koruması sağlar.
- **GuardAgent:** Yapay zeka çıktılarının sistem güvenliğini tehdit etmediğini gerçek zamanlı denetler.

---

### Teknik Uygulama ve Yapı
- **Paket Yapılandırması:** Sistemin modüler yapısı ve bağımlılıkları [[Package.swift]] dosyasında tanımlanmıştır.
- **Dosya Dizini:** Projenin hiyerarşik yapısını [[project_tree]] üzerinden inceleyebilirsiniz.
- **Kod Giriş Noktası:** Uygulamanın nasıl ayağa kalktığını anlamak için [[entry_point_code]] örneklerine bakabilirsiniz.

