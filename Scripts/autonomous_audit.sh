#!/bin/bash
echo "🛡 EliteAgent Otonom Denetim Başlatıldı (v7.1)"
echo "----------------------------------------------"

# Log dosyalarını temizle (yeni başlangıç)
> /Users/trgysvc/Library/Logs/EliteAgent/audit.log
> /Users/trgysvc/Library/Logs/EliteAgent/debug.log

PROMPTS=(
    "Şu anki sistem bilgilerimi ve İstanbul hava durumunu getir. Gerçek veri istiyorum."
    "Proje kökünde 'AUDIT_TEST.txt' dosyası oluştur, içine 'EliteAgent Stability Test' yaz. Sonra bu dosyayı git ile 'Audit' mesajıyla commit et."
    "Sistemdeki 8080 portunu kullanan süreçleri listele."
    "Takvimdeki bugünkü etkinliklerimi listele."
)

for i in "${!PROMPTS[@]}"; do
    echo "📝 GÖREV $((i+1)): ${PROMPTS[$i]}"
    swift run elite --cpu-only "${PROMPTS[$i]}"
    echo "✅ GÖREV $((i+1)) TAMAMLANDI."
    echo "----------------------------------------------"
done

echo "📊 LOG ANALİZİ BAŞLATILIYOR..."
tail -n 100 /Users/trgysvc/Library/Logs/EliteAgent/audit.log
