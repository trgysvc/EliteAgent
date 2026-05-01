# 'Triple-Threat' Mimari Derin Dalış

EliteAgent'ın operasyonel üstünlüğü, üç temel sütun üzerine inşa edilmiş olan **'Triple-Threat'** mimarisinden gelir: Deterministik Akıl Yürütme, Vizyon Tabanlı Tarayıcı ve Deneyimsel Bellek.

## 1. Akıl Yürütme (Reasoning Engine & UNO Backbone)
EliteAgent, karmaşık görevleri çözmek için çok katmanlı bir ajan hiyerarşisi kullanır:
- **Distributed Actor Isolation:** Tüm ajanlar Swift 6'nın `distributed actor` yapısı ile izole edilmiştir. IPC (Inter-Process Communication) süreçleri XPC üzerinden derleme zamanı (compile-time) güvenliği ile yürütülür.
- **UNO Pointer Migration:** v7.0 ile gelen bu mimari, aktörler arası veri transferinde kopyalama (copying) işlemini ortadan kaldırır. `SharedMemoryPool` üzerinden sadece bellek işaretçileri (pointers) aktarılarak sıfır maliyetli (Zero-Copy) bir veri yolu oluşturulmuştur.
- **Planner/Executor/Guard Hierarchy:** Görevler atomik adımlara bölünür, UBID-native araçlarla icra edilir ve gerçek zamanlı denetlenir.

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

## 4. Düşük Seviyeli Optimizasyon & Donanım Kısıtları (Hardware Constraints)
v7.0 çıkarım motoru, "Donanımı Bir Kısıt Olarak Kabul Et" felsefesiyle çalışır:
- **Lazy Inference & Graph Fusion:** Akıl yürütme katmanı, MLX'in [Metal Mimarisi](../concepts/mlx_metal_internals.md) ile entegre çalışır. Gereksiz hesaplamalar lazy evaluation ile engellenir ve kernel fusion ile GPU verimliliği maksimize edilir.
- **KV Cache & RoPE Precision:** [LLM Çıkarım Standartları](../concepts/llm_inference_mechanics.md), modelin bağlam penceresini ve dikkat (attention) mekanizmasını doğrudan donanımsal limitlerle (VRAM, MPS optimizasyonları) ilişkilendirir.
- **Hafıza Mühürleme (Memory Anchoring):** Ajan tasarlanırken, model ağırlıkları ve çalışma belleği Unified Memory üzerinde mühürlenmiş kabul edilir. Bu, ajanın "bellek kısıtlarını" birer değişken değil, deterministik sabitler olarak görmesini sağlar.

---
*Bu mimari, EliteAgent'ın sadece bir LLM wrapper'ı değil, gerçek bir otonom sistem olmasını sağlar.*
