# EliteAgent Wiki

EliteAgent, Apple Silicon üzerinde koşan, Swift 6 ve MLX tabanlı yerel bir yapay zeka asistanı ve orkestrasyon motorudur. Bu wiki, projenin mimarisini, dökümantasyonunu ve geliştirme süreçlerini merkezi bir noktada toplar.

## Proje Amacı
EliteAgent'ın temel amacı, Apple ekosisteminin sunduğu yerel donanım güçlerini (Neural Engine, Unified Memory) kullanarak, verileri dış dünyaya sızdırmadan, yüksek performanslı ve güvenli bir otonom ajan deneyimi sunmaktır.

## Wiki İçeriği
- [Yazılım Üretim Kuralları](rules.md)
- [Hot Memory (Güncel Durum)](h.md)

### 🏗 Mimari ve İnceleme Raporları
- [Mimari Genel Bakış](wiki/architecture_overview.md)
- [Mimari Derin Dalış (Triple-Threat)](wiki/architecture_deep_dive.md)
- [Sistem Kararlılığı ve Self-Healing](wiki/system_stability.md)
- [Proje Gelişim Tarihçesi (Evolution)](wiki/evolution.md)
- [Gap Analizi ve Gelişim](wiki/gap_analysis.md)
- [Stratejik Performans İyileştirme Önerileri (v7.0+)](wiki/performance_optimization_report.md)

### 📚 Temel Kavramlar ve Teknik Standartlar (Concepts)
- [Distributed Actors ve UNO İzolasyon Mimarisi](concepts/distributed_actors.md)
- [MLX Swift ve Unified Memory Yönetimi](concepts/mlx_swift_unified_memory.md)
- [MLX Metal Mimarisi ve GPU Internals](concepts/mlx_metal_internals.md)
- [LLM Çıkarım Standartları (KV Cache, RoPE)](concepts/llm_inference_mechanics.md)
- [Swift API Design Standartları](concepts/swift_api_standards.md)
- [XPC ve Native IPC Standartları](concepts/xpc_native_ipc.md)
- [MLX Swift Temel Kavramlar](concepts/MLX_Swift_Core.md)

### 🛠 Araçlar ve Entegrasyonlar
- [Araç Seti Haritası (Tooling Landscape)](wiki/tooling_landscape.md)
- [Blender Bridge Pro-Grade Stabilizasyonu](wiki/blender_bridge_evolution.md)

## Kaynaklar (Ham Veriler - Raw)

### 📜 Geliştirme Geçmişi
- [[GeliştirmeKonuşmaları]] - Tüm geliştirme sürecinin detaylı kayıtları.
- [[devlog]] - Günlük teknik notlar ve ilerleme raporları.
- [[CHANGELOG]] - Sürüm değişiklikleri ve önemli güncellemeler.
- [[README]] - Projenin genel başlangıç dökümanı.

### 📐 Gereksinimler ve Tasarım
- [[EliteAgent_PRD_v5.2]] - Ürün gereksinim dökümanı.
- [[all_features]] - Tüm sistem özelliklerinin listesi.
- [[Audio Intelligence Platform]] - Ses zekası platformu vizyonu.

### 🛠️ Araçlar ve Bilgi Bankası
- [[EliteAgentTools]] - Ana araç seti dökümantasyonu.
- [[MusicTools]] - Müzik ve ses işleme araçları.
- [[KNOWLEDGE_BlenderAPI]] - Blender API entegrasyon rehberi.

### ⚙️ Sistem Yapılandırması ve Testler
- [[UNO_BATTLE_TEST]] - UNO protokolü stres ve yetenek testleri.
- [[Package.swift]] - Swift paket yapılandırması.
- [[project_tree]] - Proje dizin yapısı.
- [[entry_point_code]] - Sistemin giriş noktası kod örnekleri.

