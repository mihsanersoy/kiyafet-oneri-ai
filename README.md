# 🌤️🧥 Kişiselleştirilmiş Hava Durumu ve Kıyafet Öneri AI

> **Klasik hava durumu uygulamaları sadece gökyüzüne bakar; bu uygulama ise seni, vücut yapını ve geçmiş deneyimlerini tanır.**

Klasik hava durumu servisleri *"Bugün hava 10°C, mont giyin"* der ve geçer. Ancak gerçek dünyada **10°C**, herkes için aynı hissettirmez:
- Vücut Kitle Endeksi (VKE) yüksek olan veya tempolu yürürken çabuk terleyen biri için kalın bir kışlık mont, 10 dakika içinde terleyip ardından rüzgarda üşütmek demektir.
- Daha önce *"15 derecede montla terledim"* veya *"Rüzgarlı havada tişörtle üşüdüm"* diyen bir kullanıcının geçmiş deneyimleri dikkate alınmadığında yapay zeka jenerik öneriler üretir.

**Kişiselleştirilmiş Hava Durumu ve Kıyafet Öneri AI**; kullanıcının fiziksel verilerini (**Boy, Kilo, VKE, Terleme Hassasiyeti**), mikro-lokasyon meteoroloji verilerini (**Hissedilen Sıcaklık, Rüzgar Hızı, WMO Hava Olayı Kodu**) ve **Kişisel Senaryo Hafızası'nı (`scenarios.db`)** bir araya getirerek **Google Gemini AI** ile nokta atışı, katmanlı giyim (*layering*) ve fonksiyonel ekipman (şemsiye, kaymaz bot, rüzgarlık vb.) önerisi sunar.

---

## ✨ Öne Çıkan Özellikler

- 🧠 **Kişisel Termal Hafıza (Long-Term Memory):** Kullanıcının geçmiş giyim ve terleme deneyimleri yerel SQLite (`scenarios.db`) veya PostgreSQL veritabanında saklanır. Yapay zeka her öneride geçmiş deneyimlere doğrudan atıfta bulunur (*"Geçen sefer 12 derecede ceketle terlemiştin, bu yüzden bugün..."*).
- 📍 **Mikro-Lokasyon & Çok Katmanlı Konum Desteği:**
  - **HTML5 Geolocation (GPS):** Tek tıkla koordinat bazlı nokta atışı konum tespiti.
  - **Ters Geocoding (Nominatim):** Koordinatlardan otomatik İl ve İlçe adını çözümler.
  - **IP Tabanlı Yedek Konum:** Masaüstü cihazlarda GPS donanımı veya tarayıcı izni olmadığında IP üzerinden otomatik konum bulma.
- 🏙️ **81 İl Dinamik Combobox (Autocomplete):** Türkiye'nin 81 ilini Türkçe karakter duyarlı (`toLocaleLowerCase("tr-TR")`) olarak arayan, klavye ok tuşları ve fare destekli interaktif arama menüsü.
- 🌪️ **WMO Hava Olayı & Fonksiyonel Ekipman Analizi:** Open-Meteo ve OpenWeatherMap üzerinden çekilen WMO kodları 6 ana duruma eşleştirilir (`Güneşli`, `Soğuk/Ayaz`, `Yağmurlu`, `Karlı`, `Rüzgarlı`, `Dolu`). Yapay zeka sadece sıcaklığı değil, yağmurda su geçirmez katman ve şemsiyeyi, karda kaymaz tabanlı botu, rüzgarda rüzgarlığı hesaba katar.
- 🎨 **6 Canlı CSS Arka Plan Animasyonu & Glassmorphism:**
  - Sayfa ilk açıldığında 6 farklı hava durumu animasyonu (düşen yağmur damlaları, süzülen kar taneleri, rüzgar bulutları, güneş, ayaz, dolu) arasında 5.5 saniyede bir yumuşak geçiş yapar.
  - Form gönderilip canlı hava durumu geldiğinde döngü otomatik durur ve arka plan o anki gerçek hava durumuna kilitlenir.
  - Koyu yarı saydam cam efekti (*Glassmorphism - `backdrop-blur-xl`*) ile şık ve modern arayüz.

---

## 🛠️ Mimari ve Teknolojiler

### 💻 Frontend
- **Next.js (App Router) & React** – Modern bileşen ve sayfa mimarisi
- **TypeScript** – Güçlü tip güvenliği
- **Tailwind CSS** – Glassmorphism, karanlık mod ve mobil uyumlu responsive tasarım
- **Saf CSS Keyframe Animasyonları** – Harici kütüphaneye ihtiyaç duymayan hafif hava olayları

### ⚙️ Backend & Veritabanı
- **Python & FastAPI** – Yüksek hızlı asenkron REST API
- **SQLAlchemy & SQLite / PostgreSQL** – Kişisel senaryo hafızası için ORM katmanı (`scenarios.db`)
- **Pydantic v2** – Katı veri şeması ve doğrulama
- **HTTPX** – Asenkron dış API çağrıları ve hata yönetimi (`try/except`)
- **Uvicorn** – ASGI web sunucusu

### 🤖 Yapay Zeka & Meteoroloji Servisleri
- **Google Gemini API (`gemini-3.8-flash` / `gemini-3.1-flash-lite` / `gemini-2.5-flash`)** – Termal strateji ve giyim tavsiyesi motoru
- **Open-Meteo API** – Ücretsiz, anahtarsız anlık sıcaklık, rüzgar ve WMO hava olayı servisi
- **OpenWeatherMap API** – İsteğe bağlı alternatif hava durumu sağlayıcısı

---

## 📁 Proje Dizin Yapısı

