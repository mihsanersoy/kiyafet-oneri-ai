"use client";

import React, { useState, useEffect, useRef, FormEvent } from "react";

export type WeatherTheme =
  | "Güneşli"
  | "Soğuk/Ayaz"
  | "Yağmurlu"
  | "Karlı"
  | "Rüzgarlı"
  | "Dolu";

const WEATHER_THEMES: WeatherTheme[] = [
  "Güneşli",
  "Soğuk/Ayaz",
  "Yağmurlu",
  "Karlı",
  "Rüzgarlı",
  "Dolu",
];

// Türkiye'nin 81 İli (Combobox / Autocomplete için)
const TURKISH_PROVINCES: string[] = [
  "Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Aksaray", "Amasya", "Ankara",
  "Antalya", "Ardahan", "Artvin", "Aydın", "Balıkesir", "Bartın", "Batman",
  "Bayburt", "Bilecik", "Bingöl", "Bitlis", "Bolu", "Burdur", "Bursa",
  "Çanakkale", "Çankırı", "Çorum", "Denizli", "Diyarbakır", "Düzce", "Edirne",
  "Elazığ", "Erzincan", "Erzurum", "Eskişehir", "Gaziantep", "Giresun",
  "Gümüşhane", "Hakkari", "Hatay", "Iğdır", "Isparta", "İstanbul", "İzmir",
  "Kahramanmaraş", "Karabük", "Karaman", "Kars", "Kastamonu", "Kayseri",
  "Kırıkkale", "Kırklareli", "Kırşehir", "Kilis", "Kocaeli", "Konya",
  "Kütahya", "Malatya", "Manisa", "Mardin", "Mersin", "Muğla", "Muş",
  "Nevşehir", "Niğde", "Ordu", "Osmaniye", "Rize", "Sakarya", "Samsun",
  "Siirt", "Sinop", "Sivas", "Şanlıurfa", "Şırnak", "Tekirdağ", "Tokat",
  "Trabzon", "Tunceli", "Uşak", "Van", "Yalova", "Yozgat", "Zonguldak",
];

export interface UserPreferences {
  city: string;
  district: string;
  lat: number | null;
  lon: number | null;
  height: number | "";
  weight: number | "";
  sweatsEasily: boolean;
}

export interface ScenarioItem {
  id: number;
  scenario_text: string;
  created_at: string;
}

export interface RecommendationResult {
  sehir: string;
  sicaklik: number;
  hissedilen_sicaklik: number;
  ruzgar_hizi: number;
  wmo_kodu: number;
  hava_durumu_durumu: WeatherTheme | string;
  vke: number;
  kullanilan_senaryo_sayisi: number;
  oneri: string;
}

const getApiBaseUrl = (): string => {
  if (typeof window !== "undefined") {
    const host = window.location.hostname || "localhost";
    return `http://${host}:8001`;
  }
  return process.env.NEXT_PUBLIC_API_URL || "http://127.0.0.1:8001";
};

const LOCAL_STORAGE_KEY = "thermal_advisor_scenarios";

// Eski veya yeni her formatı güvenle ScenarioItem nesnelerine dönüştürür
const normalizeScenarios = (data: unknown): ScenarioItem[] => {
  if (!Array.isArray(data)) return [];
  return data
    .map((item, idx): ScenarioItem | null => {
      if (typeof item === "string" && item.trim()) {
        return {
          id: Date.now() + idx,
          scenario_text: item.trim(),
          created_at: new Date().toISOString(),
        };
      }
      if (item && typeof item === "object" && "scenario_text" in item) {
        const text = String(
          (item as { scenario_text?: unknown }).scenario_text || ""
        ).trim();
        if (!text) return null;
        return {
          id: Number((item as { id?: unknown }).id) || Date.now() + idx,
          scenario_text: text,
          created_at: String(
            (item as { created_at?: unknown }).created_at ||
              new Date().toISOString()
          ),
        };
      }
      return null;
    })
    .filter((item): item is ScenarioItem => item !== null);
};

const EXAMPLE_SCENARIOS = [
  "15 derecede yürüdüğüm için montla terledim",
  "Rüzgarlı havada tişörtle üşüdüm",
  "10 derecede fermuarlı polar ve ince tişörtle çok rahat ettim",
];

// Sabit deterministik parçacık dizileri (SSR hydration uyumsuzluğunu önler)
const RAIN_PARTICLES = Array.from({ length: 42 }, (_, i) => ({
  left: (i * 2.4) % 100,
  delay: (i * 0.17) % 2,
  duration: 0.65 + ((i * 0.11) % 0.45),
  opacity: 0.35 + ((i * 0.07) % 0.5),
}));

const SNOW_PARTICLES = Array.from({ length: 36 }, (_, i) => ({
  left: (i * 2.8) % 100,
  delay: (i * 0.25) % 4,
  duration: 3.5 + ((i * 0.3) % 3),
  size: 4 + (i % 6),
}));

const HAIL_PARTICLES = Array.from({ length: 32 }, (_, i) => ({
  left: (i * 3.1) % 100,
  delay: (i * 0.12) % 1.2,
  duration: 0.4 + ((i * 0.05) % 0.25),
  size: 5 + (i % 5),
}));

const WIND_STREAKS = Array.from({ length: 14 }, (_, i) => ({
  top: 8 + ((i * 6.5) % 85),
  delay: (i * 0.35) % 3,
  duration: 1.8 + ((i * 0.2) % 1.5),
  width: 120 + ((i * 25) % 180),
}));

