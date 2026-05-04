# EliteAgent Wiki

EliteAgent, Apple Silicon üzerinde koşan, Swift 6 ve MLX tabanlı yerel bir yapay zeka asistanı ve orkestrasyon motorudur. Bu wiki, projenin mimarisini, dökümantasyonunu ve geliştirme süreçlerini merkezi bir noktada toplar.

**Versiyon:** v8.1 "Titan Optimized" | **Güncelleme:** 2026-05-04

## Proje Amacı
EliteAgent'ın temel amacı, Apple ekosisteminin sunduğu yerel donanım güçlerini (Neural Engine, Unified Memory) kullanarak, verileri dış dünyaya sızdırmadan, yüksek performanslı ve güvenli bir otonom ajan deneyimi sunmaktır.

---

## ⛔ Kurallar (Her AI Ajan Okumalı)
- [**Yazılım Üretim Kuralları — ZORUNLU**](rules.md) ← JSON yasağı, DispatchQueue yasağı, UNO kuralları

---

## Wiki İçeriği

### 🏗 Mimari ve İnceleme Raporları
- [**Kapsamlı Teknik Audit Raporu (2026-05-02)**](wiki/audit_report_2026-05-02.md)
- [Mimari Genel Bakış](wiki/architecture_overview.md)
- [Mimari Derin Dalış (Triple-Threat)](wiki/architecture_deep_dive.md)
- [Sistem Kararlılığı ve Self-Healing](wiki/system_stability.md)
- [Proje Gelişim Tarihçesi (Evolution)](wiki/evolution.md)
- [Gap Analizi ve Gelişim](wiki/gap_analysis.md)
- [v3-Native Migration Rehberi (v7.1+)](wiki/v3_migration_guide.md)

### 🚀 Güncel Uygulama Dökümanları (v8.x)
- [**Native Tool Calling — Uygulama Rehberi**](wiki/native_tool_calling.md) ← YENİ (2026-05-04)
- [**Performans Optimizasyonları — Uygulama Raporu**](wiki/performance_optimization_report.md) ← GÜNCELLENDİ (2026-05-04)

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

---

## Hot Memory (Güncel Durum)
- [Güncel Durum ve Bağlam](h.md)

---

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
