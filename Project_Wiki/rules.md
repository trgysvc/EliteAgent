# ELM Wiki - Yazılım Üretim Kuralları

## 1. Mimari Felsefe
- **Native-First:** Her zaman Apple'ın resmi dökümantasyonuna, Swift 6 standartlarına ve yerel sistem çağrılarına sadık kal.
- **No Middleware:** LangChain, CrewAI veya benzeri soyutlama katmanlarını (middleware) asla kullanma. Çözümleri yerel kütüphanelerle üret.
- **Lean Development:** Kodun okunabilir, performanslı ve minimum bağımlılıkla çalışmasını sağla.

## 2. ELM Wiki Operasyon Kuralları
- **Hiyerarşi:** Her zaman `h.md` (Hot Memory) dosyasını oku; şu anki görev ve bağlam orada yatar.
- **Güncellik:** Bir özellik eklendiğinde veya mimari bir değişiklik yapıldığında, ilgili `wiki/` dosyasını ve `index.md` haritasını anında güncelle.
- **Sorgulama:** Teknik bir belirsizlik durumunda internette genel arama yapmak yerine öncelikle `concepts/` klasöründeki resmi teknik standart dökümanlarını referans al. Eğer bilgi hala eksikse `raw/` klasöründeki kaynaklara geri dön.

## 3. Kodlama Standartları
- Swift 6 + SwiftUI + Apple Silicon (MLX) optimizasyonlarını önceliklendir.
- Kod bloklarını `wiki/` içinde dökümante ederken mantıksal akış şemalarıyla açıkla.

## 4. Teknik Zorunluluklar (Technical Mandates)
- **Metal Backend Enforcement:** LLM operasyonları tasarlanırken, MLX'in Metal backend'inin "Lazy Evaluation" ve "Kernel Fusion" prensipleri birer kısıt olarak kabul edilmelidir. Gereksiz hesaplamalardan kaçınılmalı ve `mx.compile` kullanımı teşvik edilmelidir.
- **Memory Anchoring:** Model ağırlıkları ve KV Cache verileri, çıkarım (inference) kararlılığı için birleşik bellekte (Unified Memory) "çivilenmiş" (anchored) kabul edilmeli; bellek kısıtları LLM agent'ı tarafından bir 'Soft Constraint' değil, 'Hard Limit' olarak yönetilmelidir.
- **Native Context Management:** KV Cache yönetimi, RoPE uygulamaları ve model spesifik tensor manipülasyonları, harici bir kütüphaneye ihtiyaç duymadan doğrudan `MLXFast` ve `MLXLMCommon` standartlarına göre tasarlanmalıdır.
