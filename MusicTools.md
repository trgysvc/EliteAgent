# 🧬 Elite Music DNA: Infinity Encyclopedia (v28.0)

EliteAgent, **AudioIntelligence (v28.0)** kütüphanesi ile %100 "Full Disclosure" (Tam Şeffaflık) modunda çalışır. Bu belge, motorun ürettiği 100'den fazla parametrenin teknik karşılıklarını ve mühendislik yorumlarını içeren "Ansiklopedi" niteliğindeki ana referanstır.

---

## 🎚️ 1. Mastering & Dinamik Kontrol (BS.1770-4)

### Integrated Loudness (LUFS)
- **Tanım**: Şarkının başından sonuna kadar olan ortalama algılanan ses yüksekliği.
- **Hedef**: Spotify/Apple Music için -14 LUFS, CD/Club için -9 ya da -7 LUFS.
- **Yorum**: "High" değerler dinamik kaybını, "Low" değerler ise düşük ses seviyesini işaret eder.

### Momentary & Short-term LUFS
- **Momentary (400ms)**: Anlık patlamalar (Kick vuruşu, vokal piki).
- **Short-term (3s)**: Koro veya verse gibi bölümlerin kendi içindeki ses dengesi.
- **Yorum**: Verse ve Nakarat arasındaki Short-term farkı (Loudness Range), şarkının "enerji sıçramasını" belirler.

### True Peak (dBTP)
- **Tanım**: Örneklemeler arası (inter-sample) dijital tavanın aşılması. 0.0 dBTP üstü "clipping" (bozulma) yaratır.
- **Güvenli Sınır**: Mastering standartlarında en fazla -0.1 dBTP veya veri kaybı riski için -1.0 dBTP önerilir.

### Phase Correlation & Stereo Image
- **Correlation (+1.0 to -1.0)**:
  - **+1.0**: Perfect Mono (Sol ve sağ aynı).
  - **+0.5 to +0.9**: İdeal Stereo (Geniş ama uyumlu).
  - **0 to -1.0**: Faz İptali (Mono sistemlerde ses kaybolur).
- **L/R Balance**: Enerji merkezinin sağa veya sola kayma oranı.

---

## 🧪 2. Spektrum & Timbre (Tını) DNA

### MFCC (Mel-Frequency Cepstral Coefficients) — 20 Katsayı
LLM için tınıyı tanımlayan ana vektör budur. Katsayılar şunları temsil eder:
- **MFCC[0] (Energy)**: Genel ses basıncı ve DC ofseti.
- **MFCC[1] (Spectral Slope)**: Sesin "parlaklığı" veya "koyuluğu". Yüksek değer = tiz ağırlıklı.
- **MFCC[2] (Spectral Shape)**: Temel frekans ve armoniklerin dengesi (Vokal varlığı).
- **MFCC[3-13]**: Enstrüman karakteri (Örn: Piyano ve Gitar arasındaki fark bu katsayılarla anlaşılır).
- **MFCC[14-19]**: Yüksek frekanslı doku ve mikro-detaylar.

### Spectral Flux (Enerji Değişimi)
- **Tanım**: İki frekans karesi (frames) arasındaki öklid mesafesi.
- **Yorum**: Yüksek Flux, şarkının çok dinamik, değişken ve hareketli (Örn: Dubstep, Jazz) olduğunu gösterir. Düşük Flux durağanlıktır (Örn: Drone, Ambient).

### Spectral Flatness & ZCR
- **Flatness**: Sinyal ne kadar "tonal" (saf ses) veya "gürültülü" (hiss/noise).
- **ZCR (Zero Crossing Rate)**: Periyodik olmayan gürültülerin sayısı. Distorsiyonlu gitarlarda ve perküsyonlarda yüksektir.

---

## 🎹 3. Tonalite & Chroma Map (12 Nota)

### Chroma Bins (C, C#, D, D#, E, F, F#, G, G#, A, A#, B)
- **Tanım**: Frekansların 12 notalık batı müziği oktavına izdüşümü.
- **Analiz**:
  - Şarkıda hangi notanın ne kadar enerji taşıdığını gösterir.
  - Örn: "G" ve "D" binleri yüksekse, şarkı muhtemelen G Major veya G Minor Scale'dedir.
- **Circle of Fifths Bağlantısı**: Komşu binlerin enerji seviyelerine bakılarak harmonik geçişler ve akor dizilimleri (Chord progressions) tahmin edilebilir.

### Key & Scale Detection
- **Key Strength**: Algoritmanın (Krumhansl-Schmuckler) tespitine olan güven oranı.
- **Mode**: Majör (Neşeli/Parlak) veya Minör (Hüzünlü/Koyu) karakter tespiti.

---

## 🥁 4. Ritim & Tempo Analizi

### BPM (Beats Per Minute)
- **Algoritma**: Ellis Dynamic Programming bazlı vuruş takibi.
- **Hassasiyet**: Ondalık hassasiyetle (örn: 124.02) verilir, bu da şarkının "grid" mi yoksa "serbest çalım" mı olduğunu açıklar.

### Beat Consistency (Grid Deviation)
- **Yorum**: ±0.01s sapma "mükemmel elektronik ritim", ±0.05s ve üstü "canlı davulcu" veya "insan hissi" (swing) anlamına gelir.

---

## 🔍 5. Forensic (Adli) & Bit-Depth Analizi

### Forensic Entropy (Röntgen)
- **Bit-Depth Integrity**: 16-bit'lik bir dosyanın sadece "sayısal olarak" 24-bit'e yükseltilip yükseltilmediğini anlar.
- **Fake Hi-Res Tespiti**: Eğer etkili bit derinliği (effective bits) 16'nın altındaysa dosya "upsampled" veya "fake" olarak işaretlenir.

---

## 🧩 6. Yapısal Segmentasyon (Segmentation)
- **Foote SSM Algoritması**: Kendi kendine benzerlik matrisi kullanarak Intro, Chorus, Verse ve Outro bölümlerini matematiksel olarak ayırır.
- **Segment Labels**: 
  - `Label 0`: Genellikle ambiyans veya sessizlik.
  - `Label N`: Benzer spektral yapıya sahip tekrarlayan bölümler (Akor değişimleri).

---
*EliteAgent Music DNA Engine — The Infinity Standard*
*ASLA KISALTMA YAPMA - FULL DATA ACCESS ENABLED*