export default function UserPreferenceForm() {
  const [formData, setFormData] = useState<UserPreferences>({
    city: "",
    district: "",
    lat: null,
    lon: null,
    height: "",
    weight: "",
    sweatsEasily: false,
  });

  // Dinamik Arka Plan Animasyon State'leri
  const [activeThemeIndex, setActiveThemeIndex] = useState<number>(0);
  const [lockedTheme, setLockedTheme] = useState<WeatherTheme | null>(null);

  const currentTheme: WeatherTheme =
    lockedTheme || WEATHER_THEMES[activeThemeIndex];

  // Sonuç yokken 5.5 saniyede bir 6 arka plan arasında yumuşak geçiş döngüsü
  useEffect(() => {
    if (lockedTheme) return;

    const interval = setInterval(() => {
      setActiveThemeIndex((prev) => (prev + 1) % WEATHER_THEMES.length);
    }, 5500);

    return () => clearInterval(interval);
  }, [lockedTheme]);

  // 81 İl Combobox / Autocomplete State'leri
  const [isCityOpen, setIsCityOpen] = useState<boolean>(false);
  const [highlightedIndex, setHighlightedIndex] = useState<number>(0);
  const comboboxRef = useRef<HTMLDivElement>(null);

  // Türkçe karakter duyarlı il filtreleme (Önce baş harfi eşleşenler, sonra içerenler)
  const filteredProvinces = React.useMemo(() => {
    const query = formData.city.trim().toLocaleLowerCase("tr-TR");
    if (!query) return TURKISH_PROVINCES;

    const startsWith = TURKISH_PROVINCES.filter((p) =>
      p.toLocaleLowerCase("tr-TR").startsWith(query)
    );
    const includes = TURKISH_PROVINCES.filter(
      (p) =>
        !p.toLocaleLowerCase("tr-TR").startsWith(query) &&
        p.toLocaleLowerCase("tr-TR").includes(query)
    );
    return [...startsWith, ...includes];
  }, [formData.city]);

  // Dışarı tıklandığında Combobox menüsünü kapat
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (
        comboboxRef.current &&
        !comboboxRef.current.contains(e.target as Node)
      ) {
        setIsCityOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Geolocation state'leri
  const [isLocating, setIsLocating] = useState<boolean>(false);
  const [locationMessage, setLocationMessage] = useState<string | null>(null);

  // Senaryo Hafızası state'leri
  const [scenarios, setScenarios] = useState<ScenarioItem[]>([]);
  const [showScenarioList, setShowScenarioList] = useState<boolean>(false);
  const [newScenarioText, setNewScenarioText] = useState<string>("");
  const [isSavingScenario, setIsSavingScenario] = useState<boolean>(false);
  const [scenarioFeedback, setScenarioFeedback] = useState<{
    type: "success" | "warning";
    text: string;
  } | null>(null);
  const scenarioInputRef = useRef<HTMLInputElement>(null);

  // Öneri İsteği state'leri
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<RecommendationResult | null>(null);

  // Veritabanından (scenarios.db) senaryoları çeken fonksiyon
  const syncScenariosFromDb = async () => {
    const apiUrl = getApiBaseUrl();
    try {
      const res = await fetch(`${apiUrl}/scenarios`, {
        cache: "no-store",
      });
      if (res.ok) {
        const raw = await res.json();
        const normalized = normalizeScenarios(raw);
        setScenarios(normalized);
        localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(normalized));
        return;
      }
    } catch {
      // Backend kapalıysa localStorage yedeğini yükle
    }

    try {
      const raw = localStorage.getItem(LOCAL_STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        setScenarios(normalizeScenarios(parsed));
      }
    } catch {
      // ignore
    }
  };

  // Sayfa yüklendiğinde veritabanından (scenarios.db) senaryoları çek
  useEffect(() => {
    syncScenariosFromDb();
  }, []);

  // Senaryo Ekleme (Lokal scenarios.db + Anlık UI)
  const addScenarioItem = async (textToSave: string) => {
    const cleaned = textToSave.trim();
    if (!cleaned) {
      setScenarioFeedback({
        type: "warning",
        text: "Lütfen önce kutuya bir deneyim yazın veya üstteki hazır örneklerden birine tıklayın.",
      });
      scenarioInputRef.current?.focus();
      return;
    }

    if (
      scenarios.some(
        (s) =>
          (s?.scenario_text || "").trim().toLowerCase() ===
          cleaned.toLowerCase()
      )
    ) {
      setScenarioFeedback({
        type: "warning",
        text: "Bu senaryo zaten hafızanda kayıtlı.",
      });
      setNewScenarioText("");
      return;
    }

    setIsSavingScenario(true);
    setScenarioFeedback(null);

    const apiUrl = getApiBaseUrl();
    try {
      const res = await fetch(`${apiUrl}/scenarios`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ scenario_text: cleaned }),
      });

      if (res.ok) {
        const created = await res.json();
        const addedItems = normalizeScenarios(
          Array.isArray(created) ? created : [created]
        );
        setScenarios((prev) => {
          const next = [...addedItems, ...prev];
          localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(next));
          return next;
        });
        setNewScenarioText("");
        setScenarioFeedback({
          type: "success",
          text: `✓ "${cleaned}" veritabanına (scenarios.db) kaydedildi!`,
        });
      } else {
        throw new Error("Sunucu hatası");
      }
    } catch {
      // Backend o an kapalıysa bile UI + localStorage'a kaydet
      const fallbackItem: ScenarioItem = {
        id: Date.now(),
        scenario_text: cleaned,
        created_at: new Date().toISOString(),
      };
      setScenarios((prev) => {
        const next = [fallbackItem, ...prev];
        localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(next));
        return next;
      });
      setNewScenarioText("");
      setScenarioFeedback({
        type: "success",
        text: `✓ "${cleaned}" eklendi (öneri isteğiyle veritabanına aktarılacak).`,
      });
    } finally {
      setIsSavingScenario(false);
    }
  };

  const handleAddScenario = async (e: FormEvent) => {
    e.preventDefault();
    await addScenarioItem(newScenarioText);
  };

  const handleDeleteScenario = async (id: number) => {
    setScenarios((prev) => {
      const filtered = prev.filter((item) => item.id !== id);
      localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(filtered));
      return filtered;
    });

    try {
      const apiUrl = getApiBaseUrl();
      await fetch(`${apiUrl}/scenarios/${id}`, {
        method: "DELETE",
      });
    } catch {
      // ignore
    }
  };

  // Gelişmiş Konum Bulma (HTML5 Geolocation + Ters Geocoding + IP Konum Yedeği)
  const handleFindLocation = async () => {
    setIsLocating(true);
    setError(null);

    const applyCoordinates = async (
      lat: number,
      lon: number,
      fallbackCity?: string,
      fallbackDistrict?: string
    ) => {
      let detectedCity = fallbackCity || "";
      let detectedDistrict = fallbackDistrict || "";

      // Koordinattan İl ve İlçe adını otomatik doldurmak için OpenStreetMap Nominatim sorgusu
      if (!detectedCity) {
        try {
          const revRes = await fetch(
            `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lon}&accept-language=tr`
          );
          if (revRes.ok) {
            const revData = await revRes.json();
            const addr = revData.address || {};
            detectedCity =
              addr.province || addr.state || addr.city || detectedCity;
            detectedDistrict =
              addr.town ||
              addr.county ||
              addr.suburb ||
              addr.city_district ||
              detectedDistrict;
          }
        } catch {
          // Ters geocoding başarısız olursa koordinatlar yine de yeterli
        }
      }

      setFormData((prev) => ({
        ...prev,
        city: detectedCity || prev.city,
        district: detectedDistrict || prev.district,
        lat,
        lon,
      }));

      const label =
        detectedCity && detectedDistrict
          ? `${detectedCity}, ${detectedDistrict} (${lat}, ${lon})`
          : detectedCity
          ? `${detectedCity} (${lat}, ${lon})`
          : `GPS (${lat}, ${lon})`;

      setLocationMessage(`Konum bulundu: ${label}`);
      setIsLocating(false);
    };

    // Yedek IP tabanlı konum bulucu (Masaüstü PC'de GPS/Konum servisi kapalıysa devreye girer)
    const fallbackToIpLocation = async () => {
      const apiUrl = getApiBaseUrl();
      try {
        const ipRes = await fetch(`${apiUrl}/ip-location`);
        if (ipRes.ok) {
          const data = await ipRes.json();
          await applyCoordinates(
            data.lat,
            data.lon,
            data.city,
            data.district
          );
          return;
        }
      } catch {
        // Backend IP servisine ulaşılamazsa doğrudan tarayıcıdan dene
      }

      try {
        const directRes = await fetch("https://ipapi.co/json/");
        if (directRes.ok) {
          const d = await directRes.json();
          if (d.latitude && d.longitude) {
            await applyCoordinates(
              Number(Number(d.latitude).toFixed(4)),
              Number(Number(d.longitude).toFixed(4)),
              d.region || d.city,
              d.city
            );
            return;
          }
        }
      } catch {
        // ignore
      }

      setIsLocating(false);
      setError(
        "Tarayıcı konum izni kapalı veya masaüstü GPS bulunamadı. Lütfen listeden İl seçin."
      );
    };

    // HTTPS veya localhost kontrolü ve HTML5 Geolocation çağrısı
    if (typeof window !== "undefined" && "geolocation" in navigator) {
      navigator.geolocation.getCurrentPosition(
        async (position) => {
          const lat = Number(position.coords.latitude.toFixed(4));
          const lon = Number(position.coords.longitude.toFixed(4));
          await applyCoordinates(lat, lon);
        },
        async () => {
          // Tarayıcı GPS'i hata verirse (Masaüstünde Windows Konum kapalıysa) otomatik IP yedeğine geç
          await fallbackToIpLocation();
        },
        {
          enableHighAccuracy: false, // Masaüstü Wi-Fi konumlandırmasında takılmaması için false
          timeout: 6000,
          maximumAge: 60000,
        }
      );
    } else {
      await fallbackToIpLocation();
    }
  };

  const handleClearGps = () => {
    setFormData((prev) => ({ ...prev, lat: null, lon: null }));
    setLocationMessage(null);
  };

  // Ana Kombin Öneri Formu Gönderimi
  const handleSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setIsLoading(true);
    setError(null);

    const activeScenarios = scenarios
      .map((s) => s?.scenario_text?.trim())
      .filter(Boolean) as string[];

    if (
      newScenarioText.trim() &&
      !activeScenarios.includes(newScenarioText.trim())
    ) {
      activeScenarios.unshift(newScenarioText.trim());
      await addScenarioItem(newScenarioText.trim());
    }

    try {
      const apiUrl = getApiBaseUrl();
      const response = await fetch(`${apiUrl}/get-recommendation`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          sehir: formData.city,
          ilce: formData.district,
          lat: formData.lat,
          lon: formData.lon,
          boy: Number(formData.height),
          kilo: Number(formData.weight),
          terleme_egilimi: formData.sweatsEasily ? "Evet" : "Hayır",
          gecmis_senaryolar: activeScenarios,
        }),
      });

      const data: RecommendationResult = await response.json();

      if (!response.ok) {
        throw new Error(
          (data as unknown as { detail?: string }).detail ||
            "Öneri alınırken bir hata oluştu. Lütfen tekrar deneyin."
        );
      }

      setResult(data);

      // Gelen gerçek hava olayına göre arka plan döngüsünü durdur ve o havaya kilitle!
      const incomingTheme = data.hava_durumu_durumu as WeatherTheme;
      if (WEATHER_THEMES.includes(incomingTheme)) {
        setLockedTheme(incomingTheme);
      } else {
        setLockedTheme("Güneşli");
      }
    } catch (err: unknown) {
      setResult(null);
      if (err instanceof Error) {
        setError(err.message);
      } else {
        setError(
          "Sunucuya bağlanılamadı. FastAPI servisinin 8001 portunda çalıştığından emin olun."
        );
      }
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <>
      {/* Tam Ekran CSS Hava Olayı Animasyon Katmanı */}
      <WeatherAnimatedBackground theme={currentTheme} />

      <div className="relative z-10 w-full max-w-2xl mx-auto space-y-6 my-4">
        {/* Üst Bilgi Çubuğu: Aktif Hava Olayı Animasyonu Göstergesi */}
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-2xl backdrop-blur-xl bg-slate-950/60 border border-white/15 px-4 py-2.5 text-xs text-slate-200 shadow-lg">
          <div className="flex items-center gap-2">
            <span className="inline-block h-2 w-2 rounded-full bg-sky-400 animate-pulse" />
            <span>
              {lockedTheme ? (
                <>
                  Canlı Hava Durumu Arka Planı Kilitlendi:{" "}
                  <strong className="text-sky-300">{currentTheme}</strong>
                </>
              ) : (
                <>
                  Önizleme Döngüsü Aktif (5.5 sn):{" "}
                  <strong className="text-amber-300">{currentTheme}</strong>
                </>
              )}
            </span>
          </div>

          <div className="flex items-center gap-1.5">
            {lockedTheme && (
              <button
                type="button"
                onClick={() => setLockedTheme(null)}
                className="rounded-lg bg-white/10 hover:bg-white/20 px-2.5 py-1 text-[11px] font-medium text-sky-200 transition cursor-pointer"
              >
                Döngüyü Başlat
              </button>
            )}
          </div>
        </div>

        {/* 1. BÖLÜM: Kişisel Senaryo Hafızası (Glassmorphism) */}
        <div className="backdrop-blur-xl bg-slate-950/70 rounded-2xl shadow-2xl border border-white/15 p-6 sm:p-7 text-slate-100 transition-all">
          <div className="flex items-start justify-between gap-4 mb-4">
            <div>
              <span className="inline-block text-xs font-medium tracking-wider uppercase text-amber-300 bg-amber-500/20 border border-amber-400/30 px-2.5 py-1 rounded-full mb-1.5">
                🧠 Kişisel Termal Hafıza
              </span>
              <h2 className="text-lg font-semibold text-white">
                Geçmiş Deneyimlerini Ekle
              </h2>
              <p className="text-xs sm:text-sm text-slate-300 mt-0.5">
                Yapay zekanın seni daha iyi tanıması için geçmiş deneyimlerini
                ekle. Veriler lokal <code>scenarios.db</code> veritabanına
                kaydedilir.
              </p>
            </div>
            <span className="shrink-0 rounded-full bg-sky-500/20 border border-sky-400/30 text-sky-200 px-3 py-1 text-xs font-semibold">
              {scenarios.length} Kayıt
            </span>
          </div>

          {/* Hızlı Örnek Şablon Çipleri */}
          <div className="mb-3">
            <span className="block text-[11px] font-medium text-slate-400 mb-1.5">
              Hızlı eklemek için bir örneğe tıkla:
            </span>
            <div className="flex flex-wrap gap-1.5">
              {EXAMPLE_SCENARIOS.map((sample, idx) => (
                <button
                  key={idx}
                  type="button"
                  onClick={() => addScenarioItem(sample)}
                  className="text-xs rounded-lg border border-white/15 bg-white/5 hover:bg-sky-500/20 hover:border-sky-400/50 text-slate-200 px-2.5 py-1.5 transition active:scale-95 cursor-pointer"
                >
                  + &ldquo;{sample}&rdquo;
                </button>
              ))}
            </div>
          </div>

          {/* Senaryo Ekleme Formu */}
          <form onSubmit={handleAddScenario} className="flex gap-2">
            <input
              ref={scenarioInputRef}
              type="text"
              value={newScenarioText}
              onChange={(e) => {
                setNewScenarioText(e.target.value);
                if (scenarioFeedback) setScenarioFeedback(null);
              }}
              placeholder="Örn: 15 derecede yürüdüğüm için montla terledim..."
              className="flex-1 rounded-xl border border-white/20 bg-white/10 px-3.5 py-2.5 text-sm text-white placeholder-slate-400 focus:border-sky-400 focus:bg-slate-900/80 focus:outline-none focus:ring-2 focus:ring-sky-400/30 transition"
            />
            <button
              type="submit"
              disabled={isSavingScenario}
              className="shrink-0 rounded-xl bg-sky-500 hover:bg-sky-400 active:scale-95 disabled:opacity-50 text-slate-950 font-semibold text-sm px-4 py-2.5 transition shadow-md cursor-pointer"
            >
              {isSavingScenario ? "Ekleniyor..." : "+ Senaryo Ekle"}
            </button>
          </form>

          {scenarioFeedback && (
            <div
              className={`mt-2.5 rounded-lg px-3 py-1.5 text-xs font-medium ${
                scenarioFeedback.type === "success"
                  ? "bg-emerald-500/20 text-emerald-200 border border-emerald-400/30"
                  : "bg-amber-500/20 text-amber-200 border border-amber-400/30"
              }`}
            >
              {scenarioFeedback.text}
            </div>
          )}

          {/* Arka Plan Hafıza Durumu & Açılır/Kapanır Liste Çekmecesi */}
          <div className="mt-4 pt-3 border-t border-white/10">
            <div className="flex items-center justify-between text-xs text-slate-300">
              <span>
                🗄️ <code>scenarios.db</code> arka plan hafızasında{" "}
                <strong className="text-sky-300">{scenarios.length}</strong>{" "}
                deneyim kayıtlı (her öneride otomatik kullanılır).
              </span>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={syncScenariosFromDb}
                  className="text-slate-400 hover:text-sky-300 underline cursor-pointer"
                >
                  Yenile
                </button>
                {scenarios.length > 0 && (
                  <button
                    type="button"
                    onClick={() => setShowScenarioList((prev) => !prev)}
                    className="rounded-lg bg-white/10 hover:bg-white/15 px-2.5 py-1 text-sky-200 font-medium transition cursor-pointer"
                  >
                    {showScenarioList ? "Hafızayı Gizle ▲" : "Hafızayı Gör ▼"}
                  </button>
                )}
              </div>
            </div>

            {showScenarioList && scenarios.length > 0 && (
              <div className="mt-3 space-y-2 max-h-44 overflow-y-auto pr-1">
                {scenarios.map((item) => (
                  <div
                    key={item.id}
                    className="flex items-center justify-between gap-3 rounded-xl bg-white/5 px-3.5 py-2 text-xs sm:text-sm text-slate-200 border border-white/10"
                  >
                    <span className="truncate">
                      • &ldquo;{item.scenario_text}&rdquo;
                    </span>
                    <button
                      type="button"
                      onClick={() => handleDeleteScenario(item.id)}
                      title="Veritabanından Kalıcı Olarak Sil"
                      className="text-slate-400 hover:text-rose-400 font-semibold text-xs px-2 py-0.5 rounded hover:bg-rose-500/10 transition cursor-pointer"
                    >
                      Sil ×
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* 2. BÖLÜM: Mikro-Lokasyon & Fiziksel Profil Formu (Glassmorphism) */}
        <div className="backdrop-blur-xl bg-slate-950/70 rounded-2xl shadow-2xl border border-white/15 p-6 sm:p-8 text-slate-100 transition-all">
          <div className="mb-6 flex items-start gap-3.5 sm:gap-4">
            <div className="shrink-0 rounded-2xl bg-white p-1.5 shadow-lg shadow-sky-500/20 ring-2 ring-sky-400/40">
              <img
                src="/logo.png"
                alt="OptiWear Logo"
                className="h-12 w-12 sm:h-14 sm:w-14 object-contain"
              />
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-2 mb-1.5">
                <span className="inline-block text-xs font-semibold tracking-wider uppercase text-sky-300 bg-sky-500/20 border border-sky-400/30 px-2.5 py-0.5 rounded-full">
                  OptiWear AI
                </span>
                <span className="text-xs text-slate-400">| Mikro-Lokasyon & Termal Profil</span>
              </div>
              <h1 className="text-xl sm:text-2xl font-bold text-white tracking-tight flex flex-wrap items-center gap-2">
                <span className="bg-gradient-to-r from-sky-400 via-teal-300 to-indigo-400 bg-clip-text text-transparent">
                  OptiWear
                </span>
                <span className="text-white/80 font-normal text-lg sm:text-xl">
                  – Akıllı Giyim Asistanı
                </span>
              </h1>
              <p className="text-sm text-slate-300 mt-1">
                81 ilden şehrinizi seçin veya tek tıkla konumunuzu bulun; anlık
                hava olayına ve vücut yapınıza göre kişiselleştirilmiş öneri alın.
              </p>
            </div>
          </div>

          <form onSubmit={handleSubmit} className="space-y-5">
            {/* Konumumu Bul (Geolocation) Alanı */}
            <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-sky-500/10 border border-sky-400/25 p-3">
              <div className="text-xs sm:text-sm text-sky-100">
                {locationMessage ? (
                  <span className="font-medium text-emerald-300">
                    ✓ {locationMessage}
                  </span>
                ) : (
                  <span>
                    Koordinat bazlı nokta atışı hava durumu için konumunu bul.
                  </span>
                )}
              </div>

              <div className="flex items-center gap-2">
                {formData.lat !== null && (
                  <button
                    type="button"
                    onClick={handleClearGps}
                    className="text-xs text-slate-300 hover:text-rose-400 underline px-2 py-1 cursor-pointer"
                  >
                    Sıfırla
                  </button>
                )}
                <button
                  type="button"
                  onClick={handleFindLocation}
                  disabled={isLocating}
                  className="inline-flex items-center gap-1.5 rounded-lg bg-sky-500/20 hover:bg-sky-500/30 border border-sky-400/40 px-3 py-1.5 text-xs font-semibold text-sky-200 transition shadow-sm cursor-pointer"
                >
                  <span>📍</span>
                  <span>
                    {isLocating ? "Konum Bulunuyor..." : "Konumumu Bul"}
                  </span>
                </button>
              </div>
            </div>

            {/* 81 İl Dinamik Combobox & İlçe Alanı */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {/* Dinamik İl Seçimi (Combobox / Autocomplete) */}
              <div ref={comboboxRef} className="relative">
                <label
                  htmlFor="city-combobox"
                  className="block text-sm font-medium text-slate-200 mb-1.5"
                >
                  İl (81 İl Arama){" "}
                  {formData.lat !== null && (
                    <span className="text-xs text-slate-400">(Opsiyonel)</span>
                  )}
                </label>
                <div className="relative">
                  <input
                    id="city-combobox"
                    type="text"
                    autoComplete="off"
                    required={formData.lat === null}
                    placeholder="İl yazın veya seçin (Örn: Bursa, Ankara)..."
                    value={formData.city}
                    onFocus={() => {
                      setIsCityOpen(true);
                      setHighlightedIndex(0);
                    }}
                    onChange={(e) => {
                      setFormData((prev) => ({
                        ...prev,
                        city: e.target.value,
                      }));
                      setIsCityOpen(true);
                      setHighlightedIndex(0);
                    }}
                    onKeyDown={(e) => {
                      if (!isCityOpen && e.key === "ArrowDown") {
                        setIsCityOpen(true);
                        return;
                      }
                      if (e.key === "ArrowDown") {
                        e.preventDefault();
                        setHighlightedIndex((prev) =>
                          filteredProvinces.length > 0
                            ? (prev + 1) % filteredProvinces.length
                            : 0
                        );
                      } else if (e.key === "ArrowUp") {
                        e.preventDefault();
                        setHighlightedIndex((prev) =>
                          filteredProvinces.length > 0
                            ? (prev - 1 + filteredProvinces.length) %
                              filteredProvinces.length
                            : 0
                        );
                      } else if (
                        e.key === "Enter" &&
                        isCityOpen &&
                        filteredProvinces[highlightedIndex]
                      ) {
                        e.preventDefault();
                        const selected = filteredProvinces[highlightedIndex];
                        setFormData((prev) => ({ ...prev, city: selected }));
                        setIsCityOpen(false);
                      } else if (e.key === "Escape") {
                        setIsCityOpen(false);
                      }
                    }}
                    className="w-full rounded-xl border border-white/20 bg-white/10 pl-4 pr-9 py-2.5 text-sm text-white placeholder-slate-400 focus:border-sky-400 focus:bg-slate-900/90 focus:outline-none focus:ring-2 focus:ring-sky-400/30 transition"
                  />
                  <button
                    type="button"
                    tabIndex={-1}
                    onClick={() => setIsCityOpen((prev) => !prev)}
                    className="absolute inset-y-0 right-2.5 flex items-center text-slate-400 hover:text-white cursor-pointer"
                  >
                    <svg
                      className={`h-4 w-4 transition-transform ${
                        isCityOpen ? "rotate-180" : ""
                      }`}
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M19 9l-7 7-7-7"
                      />
                    </svg>
                  </button>
                </div>

                {/* Combobox Açılır Menüsü */}
                {isCityOpen && (
                  <ul className="absolute z-50 mt-1.5 max-h-52 w-full overflow-y-auto rounded-xl border border-white/20 bg-slate-900/95 backdrop-blur-xl py-1 text-sm shadow-2xl">
                    {filteredProvinces.length > 0 ? (
                      filteredProvinces.map((province, idx) => (
                        <li
                          key={province}
                          onMouseDown={(e) => {
                            e.preventDefault();
                            setFormData((prev) => ({
                              ...prev,
                              city: province,
                            }));
                            setIsCityOpen(false);
                          }}
                          onMouseEnter={() => setHighlightedIndex(idx)}
                          className={`flex items-center justify-between px-3.5 py-2 cursor-pointer transition ${
                            idx === highlightedIndex
                              ? "bg-sky-500/30 text-white font-medium"
                              : "text-slate-200 hover:bg-white/10"
                          }`}
                        >
                          <span>{province}</span>
                          {formData.city.toLocaleLowerCase("tr-TR") ===
                            province.toLocaleLowerCase("tr-TR") && (
                            <span className="text-sky-400 text-xs">✓</span>
                          )}
                        </li>
                      ))
                    ) : (
                      <li className="px-3.5 py-2 text-xs text-slate-400">
                        Eşleşen il bulunamadı.
                      </li>
                    )}
                  </ul>
                )}
              </div>

              {/* İlçe Alanı */}
              <div>
                <label
                  htmlFor="district"
                  className="block text-sm font-medium text-slate-200 mb-1.5"
                >
                  İlçe <span className="text-xs text-slate-400">(Opsiyonel)</span>
                </label>
                <input
                  id="district"
                  name="district"
                  type="text"
                  placeholder="Örn: Sincan, Nilüfer, Kadıköy..."
                  value={formData.district}
                  onChange={(e) =>
                    setFormData((prev) => ({
                      ...prev,
                      district: e.target.value,
                    }))
                  }
                  className="w-full rounded-xl border border-white/20 bg-white/10 px-4 py-2.5 text-sm text-white placeholder-slate-400 focus:border-sky-400 focus:bg-slate-900/90 focus:outline-none focus:ring-2 focus:ring-sky-400/30 transition"
                />
              </div>
            </div>

            {/* Boy ve Kilo (Gerçekçi Placeholderlar: 175 cm ve 75 kg) */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label
                  htmlFor="height"
                  className="block text-sm font-medium text-slate-200 mb-1.5"
                >
                  Boy (cm)
                </label>
                <div className="relative">
                  <input
                    id="height"
                    name="height"
                    type="number"
                    min={100}
                    max={250}
                    required
                    placeholder="175"
                    value={formData.height}
                    onChange={(e) =>
                      setFormData((prev) => ({
                        ...prev,
                        height:
                          e.target.value === "" ? "" : Number(e.target.value),
                      }))
                    }
                    className="w-full rounded-xl border border-white/20 bg-white/10 pl-4 pr-11 py-2.5 text-sm text-white placeholder-slate-400 focus:border-sky-400 focus:bg-slate-900/90 focus:outline-none focus:ring-2 focus:ring-sky-400/30 transition"
                  />
                  <span className="pointer-events-none absolute inset-y-0 right-3.5 flex items-center text-xs text-slate-400">
                    cm
                  </span>
                </div>
              </div>

              <div>
                <label
                  htmlFor="weight"
                  className="block text-sm font-medium text-slate-200 mb-1.5"
                >
                  Kilo (kg)
                </label>
                <div className="relative">
                  <input
                    id="weight"
                    name="weight"
                    type="number"
                    min={30}
                    max={300}
                    required
                    placeholder="75"
                    value={formData.weight}
                    onChange={(e) =>
                      setFormData((prev) => ({
                        ...prev,
                        weight:
                          e.target.value === "" ? "" : Number(e.target.value),
                      }))
                    }
                    className="w-full rounded-xl border border-white/20 bg-white/10 pl-4 pr-11 py-2.5 text-sm text-white placeholder-slate-400 focus:border-sky-400 focus:bg-slate-900/90 focus:outline-none focus:ring-2 focus:ring-sky-400/30 transition"
                  />
                  <span className="pointer-events-none absolute inset-y-0 right-3.5 flex items-center text-xs text-slate-400">
                    kg
                  </span>
                </div>
              </div>
            </div>

            {/* Terleme Durumu Toggle Alanı */}
            <div className="rounded-xl border border-white/15 bg-white/5 p-4">
              <div className="flex items-center justify-between gap-4">
                <div className="space-y-0.5">
                  <label
                    htmlFor="sweats-toggle"
                    className="text-sm font-medium text-white cursor-pointer"
                  >
                    Soğukta hareket edince çabuk terler misin?
                  </label>
                  <p className="text-xs text-slate-300">
                    Katmanlı giyim (layering) önerisini optimize eder.
                  </p>
                </div>

                <button
                  id="sweats-toggle"
                  type="button"
                  role="switch"
                  aria-checked={formData.sweatsEasily}
                  onClick={() =>
                    setFormData((prev) => ({
                      ...prev,
                      sweatsEasily: !prev.sweatsEasily,
                    }))
                  }
                  className={`relative inline-flex h-7 w-14 shrink-0 cursor-pointer items-center rounded-full p-1 transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-sky-400/40 ${
                    formData.sweatsEasily ? "bg-sky-500" : "bg-slate-700"
                  }`}
                >
                  <span className="sr-only">
                    Soğukta hareket edince çabuk terler misin?
                  </span>
                  <span
                    className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow-sm ring-0 transition duration-200 ease-in-out ${
                      formData.sweatsEasily ? "translate-x-7" : "translate-x-0"
                    }`}
                  />
                </button>
              </div>

              <div className="mt-2.5 flex items-center gap-2">
                <span
                  className={`inline-flex items-center rounded-md px-2.5 py-0.5 text-xs font-semibold transition ${
                    formData.sweatsEasily
                      ? "bg-sky-500/25 text-sky-200 border border-sky-400/30"
                      : "bg-white/10 text-slate-300"
                  }`}
                >
                  Seçim: {formData.sweatsEasily ? "Evet" : "Hayır"}
                </span>
              </div>
            </div>

            {/* Gönder Butonu */}
            <button
              type="submit"
              disabled={isLoading}
              className="w-full flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-sky-500 to-indigo-600 hover:from-sky-400 hover:to-indigo-500 disabled:opacity-60 disabled:cursor-not-allowed active:scale-[0.99] text-white font-semibold py-3.5 px-4 text-sm shadow-lg transition-all focus:outline-none focus:ring-2 focus:ring-sky-400/40 cursor-pointer"
            >
              {isLoading ? (
                <>
                  <svg
                    className="h-4 w-4 animate-spin text-white"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <circle
                      className="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      strokeWidth="4"
                    />
                    <path
                      className="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                    />
                  </svg>
                  <span>Yapay Zeka & Hava Durumu Analiz Ediliyor...</span>
                </>
              ) : (
                <span>OptiWear ile Kişiselleştirilmiş Öneri Al</span>
              )}
            </button>
          </form>
        </div>

        {/* Hata Mesajı Kartı */}
        {error && (
          <div className="backdrop-blur-xl rounded-2xl bg-rose-950/80 border border-rose-400/40 p-4 text-sm text-rose-100 shadow-xl">
            <p className="font-semibold">Hata Oluştu</p>
            <p className="mt-0.5 text-xs sm:text-sm opacity-90">{error}</p>
          </div>
        )}

        {/* Kıyafet Önerisi Sonuç Kartı */}
        {result && (
          <div className="backdrop-blur-xl rounded-2xl bg-gradient-to-br from-slate-900/90 via-sky-950/90 to-indigo-950/90 border border-sky-400/30 text-white shadow-2xl p-6 sm:p-7 transition-all">
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-white/15 pb-4 mb-4">
              <div>
                <span className="text-xs font-medium uppercase tracking-wider text-sky-300">
                  Canlı Hava Olayı & Termal Analiz
                </span>
                <h2 className="text-lg sm:text-xl font-bold tracking-tight mt-0.5">
                  {result.sehir}
                </h2>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <div className="rounded-xl bg-sky-500/25 border border-sky-400/30 px-3 py-1.5 text-center">
                  <span className="block text-[10px] uppercase tracking-wider text-sky-200">
                    Durum
                  </span>
                  <span className="text-sm font-bold text-white">
                    {result.hava_durumu_durumu}
                  </span>
                </div>
                <div className="rounded-xl bg-white/10 px-3 py-1.5 text-center">
                  <span className="block text-[10px] uppercase tracking-wider text-sky-200">
                    Sıcaklık
                  </span>
                  <span className="text-sm font-semibold">
                    {result.sicaklik}°C
                  </span>
                </div>
                <div className="rounded-xl bg-white/15 px-3 py-1.5 text-center">
                  <span className="block text-[10px] uppercase tracking-wider text-sky-200">
                    Hissedilen
                  </span>
                  <span className="text-sm font-semibold">
                    {result.hissedilen_sicaklik}°C
                  </span>
                </div>
                <div className="rounded-xl bg-white/10 px-3 py-1.5 text-center">
                  <span className="block text-[10px] uppercase tracking-wider text-sky-200">
                    Rüzgar
                  </span>
                  <span className="text-sm font-semibold">
                    {result.ruzgar_hizi} km/s
                  </span>
                </div>
                <div className="rounded-xl bg-white/10 px-3 py-1.5 text-center">
                  <span className="block text-[10px] uppercase tracking-wider text-sky-200">
                    VKE
                  </span>
                  <span className="text-sm font-semibold">{result.vke}</span>
                </div>
              </div>
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-sky-300 flex items-center gap-2">
                  <img
                    src="/logo.png"
                    alt="OptiWear"
                    className="h-5 w-5 rounded-md bg-white p-0.5 object-contain"
                  />
                  <span>OptiWear & Gemini AI Kombin ve Ekipman Önerin</span>
                </h3>
                <span className="text-[11px] bg-white/10 px-2.5 py-0.5 rounded-full text-sky-200">
                  {result.kullanilan_senaryo_sayisi} geçmiş senaryo analiz edildi
                </span>
              </div>
              <p className="text-sm sm:text-base leading-relaxed text-white/95 font-medium">
                {result.oneri}
              </p>
            </div>
          </div>
        )}
      </div>
    </>
  );
}

// ==========================================
// 6 Farklı Kod Tabanlı CSS Hava Olayı Arka Plan Bileşeni
// ==========================================
function WeatherAnimatedBackground({ theme }: { theme: WeatherTheme }) {
  return (
    <div className="fixed inset-0 z-0 overflow-hidden pointer-events-none select-none transition-colors duration-1000">
      <style>{`
        @keyframes rainFall {
          0% { transform: translateY(-15vh) translateX(0) rotate(12deg); }
          100% { transform: translateY(115vh) translateX(-18vh) rotate(12deg); }
        }
        @keyframes snowFall {
          0% { transform: translateY(-10vh) translateX(0) rotate(0deg); }
          50% { transform: translateY(50vh) translateX(25px) rotate(180deg); }
          100% { transform: translateY(110vh) translateX(-15px) rotate(360deg); }
        }
        @keyframes hailFall {
          0% { transform: translateY(-15vh) translateX(0); }
          85% { transform: translateY(96vh) translateX(-10vh); }
          92% { transform: translateY(90vh) translateX(-12vh); }
          100% { transform: translateY(105vh) translateX(-14vh); }
        }
        @keyframes windSweep {
          0% { transform: translateX(-30vw); opacity: 0; }
          30% { opacity: 0.55; }
          70% { opacity: 0.55; }
          100% { transform: translateX(120vw); opacity: 0; }
        }
        @keyframes cloudDrift {
          0% { transform: translateX(-25%); }
          50% { transform: translateX(15%); }
          100% { transform: translateX(-25%); }
        }
        @keyframes sunPulse {
          0%, 100% { transform: scale(1); opacity: 0.85; }
          50% { transform: scale(1.12); opacity: 1; }
        }
        @keyframes frostShimmer {
          0%, 100% { opacity: 0.25; transform: scale(1); }
          50% { opacity: 0.65; transform: scale(1.04); }
        }
        @keyframes lightningFlash {
          0%, 92%, 96%, 100% { opacity: 0; }
          94%, 98% { opacity: 0.35; }
        }
      `}</style>

      {/* 1. GÜNEŞLİ */}
      <div
        className={`absolute inset-0 transition-opacity duration-1000 bg-gradient-to-br from-sky-500 via-amber-500/80 to-orange-700 ${
          theme === "Güneşli" ? "opacity-100" : "opacity-0"
        }`}
      >
        <div
          style={{ animation: "sunPulse 5s ease-in-out infinite" }}
          className="absolute -top-20 -right-20 h-96 w-96 rounded-full bg-gradient-to-br from-yellow-200 via-amber-300 to-orange-400 blur-2xl"
        />
        <div
          style={{ animation: "sunPulse 7s ease-in-out infinite" }}
          className="absolute top-12 right-12 h-48 w-48 rounded-full bg-yellow-100/70 blur-md"
        />
      </div>

      {/* 2. SOĞUK / AYAZ */}
      <div
        className={`absolute inset-0 transition-opacity duration-1000 bg-gradient-to-b from-slate-950 via-cyan-950 to-blue-950 ${
          theme === "Soğuk/Ayaz" ? "opacity-100" : "opacity-0"
        }`}
      >
        {/* Kenar Kırağı / Buz Efekti */}
        <div
          style={{ animation: "frostShimmer 4s ease-in-out infinite" }}
          className="absolute inset-0 shadow-[inset_0_0_120px_rgba(165,243,252,0.45)] border-[12px] border-cyan-200/15"
        />
        <div className="absolute top-1/4 left-1/4 h-72 w-72 rounded-full bg-cyan-400/15 blur-3xl animate-pulse" />
        <div className="absolute bottom-1/4 right-1/4 h-80 w-80 rounded-full bg-sky-300/15 blur-3xl animate-pulse" />
      </div>

      {/* 3. YAĞMURLU */}
      <div
        className={`absolute inset-0 transition-opacity duration-1000 bg-gradient-to-b from-slate-950 via-slate-900 to-indigo-950 ${
          theme === "Yağmurlu" ? "opacity-100" : "opacity-0"
        }`}
      >
        {RAIN_PARTICLES.map((drop, idx) => (
          <span
            key={idx}
            style={{
              left: `${drop.left}%`,
              opacity: drop.opacity,
              animation: `rainFall ${drop.duration}s linear ${drop.delay}s infinite`,
            }}
            className="absolute top-0 h-10 w-[1.5px] bg-gradient-to-b from-transparent via-sky-300 to-sky-100"
          />
        ))}
      </div>

      {/* 4. KARLI */}
      <div
        className={`absolute inset-0 transition-opacity duration-1000 bg-gradient-to-b from-slate-900 via-blue-950 to-slate-950 ${
          theme === "Karlı" ? "opacity-100" : "opacity-0"
        }`}
      >
        {SNOW_PARTICLES.map((flake, idx) => (
          <span
            key={idx}
            style={{
              left: `${flake.left}%`,
              width: `${flake.size}px`,
              height: `${flake.size}px`,
              animation: `snowFall ${flake.duration}s ease-in-out ${flake.delay}s infinite`,
            }}
            className="absolute top-0 rounded-full bg-white/85 shadow-[0_0_8px_rgba(255,255,255,0.9)]"
          />
        ))}
      </div>

      {/* 5. RÜZGARLI (HAREKETLİ BULUTLAR & RÜZGAR ÇİZGİLERİ) */}
      <div
        className={`absolute inset-0 transition-opacity duration-1000 bg-gradient-to-br from-slate-800 via-slate-900 to-teal-950 ${
          theme === "Rüzgarlı" ? "opacity-100" : "opacity-0"
        }`}
      >
        <div
          style={{ animation: "cloudDrift 14s ease-in-out infinite" }}
          className="absolute top-12 left-10 h-40 w-96 rounded-full bg-slate-400/20 blur-3xl"
        />
        <div
          style={{ animation: "cloudDrift 18s ease-in-out infinite reverse" }}
          className="absolute top-48 right-10 h-48 w-[28rem] rounded-full bg-teal-300/15 blur-3xl"
        />
        {WIND_STREAKS.map((streak, idx) => (
          <span
            key={idx}
            style={{
              top: `${streak.top}%`,
              width: `${streak.width}px`,
              animation: `windSweep ${streak.duration}s ease-in-out ${streak.delay}s infinite`,
            }}
            className="absolute left-0 h-[2px] rounded-full bg-gradient-to-r from-transparent via-teal-200/50 to-transparent"
          />
        ))}
      </div>

      {/* 6. DOLU & FIRTINA */}
      <div
        className={`absolute inset-0 transition-opacity duration-1000 bg-gradient-to-b from-zinc-950 via-slate-900 to-purple-950 ${
          theme === "Dolu" ? "opacity-100" : "opacity-0"
        }`}
      >
        <div
          style={{ animation: "lightningFlash 6s infinite" }}
          className="absolute inset-0 bg-white pointer-events-none"
        />
        {HAIL_PARTICLES.map((stone, idx) => (
          <span
            key={idx}
            style={{
              left: `${stone.left}%`,
              width: `${stone.size}px`,
              height: `${stone.size}px`,
              animation: `hailFall ${stone.duration}s linear ${stone.delay}s infinite`,
            }}
            className="absolute top-0 rounded-full bg-gradient-to-br from-white via-cyan-100 to-sky-300 shadow-[0_0_6px_rgba(255,255,255,0.8)]"
          />
        ))}
      </div>
    </div>
  );
}
