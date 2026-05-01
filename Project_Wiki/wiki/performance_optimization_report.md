# Stratejik Performans İyileştirme Önerileri (v7.0+)

EliteAgent v7.0'ın "Hardware-Aware" zekasıyla hazırlanan bu rapor, sistemin çıkarım performansını ve bellek verimliliğini bir üst seviyeye taşımak için iki ana alana odaklanır.

## 1. Kernel Fusion: GPU Geçişlerinin Optimizasyonu

Mevcut MLX operasyonlarımız lazy evaluation sayesinde verimli çalışsa da, karmaşık matematiksel operasyonlar hala birden fazla Metal kernel başlatma maliyetine (launch overhead) sahiptir.

### Öneri: Custom Compiled Graphs
- **Uygulama:** `InferenceActor` içindeki `forward` pass'in kritik bölümleri (özellikle Attention ve LayerNorm katmanları) `mx.compile` ile mühürlenmelidir.
- **Teknik Detay:** Ardışık operasyonlar tek bir Metal Shading Language (MSL) kernel'ında birleştirilerek GPU register kullanımı optimize edilir. Bu, verinin Global Memory'ye (VRAM) yazılıp tekrar okunmasını (round-trip) engeller.
- **Hedef Kazanç:** Çıkarım hızında (tokens/sec) %15-%20 artış ve CPU yükünde azalma.

## 2. KV Cache Management: Çoklu Ajan ve Birleşik Bellek Verimliliği

Çoklu ajan (Multi-agent) senaryolarında, her ajanın kendi KV Cache'ini tutması Unified Memory üzerinde ciddi bir baskı oluşturur.

### Öneri: Prefix Sharing & UNO Pointer Sharing
- **Uygulama:** Ajanlar genellikle aynı "System Prompt" veya "Shared Context" üzerinden çalışır. Bu ortak bağlamın KV Cache'i bir kez hesaplanmalı ve bellek adresi (pointer) UNO omurgası üzerinden diğer aktörlere paylaştırılmalıdır.
- **Teknik Detay:** 
    - **Shared Prefix Cache:** Ortak sistem mesajları için salt-okunur bir KV Cache bloğu oluşturulur.
    - **Zero-Copy Reference:** Diğer ajanlar bu bloğu kopyalamak yerine, kendi dikkat (attention) mekanizmalarında bu bellek adresini bir "Offset" olarak kullanır.
- **Hedef Kazanç:** 16GB cihazlarda eşzamanlı çalışabilen ajan sayısında 2-3 kat artış ve bağlam yükleme sürelerinde %90 kısalma.

## 3. Yol Haritası (Next Steps)

1. **Phase A:** `InferenceActor` için `mx.compile` stres testlerinin yapılması.
2. **Phase B:** `SharedMemoryPool` entegrasyonu ile KV Cache pointer sharing prototipinin oluşturulması.
3. **Phase C:** Bellek baskısı altında (Memory Pressure) dinamik cache boşaltma (purging) önceliklerinin belirlenmesi.

---
**Hazırlayan:** EliteAgent Autonomous Architect
**Tarih:** 2026-05-01