```text
Proje2/
├── app/
│   ├── globals.css         # Tailwind temel stilleri
│   ├── layout.tsx          # Kök sayfa düzeni ve meta etiketleri
│   └── page.tsx            # Ana sayfa (HomePage Server Component)
├── components/
│   └── UserPreferenceForm.tsx  # 81 İl Combobox, Geolocation, Hafıza Kartı ve CSS Animasyonları
├── database.py             # SQLite (scenarios.db) / PostgreSQL ORM ve oturum yönetimi
├── main.py                 # FastAPI backend, Gemini AI motoru ve hava durumu servisleri
├── next.config.mjs         # Next.js yapılandırması
├── package.json            # Node.js bağımlılıkları ve çalıştırma scriptleri
├── requirements.txt        # Python kütüphaneleri
├── .env.example            # Örnek ortam değişkenleri şablonu
├── .gitignore              # Gizli ve gereksiz dosyaları engelleyen güvenlik kuralları
└── README.md               # Proje dokümantasyonu
```

---

## 🚀 Kurulum ve Çalıştırma

### 1️⃣ Repoyu Klonlayın
```bash
git clone https://github.com/KULLANICI_ADINIZ/REPO_ADINIZ.git
cd REPO_ADINIZ
```

### 2️⃣ Ortam Değişkenlerini Tanımlayın (`.env`)
`.env.example` dosyasını kopyalayarak `.env` oluşturun:
```bash
cp .env.example .env
```
`.env` dosyasını düzenleyin:
```env
# Google AI Studio'dan alınan Gemini API Anahtarı (Zorunlu)
GEMINI_API_KEY=your_gemini_api_key_here

# OpenWeatherMap API Anahtarı (İsteğe bağlı - boşsa Open-Meteo kullanılır)
OPENWEATHER_API_KEY=your_openweather_api_key_here

# PostgreSQL Veritabanı (Boş bırakılırsa yerel SQLite scenarios.db otomatik kullanılır)
DATABASE_URL=

# Frontend için Backend API Adresi (Varsayılan: http://127.0.0.1:8001)
NEXT_PUBLIC_API_URL=http://127.0.0.1:8001
```

---

### 3️⃣ Backend (FastAPI) Sunucusunu Başlatın

Python sanal ortamını kurun ve paketleri yükleyin:

**Windows (PowerShell / CMD):**
```powershell
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
python -m uvicorn main:app --port 8001 --reload
```

**macOS / Linux:**
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --port 8001 --reload
```
- 🌐 **API Adresi:** `http://127.0.0.1:8001`
- 📄 **Swagger UI (İnteraktif Dokümantasyon):** `http://127.0.0.1:8001/docs`

---

### 4️⃣ Frontend (Next.js) Arayüzünü Başlatın

Ayrı bir terminal penceresinde Node paketlerini kurup sunucuyu başlatın:
```bash
npm install
npm run dev
```
- 🖥️ **Tarayıcıda Açın:** **`http://localhost:3000`**

---

## 📡 API Uç Noktaları (Endpoints)

| Metot | Uç Nokta | Açıklama |
|---|---|---|
| `GET` | `/` | API durum ve servis karşılama mesajı |
| `GET` | `/scenarios` | Kayıtlı tüm geçmiş kişisel senaryoları listeler |
| `POST` | `/scenarios` | Yeni tekli veya çoklu geçmiş deneyim senaryosu kaydeder |
| `DELETE` | `/scenarios/{id}` | Belirtilen bir senaryoyu veritabanından kalıcı olarak siler |
| `GET` | `/ip-location` | GPS olmadığında IP üzerinden otomatik İl/İlçe/Koordinat bulur |
| `POST` | `/get-recommendation` | Hava durumu, VKE, rüzgar ve hafızayı analiz edip Gemini AI önerisini döner |

### Örnek İstek & Yanıt (`POST /get-recommendation`)

**İstek Gövdesi (Request Body):**
```json
{
  "sehir": "Yalova",
  "ilce": "Armutlu",
  "boy": 175,
  "kilo": 75,
  "terleme_egilimi": "Hayır",
  "gecmis_senaryolar": [
    "12 derecede yürürken kalın mont giydiğim için çok terledim",
    "20 derecede tişörtle yürürken bile terlemedim çok idealdi"
  ]
}
```

**Başarılı Yanıt (Response Body):**
```json
{
  "sehir": "Yalova, Armutlu",
  "sicaklik": 16.4,
  "hissedilen_sicaklik": 16.5,
  "ruzgar_hizi": 6.8,
  "wmo_kodu": 61,
  "hava_durumu_durumu": "Yağmurlu",
  "vke": 24.49,
  "kullanilan_senaryo_sayisi": 5,
  "oneri": "Armutlu'da bugün 16.5 derecelik yağmurlu havada, geçmişte 12 derecede kalın montla terlediğini ve 20 derecede tişörtle ideal hissettiğini göz önüne alırsak hafif ama koruyucu bir katmanlama en iyi tercih olacaktır. İçine nefes alan pamuklu bir tişört, üzerine fermuarlı bir sweatshirt ve en dışa su geçirmez kapüşonlu ince bir yağmurluk almanı öneririm. Yağışlı havada ıslanmamak için su tutmayan bir pantolon ve su geçirmeyen bir ayakkabı tercih ederek termal dengeni koruyabilirsin."
}
```

---

## 🔒 Güvenlik & Gizlilik
- Gerçek API anahtarları (`GEMINI_API_KEY`, `OPENWEATHER_API_KEY`) ve yerel veritabanı dosyaları (`scenarios.db`, `*.sqlite3`) `.gitignore` ile korunmaktadır ve depoya dahil edilmez.
- Repoya katkı sağlarken yalnızca `.env.example` şablonu üzerinde değişiklik yapılmalıdır.
