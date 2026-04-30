# 'Triple-Threat' Mimari Derin Dalış

EliteAgent'ın operasyonel üstünlüğü, üç temel sütun üzerine inşa edilmiş olan **'Triple-Threat'** mimarisinden gelir: Deterministik Akıl Yürütme, Vizyon Tabanlı Tarayıcı ve Deneyimsel Bellek.

## 1. Akıl Yürütme (Reasoning Engine)
EliteAgent, karmaşık görevleri çözmek için çok katmanlı bir ajan hiyerarşisi kullanır:
- **PlannerAgent:** Görevi analiz eder ve atomik adımlara böler.
- **ExecutorAgent:** Belirlenen adımları araç setini (UBID-native tools) kullanarak icra eder.
- **GuardAgent:** Çıktıları ve güvenliği gerçek zamanlı denetler.
- **Orchestrator:** Bu ajanlar arasındaki koordinasyonu ve durum geçişlerini yönetir.

## 2. Vizyon Tabanlı Tarayıcı (BrowserAgent)
Geleneksel, dış bağımlılıklı çözümlerin (chrome-mcp vb.) aksine EliteAgent, tamamen yerel bir tarayıcı otomasyonu sunar:
- **Safari + WebKit Native:** Apple'ın `BrowserAgent` mimarisi ile Safari üzerinden vizyon tabanlı kontrol sağlar.
- **CUA (Computer Use Agent) Katmanı:** Safari'nin `AXUIElement` (Accessibility) ve WebKit DOM ağacını ikili bir katman olarak kullanır. Bu sayede "gördüğü" elemanlarla etkileşime girebilir.
- **Zero Middleware:** Harici npm paketlerine ihtiyaç duymadan doğrudan sistem çağrılarıyla çalışır.

## 3. Deneyimsel Bellek (Experiential Memory)
Ajanın geçmiş hatalardan ders almasını ve bağlamı korumasını sağlayan katman:
- **TrajectoryRecorder:** Her oturumun eylemlerini, araç çıktılarını ve döngü tespitlerini **Binary .plist** formatında kaydeder. Bu, sistemin "kara kutusu"dur.
- **MemoryTool:** Uzun dönemli deneyimleri ve kullanıcı tercihlerini semantik olarak saklar.
- **Must-Preserve Kuralları:** Bağlam sıkıştırması (compaction) sırasında dosya yolları, kritik hata mesajları ve bekleyen görevlerin asla silinmemesini garanti eder.

---
*Bu mimari, EliteAgent'ın sadece bir LLM wrapper'ı değil, gerçek bir otonom sistem olmasını sağlar.*
