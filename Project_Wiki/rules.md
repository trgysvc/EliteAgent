# ELM Wiki - Yazılım Üretim Kuralları

## 1. Mimari Felsefe
- **Native-First:** Her zaman Apple'ın resmi dökümantasyonuna, Swift 6 standartlarına ve yerel sistem çağrılarına sadık kal.
- **No Middleware:** LangChain, CrewAI veya benzeri soyutlama katmanlarını (middleware) asla kullanma. Çözümleri yerel kütüphanelerle üret.
- **Lean Development:** Kodun okunabilir, performanslı ve minimum bağımlılıkla çalışmasını sağla.

## 2. ELM Wiki Operasyon Kuralları
- **Hiyerarşi:** Her zaman `h.md` (Hot Memory) dosyasını oku; şu anki görev ve bağlam orada yatar.
- **Güncellik:** Bir özellik eklendiğinde veya mimari bir değişiklik yapıldığında, ilgili `wiki/` dosyasını ve `index.md` haritasını anında güncelle.
- **Sorgulama:** Eğer bir bilgi eksikse veya çelişki varsa, `raw/` klasöründeki kaynak dökümanlara geri dön.

## 3. Kodlama Standartları
- Swift 6 + SwiftUI + Apple Silicon (MLX) optimizasyonlarını önceliklendir.
- Kod bloklarını `wiki/` içinde dökümante ederken mantıksal akış şemalarıyla açıkla.
