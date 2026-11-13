# 🌤️🧥 Kişiselleştirilmiş Hava Durumu ve Kıyafet Öneri AI

> **Standart hava durumu uygulamaları sadece gökyüzüne bakar; bu uygulama ise seni tanır.**

Klasik hava durumu servisleri *"Bugün hava 5°C, kalın mont giyin"* der ve geçer. Ancak gerçek dünyada **5°C**, herkes için aynı hissettirmez. Vücut Kitle Endeksi (VKE) yüksek olan veya soğukta hareket ettiğinde çabuk terleyen biri için kalın ve tek parça bir mont giymek, kısa sürede terleyip rüzgarda üşütmek demektir.

**Kişiselleştirilmiş Hava Durumu ve Kıyafet Öneri AI**, bulunduğun şehrin anlık **Hissedilen Sıcaklık (`feels_like`)** verisini senin fiziksel profilinle (**Boy, Kilo, VKE ve Terleme Eğilimi**) birleştirir ve **Google Gemini (`gemini-3.8-flash` / `gemini-3.1-flash-lite`)** yapay zeka modeli aracılığıyla sana özel bir **termal konfor & kombin danışmanlığı** sunar.

---

## ✨ Öne Çıkan Özellikler

- 🧠 **Yapay Zeka Destekli Termal Konfor Analizi:** Google Gemini (`gemini-3.8-flash` / `gemini-3.1-flash-lite`) modeli, uzman bir termal konfor danışmanı rolüyle ev içi ve dış ortam için katmanlı giyim (*layering*) stratejisi üretir.
- 🌡️ **Anlık Hissedilen Sıcaklık (`feels_like`) Entegrasyonu:** Yalnızca termometre sıcaklığını değil; rüzgar ve nemi hesaba katan gerçek hissedilen sıcaklığı **OpenWeatherMap** ve **Open-Meteo** üzerinden asenkron (`async/await`) olarak çeker.
- ⚖️ **Dinamik VKE (BMI) ve Terleme Hesaplaması:** Kullanıcının boy ve kilo verilerinden Vücut Kitle Endeksini otomatik hesaplar, bazal ısı üretimini ve hareket halindeki terleme eğilimini analize dahil eder.
- 🎨 **Modern, Minimalist & Karanlık Mod Destekli Arayüz:** Next.js (App Router) ve Tailwind CSS ile geliştirilmiş, mobil uyumlu (responsive), yükleme (*loading*) durumlarını ve sonuç kartlarını şık bir şekilde sunan kullanıcı deneyimi.
- 🔒 **Güvenli ve Ayrık (Decoupled) Mimari:** Frontend ve Backend birbirinden bağımsız çalışır ve REST API üzerinden haberleşir. Tüm API anahtarları `.env` katmanında izole edilerek korunur.

---

## 🛠️ Kullanılan Teknolojiler

### 💻 Frontend
- **Next.js (App Router)** – Modern React çatısı
- **React & TypeScript** – Tip güvenli bileşen ve state yönetimi
- **Tailwind CSS** – Karanlık mod (`dark mode`) destekli, responsive ve minimalist tasarım

### ⚙️ Backend
- **Python & FastAPI** – Yüksek performanslı asenkron REST API mimarisi
- **Uvicorn** – ASGI sunucusu
- **Pydantic** – Güçlü veri doğrulama ve şema yönetimi
- **HTTPX** – Asenkron dış API istekleri ve hata yönetimi (`try/except`)

### 🤖 Yapay Zeka & Dış Servisler
- **Google Gemini (`gemini-3.8-flash` / `gemini-3.1-flash-lite`) (`google-generativeai`)** – Doğal dilde kişiselleştirilmiş giyim stratejisi üretimi
- **OpenWeatherMap API & Open-Meteo API** – Gerçek zamanlı meteorolojik veri ve hissedilen sıcaklık servisi

---

## 🚀 Kurulum ve Çalıştırma (Installation)

Projeyi kendi bilgisayarınızda çalıştırmak için aşağıdaki adımları sırasıyla uygulayın:

### 1️⃣ Projeyi Klonlayın
```bash
git clone https://github.com/KULLANICI_ADINIZ/REPO_ADINIZ.git
cd REPO_ADINIZ
```

### 2️⃣ Ortam Değişkenlerini (`.env`) Ayarlayın
Proje ana dizininde bulunan `.env.example` dosyasını kopyalayarak `.env` adında yeni bir dosya oluşturun:
```bash
cp .env.example .env
```
`.env` dosyasını açarak **Google AI Studio** ve **OpenWeatherMap** anahtarlarınızı tanımlayın:
```env
GEMINI_API_KEY=AIzaSy_SENIN_GEMINI_API_ANAHTARIN
OPENWEATHER_API_KEY=SENIN_OPENWEATHER_API_ANAHTARIN
NEXT_PUBLIC_API_URL=http://127.0.0.1:8001
```
> 💡 *Not: `OPENWEATHER_API_KEY` boş bırakılırsa sistem kesintisiz çalışmaya devam etmek için otomatik olarak ücretsiz Open-Meteo servisine geçiş yapar.*

---

### 3️⃣ Backend (FastAPI) Kurulumu ve Başlatılması

Python sanal ortamını (`venv`) oluşturun, aktif edin ve bağımlılıkları yükleyin:

**Windows (PowerShell):**
```powershell
python -m venv venv
.\venv\Scripts\Activate
pip install -r requirements.txt
```

**macOS / Linux:**
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

FastAPI sunucusunu başlatın *(8000 portu başka bir servis tarafından kullanılıyorsa `8001` portunu kullanabilirsiniz)*:
```bash
uvicorn main:app --reload --port 8001
```
- 🌐 **API Adresi:** `http://127.0.0.1:8001`
- 📄 **Swagger UI (İnteraktif Test Ekranı):** `http://127.0.0.1:8001/docs`

---

### 4️⃣ Frontend (Next.js) Kurulumu ve Başlatılması

Yeni bir terminal penceresi açın, proje dizininde Node.js paketlerini yükleyin ve geliştirme sunucusunu başlatın:
```bash
npm install
npm run dev
```
- 🖥️ **Uygulama Arayüzü:** Tarayıcınızda `http://localhost:3000` adresine giderek uygulamayı kullanmaya başlayabilirsiniz.

---

## 📡 Örnek API Kullanımı (`POST /get-recommendation`)

**İstek (Request Body):**
```json
{
  "sehir": "Ankara",
  "boy": 179,
  "kilo": 159,
  "terleme_egilimi": "Evet"
}
```

**Yanıt (Response Body):**
```json
{
  "sehir": "Ankara",
  "sicaklik": 6.2,
  "hissedilen_sicaklik": 3.8,
  "vke": 49.62,
  "oneri": "Ankara'da hissedilen sıcaklık 3.8°C olsa da VKE değerin ve hareket halinde çabuk terleme eğilimin nedeniyle vücudun hızla ısı üretecektir. Ev içinde ince pamuklu bir tişörtle rahat edebilirsin; dışarı çıkarken ise tek parça kalın bir kışlık mont yerine nefes alabilen bir tişört üzerine fermuarlı polar ve rüzgar geçirmez ince bir yağmurluk/rüzgarlık giyerek ısındıkça katman azaltmanı öneririm."
}
```

---

## 🛡️ Güvenlik Notu
Bu projede API anahtarları `.gitignore` ile korunan `.env` dosyasında tutulmaktadır. Repoya katkıda bulunurken `.env` dosyanızı asla commit etmeyin; yalnızca `.env.example` şablonunu güncelleyin.
