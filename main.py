# -*- coding: utf-8 -*-
import os
import re
import secrets
import unicodedata
import uuid
from datetime import datetime, timedelta
from typing import List, Optional, Union
import httpx
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy.orm import Session

from database import EmailOTP, User, UserCustomRoutine, UserRoutine, UserScenario, get_db, init_db
from security import (
    ACCESS_TOKEN_EXPIRE_MINUTES,
    create_access_token,
    create_refresh_token,
    decode_token,
    decrypt_pii,
    encrypt_pii,
    get_current_active_user,
    get_optional_user,
    hash_password,
    logger as security_logger,
    mask_phone_number,
    rate_limiter,
    verify_password,
)

# .env dosyasındaki ortam değişkenlerini yükle
load_dotenv()

# Uygulama başlarken scenarios.db ve tabloları (users, user_routines, user_scenarios) oluştur
init_db()

app = FastAPI(
    title="OptiWear API - Kişiselleştirilmiş Hava Durumu, Güvenli Auth & Giyim Öneri AI",
    description=(
        "OptiWear: Argon2id/Scrypt + JWT Auth, Fernet PII Şifreleme, SlowAPI/Sliding-Window Firewall, "
        "Günlük Rutin Bildirimi ve Gemini AI destekli servis."
    ),
    version="5.1.0",
)

# ==========================================
# Siber Güvenlik & Firewall Katmanı: Strict CORS + HSTS / CSP Başlıkları
# ==========================================
_raw_origins = os.getenv(
    "ALLOWED_ORIGINS",
    "http://localhost:3000,http://127.0.0.1:3000,http://localhost:8080",
)
ALLOWED_ORIGINS = [o.strip() for o in _raw_origins.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1|10\.0\.2\.2|192\.168\.\d+\.\d+)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)


@app.middleware("http")
async def security_headers_middleware(request: Request, call_next):
    """
    Her HTTP yanıtına HSTS, CSP, X-Frame-Options ve MIME-sniffing koruma
    başlıklarını ekleyen güvenlik duvarı katmanı.
    """
    response: Response = await call_next(request)
    response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains; preload"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    # Swagger UI (/docs) dışındaki tüm API yanıtlarında katı CSP uygula
    if not request.url.path.startswith(("/docs", "/redoc", "/openapi.json")):
        response.headers["Content-Security-Policy"] = "default-src 'self'; frame-ancestors 'none'"
    return response

OPENWEATHER_API_KEY = os.getenv("OPENWEATHER_API_KEY", "").strip()
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()

SYSTEM_INSTRUCTION = (
    "Sen OptiWear'ın uzman termal konfor danışmanı ve kişisel giyim stratejistisin. "
    "Görevin; kullanıcının boyu, kilosu, hesaplanan Vücut Kitle Endeksi (VKE), "
    "soğukta hareket edince çabuk terleme eğilimi, bulunduğu mikro-konumun (İl/İlçe veya Koordinat) "
    "anlık hissedilen sıcaklığı (feels_like), rüzgar hızı, anlık hava olayı (Güneşli, Yağmurlu, Karlı, "
    "Rüzgarlı, Soğuk/Ayaz, Dolu) ve kullanıcının geçmiş deneyim senaryolarını bir arada analiz ederek "
    "nokta atışı, gerçekçi ve kişiselleştirilmiş bir kıyafet önerisi sunmaktır.\n\n"
    "Analiz İlkelerin:\n"
    "1. VKE yüksek olan ve çabuk terleyen kişiler, hava soğuk (hatta 5°C ve altı) olsa bile "
    "yüksek bazal ısı üretimi nedeniyle kalın tek parça mont veya kazaklarla hızla terleyip "
    "ardından rüzgarda üşütme riski yaşarlar. Bu kişilere ev içi konforu ve dışarı çıkarken kolayca "
    "çıkarılıp giyilebilen katmanlı (layering), nefes alan, fermuarlı kıyafetleri öner.\n"
    "2. Kullanıcının geçmiş senaryolarını analiz et. Örneğin geçmişte 10 derecede yürürken montla "
    "terlediğini belirtmişse, bugünkü benzer tahminde bu hatayı tekrarlatmayacak, o veriye doğrudan "
    "atıfta bulunan (örn: 'Geçen sefer yürürken montla terlemiştin, bu yüzden bugün...') nokta atışı bir öneri yap.\n"
    "3. Sadece termal denge (VKE/sıcaklık) düşünme; eğer hava yağmurluysa su geçirmez dış katman veya "
    "şemsiye, karlıysa kaymaz tabanlı bot, rüzgarlıysa rüzgarlık, dolu/fırtına varsa koruyucu kapüşonlu "
    "dış katman gibi fonksiyonel eşyaları da senaryoya göre mutlaka öner.\n"
    "4. Yanıtını doğrudan kullanıcıya hitap eden ('sen' diliyle), akıcı, samimi, net ve "
    "maksimum 3-5 cümlelik temiz bir paragraf olarak Türkçe ver; madde işareti veya "
    "markdown başlığı kullanma."
)

PREFERRED_MODELS = [
    "gemini-3.8-flash",
    "gemini-3.1-flash-lite",
    "gemini-3.1-flash-lite-preview",
    "gemini-flash-lite-latest",
    "gemini-flash-latest",
    "gemini-2.5-flash-lite",
    "gemini-2.5-flash",
]


# ==========================================
# WMO Hava Durumu Kodu -> Türkçe & Animasyon Eşleştirici
# ==========================================
def map_wmo_weather_code(wmo_code: int, temp: float, wind_speed: float) -> str:
    """
    Open-Meteo WMO hava durumu kodlarını (weather_code), sıcaklığı ve rüzgar hızını
    değerlendirerek Frontend'deki 6 ana animasyon durumundan birine çevirir:
    'Güneşli', 'Soğuk/Ayaz', 'Yağmurlu', 'Karlı', 'Rüzgarlı', 'Dolu'
    """
    # 95, 96, 99: Gök gürültülü fırtına ve dolu
    if wmo_code in (95, 96, 99):
        return "Dolu"

    # 71, 73, 75, 77, 85, 86: Kar yağışı ve tipi
    if wmo_code in (71, 73, 75, 77, 85, 86):
        return "Karlı"

    # 51-67, 80-82: Çisenti, yağmur ve sağanak yağış
    if wmo_code in (51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82):
        return "Yağmurlu"

    # Rüzgar hızı 22 km/s üzerindeyse veya parçalı/kapalı bulutlu (2, 3) olup rüzgar belirginse
    if wind_speed >= 22.0 or (wmo_code in (2, 3) and wind_speed >= 14.0):
        return "Rüzgarlı"

    # Sıcaklık 4°C ve altındaysa veya sis/kırağı (45, 48) varsa
    if temp <= 4.0 or wmo_code in (45, 48):
        return "Soğuk/Ayaz"

    # Bulutlu (2, 3) ama ılıksa Rüzgarlı/Bulutlu animasyonu
    if wmo_code in (2, 3):
        return "Rüzgarlı"

    # 0, 1: Açık / Az bulutlu ve ılık/sıcak
    return "Güneşli"


# ==========================================
# Pydantic Şemaları & Girdi Doğrulama (UTF-8 Türkçe Karakter Uyumlu Sanitization)
# ==========================================
_EMAIL_REGEX = re.compile(r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$")
_PHONE_REGEX = re.compile(r"^\+?[0-9]{10,15}$")
_TIME_REGEX = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")
_XSS_DANGEROUS_CHARS = re.compile(r"[<>`]")
_TURKISH_TEXT_REGEX = re.compile(
    r"^[a-zA-ZçğıöşüÇĞİÖŞÜ0-9\s\.\-\'\,\(\)\!\?\:\/\&\+]+$",
    re.UNICODE,
)


def _normalize_email_tr(raw_email: str) -> str:
    """
    E-posta adresinde sehven kullanılan Türkçe İ/ı/I karakterlerini ve Unicode
    combining dot (\u0307) karakterini temizleyerek küçük harfe çevirir.
    """
    s = unicodedata.normalize("NFC", (raw_email or "").strip())
    s = s.replace("İ", "i").replace("I", "i").replace("ı", "i")
    s = s.lower().replace("\u0307", "")
    return s


class RegisterRequest(BaseModel):
    email: str = Field(..., examples=["kullanici@optiwear.app"], description="Geçerli e-posta adresi")
    password: str = Field(
        ...,
        min_length=8,
        max_length=64,
        examples=["GüçlüŞifre123!"],
        description="En az 8 karakter, 1 büyük harf, 1 küçük harf ve 1 rakam içermeli (Türkçe karakter destekli)",
    )
    full_name: str = Field(..., min_length=2, max_length=120, examples=["Mehmet İhsan Öztürk"])
    phone_number: str = Field(..., examples=["+905551234567"], description="Uluslararası E.164 veya 10-15 haneli telefon")

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        cleaned = _normalize_email_tr(v)
        if not _EMAIL_REGEX.match(cleaned) or len(cleaned) > 255:
            raise ValueError("Geçerli bir e-posta adresi giriniz.")
        return cleaned

    @field_validator("password")
    @classmethod
    def validate_password_complexity(cls, v: str) -> str:
        norm = unicodedata.normalize("NFC", v or "")
        if len(norm) < 8:
            raise ValueError("Şifre en az 8 karakter uzunluğunda olmalıdır.")
        has_upper = any(ch.isupper() or ch in "ÇĞİÖŞÜ" for ch in norm)
        has_lower = any(ch.islower() or ch in "çğıöşü" for ch in norm)
        has_digit = any(ch.isdigit() for ch in norm)
        if not has_upper:
            raise ValueError("Şifre en az 1 büyük harf (A-Z veya ÇĞİÖŞÜ) içermelidir.")
        if not has_lower:
            raise ValueError("Şifre en az 1 küçük harf (a-z veya çğıöşü) içermelidir.")
        if not has_digit:
            raise ValueError("Şifre en az 1 rakam içermelidir.")
        return norm

    @field_validator("full_name")
    @classmethod
    def sanitize_full_name(cls, v: str) -> str:
        norm = unicodedata.normalize("NFC", (v or "").strip())
        cleaned = _XSS_DANGEROUS_CHARS.sub("", norm)
        if len(cleaned) < 2:
            raise ValueError("İsim-soyisim en az 2 karakter olmalıdır.")
        if not _TURKISH_TEXT_REGEX.match(cleaned):
            cleaned = re.sub(r"[^a-zA-ZçğıöşüÇĞİÖŞÜ0-9\s\.\-\']", "", cleaned).strip()
        return cleaned

    @field_validator("phone_number")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        cleaned = re.sub(r"[\s\-\(\)]", "", (v or "").strip())
        if not _PHONE_REGEX.match(cleaned):
            raise ValueError(
                "Telefon numarası 10 ile 15 rakam arasında olmalıdır (Örn: +905551234567 veya 05551234567)."
            )
        return cleaned


class LoginRequest(BaseModel):
    email: str = Field(..., examples=["kullanici@optiwear.app"])
    password: str = Field(..., min_length=1, max_length=128)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return _normalize_email_tr(v)


class VerifyEmailRequest(BaseModel):
    email: str = Field(..., examples=["kullanici@optiwear.app"], description="Kayıt olunan e-posta adresi")
    otp_code: str = Field(..., min_length=6, max_length=6, examples=["123456"], description="6 haneli doğrulama kodu")

    @field_validator("email")
    @classmethod
    def normalize_verify_email(cls, v: str) -> str:
        return _normalize_email_tr(v)

    @field_validator("otp_code")
    @classmethod
    def validate_otp_digits(cls, v: str) -> str:
        cleaned = (v or "").strip()
        if not re.match(r"^\d{6}$", cleaned):
            raise ValueError("OTP doğrulama kodu 6 haneli rakamlardan oluşmalıdır.")
        return cleaned


class RegisterOTPResponse(BaseModel):
    durum: str = "otp_gonderildi"
    mesaj: str
    email: str
    verification_required: bool = True
    expires_in_minutes: int = 15


class RefreshTokenRequest(BaseModel):
    refresh_token: str = Field(..., description="Yenileme (Refresh) JWT Token")


class AccountActionRequest(BaseModel):
    password: str = Field(..., description="İşlem onayı için mevcut kullanıcı şifresi")
    access_token: Optional[str] = Field(
        default=None,
        description="Swagger Authorize butonu kullanılmadıysa doğrudan buraya Bearer Access Token yapıştırabilirsiniz",
    )
    email: Optional[str] = Field(
        default=None,
        examples=["kullanici@optiwear.app"],
        description="Token yerine doğrudan e-posta + şifre ile doğrulama yapmak isterseniz e-posta adresiniz",
    )
    reason: Optional[str] = Field(default=None, max_length=250, description="İsteğe bağlı ayrılma/dondurma nedeni")


class UserProfileOut(BaseModel):
    id: str
    email: str
    full_name: str
    phone_masked: str
    is_active: bool
    is_verified: bool = True
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = ACCESS_TOKEN_EXPIRE_MINUTES * 60
    user: UserProfileOut


class RoutineUpdateRequest(BaseModel):
    wake_up_time: str = Field(default="07:30", examples=["07:30"], description="Uyanma saati (HH:MM)")
    sehir: str = Field(default="İstanbul", max_length=100)
    ilce: Optional[str] = Field(default="", max_length=100)
    lat: Optional[float] = Field(default=None)
    lon: Optional[float] = Field(default=None)
    boy: float = Field(default=175.0, gt=50, lt=260)
    kilo: float = Field(default=75.0, gt=20, lt=350)
    terleme_egilimi: str = Field(default="Hayır")
    notification_enabled: bool = Field(default=True)
    fcm_token: Optional[str] = Field(default=None, max_length=500)

    @field_validator("wake_up_time")
    @classmethod
    def validate_time(cls, v: str) -> str:
        cleaned = (v or "").strip()
        if not _TIME_REGEX.match(cleaned):
            raise ValueError("Uyanma saati HH:MM formatında olmalıdır (Örn: 07:30).")
        return cleaned


class RoutineOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: str
    wake_up_time: str
    sehir: str
    ilce: Optional[str]
    lat: Optional[float]
    lon: Optional[float]
    boy: float
    kilo: float
    terleme_egilimi: str
    notification_enabled: bool
    updated_at: datetime


def _compute_10_min_before(hhmm: str) -> str:
    """HH:MM formatındaki saatten tam 10 dakika öncesini hesaplar (Örn: 08:00 -> 07:50)."""
    parts = hhmm.split(":")
    total_mins = (int(parts[0]) * 60 + int(parts[1]) - 10) % 1440
    return f"{total_mins // 60:02d}:{total_mins % 60:02d}"


class CustomRoutineCreate(BaseModel):
    routine_title: str = Field(
        ...,
        min_length=2,
        max_length=150,
        examples=["Sabah İşe Gidiş"],
        description="Rutin adı (Örn: Sabah İşe Gidiş, Akşam Koşusu)",
    )
    routine_time: str = Field(
        ...,
        examples=["08:00"],
        description="Rutin saati (HH:MM formatında, bildirim 10 dk önce tetiklenir)",
    )
    days_of_week: Union[str, List[str]] = Field(
        default="Pzt,Sal,Çar,Per,Cum",
        examples=["Pzt,Sal,Çar,Per,Cum"],
        description="Tekrarlanacak günler (Virgülle ayrılmış metin veya liste)",
    )

    @field_validator("routine_title")
    @classmethod
    def sanitize_title(cls, v: str) -> str:
        norm = unicodedata.normalize("NFC", (v or "").strip())
        cleaned = _XSS_DANGEROUS_CHARS.sub("", norm)
        if len(cleaned) < 2:
            raise ValueError("Rutin başlığı en az 2 karakter olmalıdır.")
        if not _TURKISH_TEXT_REGEX.match(cleaned):
            cleaned = re.sub(r"[^a-zA-ZçğıöşüÇĞİÖŞÜ0-9\s\.\-\'\,\(\)\!\?\:]", "", cleaned).strip()
        return cleaned

    @field_validator("routine_time")
    @classmethod
    def validate_routine_time(cls, v: str) -> str:
        cleaned = (v or "").strip()
        if not _TIME_REGEX.match(cleaned):
            raise ValueError("Rutin saati HH:MM formatında olmalıdır (Örn: 08:00).")
        return cleaned


class CustomRoutineOut(BaseModel):
    id: int
    user_id: Optional[str] = None
    routine_title: str
    routine_time: str
    notify_time: str
    days_of_week: str
    is_enabled: bool = True
    notification_message: str
    sound_asset: str = "routine_alert.mp3"
    created_at: datetime


class ScenarioCreate(BaseModel):
    scenario_text: Optional[str] = Field(
        default=None,
        description="Tekli geçmiş deneyim metni, örn: '15 derecede yürüdüğüm için montla terledim'",
    )
    scenarios: Optional[List[str]] = Field(
        default=None,
        description="Tek seferde birden fazla senaryo eklemek için liste",
    )


class ScenarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    scenario_text: str
    created_at: datetime


class RecommendationRequest(BaseModel):
    sehir: Optional[str] = Field(default="Ankara", description="İl adı, örn: Ankara")
    ilce: Optional[str] = Field(default="Sincan", description="İlçe adı, örn: Sincan")
    lat: Optional[float] = Field(default=None, examples=[None], description="Enlem (HTML5 Geolocation)")
    lon: Optional[float] = Field(default=None, examples=[None], description="Boylam (HTML5 Geolocation)")
    boy: float = Field(default=175, gt=50, lt=260, description="Kullanıcının boyu (cm), örn: 175")
    kilo: float = Field(default=75, gt=20, lt=350, description="Kullanıcının kilosu (kg), örn: 75")
    terleme_egilimi: Union[str, bool] = Field(
        default="Evet", description="Soğukta hareket edince çabuk terleme durumu ('Evet' / 'Hayır' veya bool)"
    )
    gecmis_senaryolar: Optional[List[str]] = Field(
        default=[],
        description="İstek anında doğrudan gönderilen ek senaryolar",
    )


class RecommendationResponse(BaseModel):
    sehir: str
    sicaklik: float
    hissedilen_sicaklik: float
    ruzgar_hizi: float
    wmo_kodu: int
    hava_durumu_durumu: str
    vke: float
    kullanilan_senaryo_sayisi: int
    oneri: str


class CurrentWeatherResponse(BaseModel):
    sehir: str
    sicaklik: float
    hissedilen_sicaklik: float
    ruzgar_hizi: float
    wmo_kodu: int
    hava_durumu_durumu: str


class HourlyAlertResponse(BaseModel):
    sehir: str
    uyari_var_mi: bool
    sicaklik_farki: float
    min_sicaklik: float
    max_sicaklik: float
    ani_hava_olayi: Optional[str] = None
    bildirim_basligi: str
    bildirim_mesaji: str


class TravelDayForecast(BaseModel):
    tarih: str
    min_sicaklik: float
    max_sicaklik: float
    ruzgar_hizi: float
    wmo_kodu: int
    hava_durumu_durumu: str


class TravelRecommendationRequest(BaseModel):
    hedef_sehir: str = Field(..., examples=["Antalya"], description="Seyahat edilecek il veya şehir")
    hedef_ilce: Optional[str] = Field(default="", examples=["Kaş"], description="İsteğe bağlı ilçe")
    baslangic_tarihi: str = Field(..., examples=["2026-11-20"], description="Başlangıç tarihi (YYYY-MM-DD)")
    bitis_tarihi: str = Field(..., examples=["2026-11-24"], description="Bitiş tarihi (YYYY-MM-DD)")
    boy: float = Field(default=175.0, gt=50, lt=260)
    kilo: float = Field(default=75.0, gt=20, lt=350)
    terleme_egilimi: str = Field(default="Hayır")


class TravelRecommendationResponse(BaseModel):
    hedef_sehir: str
    baslangic_tarihi: str
    bitis_tarihi: str
    gun_sayisi: int
    vke: float
    gunluk_tahminler: List[TravelDayForecast]
    valiz_onerisi: str


# ==========================================
# Mikro-Lokasyon & WMO Hava Durumu Servisi
# ==========================================
async def fetch_weather_data(
    sehir: Optional[str] = "",
    ilce: Optional[str] = "",
    lat: Optional[float] = None,
    lon: Optional[float] = None,
) -> dict:
    cleaned_city = (sehir or "").strip()
    cleaned_district = (ilce or "").strip()

    has_valid_gps = (
        lat is not None
        and lon is not None
        and not (lat == 0 and lon == 0)
    )

    if not has_valid_gps and not cleaned_city:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Lütfen bir 'İl' seçin veya 'Konumumu Bul' butonunu kullanın.",
        )

    transport = httpx.AsyncHTTPTransport(local_address="0.0.0.0")

    try:
        async with httpx.AsyncClient(transport=transport, timeout=10.0) as client:
            resolved_label = ""

            if not has_valid_gps:
                geo_url = "https://geocoding-api.open-meteo.com/v1/search"
                resolved_location = None

                if cleaned_district:
                    geo_res = await client.get(
                        geo_url,
                        params={
                            "name": cleaned_district,
                            "count": 10,
                            "language": "tr",
                            "format": "json",
                        },
                    )
                    geo_res.raise_for_status()
                    candidates = geo_res.json().get("results") or []

                    city_lower = cleaned_city.lower()
                    for item in candidates:
                        admin1 = (item.get("admin1") or "").lower()
                        country_code = (item.get("country_code") or "").upper()
                        if city_lower and city_lower in admin1:
                            resolved_location = item
                            break
                        if not resolved_location and country_code == "TR":
                            resolved_location = item

                    if not resolved_location and candidates:
                        resolved_location = candidates[0]

                if not resolved_location and cleaned_city:
                    geo_res = await client.get(
                        geo_url,
                        params={
                            "name": cleaned_city,
                            "count": 1,
                            "language": "tr",
                            "format": "json",
                        },
                    )
                    geo_res.raise_for_status()
                    results = geo_res.json().get("results") or []
                    if results:
                        resolved_location = results[0]

                if not resolved_location:
                    aranan = (
                        f"{cleaned_city} / {cleaned_district}"
                        if cleaned_district
                        else cleaned_city
                    )
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND,
                        detail=f"'{aranan}' için konum bulunamadı. Lütfen il/ilçe adını kontrol edin.",
                    )

                lat = float(resolved_location["latitude"])
                lon = float(resolved_location["longitude"])
                loc_name = resolved_location.get("name", cleaned_district or cleaned_city)
                admin1_name = resolved_location.get("admin1", cleaned_city)

                if cleaned_district and admin1_name and loc_name.lower() != admin1_name.lower():
                    resolved_label = f"{admin1_name}, {loc_name}"
                elif cleaned_district and cleaned_city:
                    resolved_label = f"{cleaned_city}, {cleaned_district}"
                else:
                    resolved_label = loc_name
            else:
                if cleaned_city and cleaned_district:
                    resolved_label = f"{cleaned_city}, {cleaned_district} (GPS)"
                elif cleaned_city:
                    resolved_label = f"{cleaned_city} (GPS)"
                else:
                    resolved_label = f"GPS Konumu ({lat:.3f}, {lon:.3f})"

            # Open-Meteo'dan Sıcaklık, Hissedilen Sıcaklık, Rüzgar Hızı ve WMO weather_code çek
            weather_url = "https://api.open-meteo.com/v1/forecast"
            weather_params = {
                "latitude": lat,
                "longitude": lon,
                "current": "temperature_2m,apparent_temperature,wind_speed_10m,weather_code",
            }
            weather_res = await client.get(weather_url, params=weather_params)
            weather_res.raise_for_status()
            weather_data = weather_res.json()

            current = weather_data.get("current")
            if not current or "apparent_temperature" not in current:
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail="Hava durumu servisinden anlık veri alınamadı.",
                )

            temp = round(float(current["temperature_2m"]), 1)
            feels_like = round(float(current["apparent_temperature"]), 1)
            wind_speed = round(float(current.get("wind_speed_10m", 0.0)), 1)
            wmo_code = int(
                current.get("weather_code", current.get("weathercode", 0))
            )
            weather_status = map_wmo_weather_code(wmo_code, temp, wind_speed)

            return {
                "resolved_city": resolved_label,
                "temp": temp,
                "feels_like": feels_like,
                "wind_speed": wind_speed,
                "wmo_code": wmo_code,
                "weather_status": weather_status,
            }

    except HTTPException:
        raise
    except httpx.TimeoutException:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail="Hava durumu servisine bağlanırken zaman aşımı oluştu.",
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Hava durumu verisi alınırken hata oluştu: {repr(exc)}",
        )


def _extract_gemini_text(data: dict) -> Optional[str]:
    candidates = data.get("candidates", [])
    if candidates:
        parts = candidates[0].get("content", {}).get("parts", [])
        for part in parts:
            if "text" in part and part["text"].strip():
                return part["text"].strip()
    return None


# ==========================================
# Dinamik Senaryo & Hava Olayı Destekli Gemini AI Öneri Motoru
# ==========================================
async def generate_ai_recommendation(
    user_data: RecommendationRequest,
    resolved_location: str,
    temp: float,
    feels_like: float,
    wind_speed: float,
    weather_status: str,
    vke: float,
    past_scenarios: List[str],
) -> str:
    load_dotenv(override=True)
    api_key = os.getenv("GEMINI_API_KEY", "").strip()

    if not api_key or api_key == "BURAYA_GEMINI_API_ANAHTARINI_YAZ":
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="GEMINI_API_KEY tanımlanmamış. Lütfen .env dosyasına Google AI Studio API anahtarınızı ekleyin.",
        )

    if isinstance(user_data.terleme_egilimi, bool):
        terleme_metni = "Evet" if user_data.terleme_egilimi else "Hayır"
    else:
        terleme_metni = (
            "Evet"
            if user_data.terleme_egilimi.strip().lower() in ("evet", "true", "1")
            else "Hayır"
        )

    if past_scenarios:
        senaryo_listesi_metni = "\n".join(
            [f"  {idx + 1}. \"{s}\"" for idx, s in enumerate(past_scenarios)]
        )
        hafiza_blogu = (
            f"Kullanıcının Geçmiş Deneyimleri (Kişisel Hafıza):\n"
            f"{senaryo_listesi_metni}\n"
            f"(Önemli: Yukarıdaki geçmiş deneyimleri bugünkü {feels_like}°C hissedilen sıcaklık, "
            f"'{weather_status}' hava olayı ve {wind_speed} km/s rüzgar verisiyle kıyasla; önerinde "
            f"bu geçmiş deneyimlere doğrudan atıfta bulun!)"
        )
    else:
        hafiza_blogu = "Kullanıcının Geçmiş Deneyimleri: Henüz kayıtlı geçmiş senaryo yok."

    user_prompt = (
        f"Kullanıcı ve Mikro-Lokasyon Hava Verileri:\n"
        f"- Konum (İl/İlçe/GPS): {resolved_location}\n"
        f"- Boy: {user_data.boy} cm\n"
        f"- Kilo: {user_data.kilo} kg\n"
        f"- Hesaplanan VKE (BMI): {vke}\n"
        f"- Soğukta hareket edince çabuk terleme eğilimi: {terleme_metni}\n"
        f"- Anlık Hava Olayı: {weather_status}\n"
        f"- Anlık Gerçek Sıcaklık: {temp}°C\n"
        f"- Anlık Hissedilen Sıcaklık (feels_like): {feels_like}°C\n"
        f"- Anlık Rüzgar Hızı: {wind_speed} km/s\n\n"
        f"{hafiza_blogu}\n\n"
        f"Bu verilere göre kullanıcıya hem termal dengeyi koruyacak hem de '{weather_status}' hava olayına "
        f"uygun fonksiyonel parçaları (yağmurluysa su geçirmez katman/şemsiye, karlıysa kaymaz bot, "
        f"rüzgarlıysa rüzgarlık vb.) içeren ev içi ve dış ortam kıyafet kombin önerisini yaz."
    )

    payload = {
        "system_instruction": {
            "parts": [{"text": SYSTEM_INSTRUCTION}],
        },
        "contents": [
            {
                "role": "user",
                "parts": [{"text": user_prompt}],
            }
        ],
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 450,
        },
    }

    headers = {
        "Content-Type": "application/json",
        "x-goog-api-key": api_key,
    }

    errors_log: List[str] = []
    transport = httpx.AsyncHTTPTransport(local_address="0.0.0.0")

    async with httpx.AsyncClient(transport=transport, timeout=15.0) as client:
        available_models: List[str] = []
        try:
            list_res = await client.get(
                "https://generativelanguage.googleapis.com/v1beta/models",
                headers=headers,
            )
            if list_res.status_code == 200:
                for m in list_res.json().get("models", []):
                    methods = m.get("supportedGenerationMethods", [])
                    if "generateContent" in methods:
                        name = m.get("name", "").replace("models/", "")
                        if (
                            name
                            and "tts" not in name
                            and "image" not in name
                            and "embedding" not in name
                        ):
                            available_models.append(name)
        except Exception as list_exc:
            print(f"[Gemini API] Model listesi alınamadı: {repr(list_exc)}")

        models_to_try: List[str] = []
        for pref in PREFERRED_MODELS:
            if not available_models or pref in available_models:
                if pref not in models_to_try:
                    models_to_try.append(pref)
            else:
                for avail in available_models:
                    if avail.startswith(pref) and avail not in models_to_try:
                        models_to_try.append(avail)

        for avail in available_models:
            if "flash" in avail and avail not in models_to_try:
                models_to_try.append(avail)

        if not models_to_try:
            models_to_try = [
                "gemini-3.8-flash",
                "gemini-3.1-flash-lite",
                "gemini-flash-lite-latest",
                "gemini-2.5-flash",
            ]

        for model_name in models_to_try[:5]:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent"
            print(f"[Gemini API] Deneniyor -> {model_name} ...")
            try:
                res = await client.post(url, headers=headers, json=payload)
                if res.status_code == 200:
                    text = _extract_gemini_text(res.json())
                    if text:
                        print(f"[Gemini API] BAŞARILI -> Model: {model_name}")
                        return text
                    errors_log.append(f"{model_name}: Boş yanıt döndü")
                else:
                    short_err = res.text[:250].replace("\n", " ")
                    print(f"[Gemini API] {model_name} HTTP {res.status_code}: {short_err}")
                    errors_log.append(f"{model_name} ({res.status_code}): {short_err}")
            except Exception as call_exc:
                print(f"[Gemini API] {model_name} bağlantı/süre hatası: {repr(call_exc)}")
                errors_log.append(f"{model_name}: {repr(call_exc)}")
                continue

    raise HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail=f"Gemini AI yanıt veremedi. Denenen modeller: {' | '.join(errors_log)}",
    )


# ==========================================
# Yardımcı Fonksiyon: User -> UserProfileOut Dönüştürücü (PII Maskeli)
# ==========================================
def _to_user_profile_out(user: User) -> UserProfileOut:
    plain_phone = decrypt_pii(user.phone_number)
    return UserProfileOut(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        phone_masked=mask_phone_number(plain_phone),
        is_active=user.is_active,
        is_verified=bool(user.is_verified),
        created_at=user.created_at,
    )


def _send_smtp_otp_email_if_configured(recipient_email: str, full_name: str, otp_code: str) -> bool:
    """
    .env dosyasında SMTP_EMAIL ve SMTP_APP_PASSWORD tanımlıysa gerçek e-posta gönderir.
    Tanımlı değilse yalnızca terminal loguna basar.
    """
    smtp_host = os.getenv("SMTP_HOST", "smtp.gmail.com").strip()
    smtp_port = int(os.getenv("SMTP_PORT", "465").strip() or "465")
    smtp_user = os.getenv("SMTP_EMAIL", "").strip()
    smtp_pass = os.getenv("SMTP_APP_PASSWORD", "").strip()

    if not smtp_user or not smtp_pass:
        return False

    try:
        import smtplib
        import ssl
        from email.message import EmailMessage

        msg = EmailMessage()
        msg["Subject"] = f"OptiWear Doğrulama Kodunuz: {otp_code}"
        msg["From"] = f"OptiWear AI <{smtp_user}>"
        msg["To"] = recipient_email
        msg.set_content(
            f"Merhaba {full_name},\n\n"
            f"OptiWear hesabınızı doğrulamak için 6 haneli tek kullanımlık kodunuz:\n\n"
            f"   {otp_code}\n\n"
            f"Bu kod 15 dakika boyunca geçerlidir.\n"
            f"Eğer bu işlemi siz yapmadıysanız bu e-postayı dikkate almayınız."
        )

        context = ssl.create_default_context()
        with smtplib.SMTP_SSL(smtp_host, smtp_port, context=context, timeout=10) as server:
            server.login(smtp_user, smtp_pass)
            server.send_message(msg)
        print(f"[SMTP] Gerçek doğrulama e-postası gönderildi -> {recipient_email}", flush=True)
        return True
    except Exception as smtp_exc:
        print(f"[SMTP Uyarısı] E-posta gönderilemedi ({smtp_exc}), terminaldeki kodu kullanabilirsiniz.", flush=True)
        return False


def _issue_email_otp(db: Session, user: User) -> str:
    """
    6 haneli kriptografik rastgele OTP üretir, email_otps tablosuna (15 dk geçerli)
    kaydeder, SMTP ayarlıysa gerçek mail atar ve terminale yazdırır.
    """
    db.query(EmailOTP).filter(EmailOTP.user_id == user.id).delete()
    otp_code = f"{secrets.randbelow(900000) + 100000:06d}"
    expires_at = datetime.utcnow() + timedelta(minutes=15)

    otp_row = EmailOTP(
        user_id=user.id,
        otp_code=otp_code,
        expires_at=expires_at,
    )
    db.add(otp_row)
    db.commit()

    sent_real_mail = _send_smtp_otp_email_if_configured(user.email, user.full_name, otp_code)

    banner = (
        "\n========================================================\n"
        f"📧 [OptiWear OTP E-POSTA DOĞRULAMA KODU]\n"
        f"   Alıcı E-Posta : {user.email}\n"
        f"   6 Haneli Kod  : {otp_code}\n"
        f"   Gerçek Mail   : {'GÖNDERİLDİ (Gelen Kutusunu Kontrol Edin)' if sent_real_mail else 'SMTP Ayarsız -> Kod Bu Terminalde!'}\n"
        f"   Geçerlilik    : 15 Dakika ({expires_at.strftime('%H:%M:%S')} UTC)\n"
        "========================================================\n"
    )
    print(banner, flush=True)
    security_logger.info(f"[OTP] {user.email} için 6 haneli doğrulama kodu üretildi: {otp_code}")
    return otp_code


# ==========================================
# 1. KİMLİK DOĞRULAMA & HESAP YÖNETİMİ (/auth/*)
# ==========================================
@app.post(
    "/auth/register",
    response_model=RegisterOTPResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["Kimlik Doğrulama (Auth)"],
)
def register_user(
    payload: RegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Yeni kullanıcı kaydı oluşturur ve 6 haneli OTP doğrulama kodu üretir:
    - Firewall Rate Limit: IP başına dakikada maksimum 5 deneme.
    - Şifre Argon2id/Scrypt ile hashlenir, telefon Fernet/AES ile şifrelenir.
    - is_verified=False olarak kaydedilir ve 6 haneli OTP terminale yazdırılır.
    """
    rate_limiter.check(request, bucket="auth_register", max_requests=5, window_seconds=60)

    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        if existing.is_verified:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Bu e-posta adresi ile doğrulanmış bir hesap zaten mevcut.",
            )
        # Henüz doğrulanmamış hesapsa bilgilerini güncelle ve yeni OTP gönder
        existing.hashed_password = hash_password(payload.password)
        existing.full_name = payload.full_name
        existing.phone_number = encrypt_pii(payload.phone_number)
        existing.is_active = True
        db.commit()
        _issue_email_otp(db, existing)
        return RegisterOTPResponse(
            mesaj="Kayıt bilgileriniz güncellendi. E-postanıza (terminale) gönderilen 6 haneli OTP kodunu doğrulayın.",
            email=existing.email,
            verification_required=True,
            expires_in_minutes=15,
        )

    new_user = User(
        id=str(uuid.uuid4()),
        email=payload.email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
        phone_number=encrypt_pii(payload.phone_number),
        is_active=True,
        is_verified=False,
        token_version=1,
    )
    db.add(new_user)
    db.flush()

    default_routine = UserRoutine(
        user_id=new_user.id,
        wake_up_time="07:30",
        sehir="İstanbul",
        ilce="",
        boy=175.0,
        kilo=75.0,
        terleme_egilimi="Hayır",
        notification_enabled=True,
    )
    db.add(default_routine)
    db.commit()
    db.refresh(new_user)

    _issue_email_otp(db, new_user)

    return RegisterOTPResponse(
        mesaj="Kayıt başarılı! Lütfen e-postanıza (terminale) gönderilen 6 haneli OTP kodunu girerek hesabınızı doğrulayın.",
        email=new_user.email,
        verification_required=True,
        expires_in_minutes=15,
    )


@app.post(
    "/auth/verify-email",
    response_model=TokenResponse,
    tags=["Kimlik Doğrulama (Auth)"],
)
def verify_email_otp(
    payload: VerifyEmailRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    6 Haneli E-Posta OTP Doğrulama Uç Noktası:
    - E-posta ve 6 haneli otp_code doğrulanır.
    - Kod doğru ve süresi (15 dk) geçmemişse is_verified=True yapılır ve
      JWT Access + Refresh Token döner.
    """
    rate_limiter.check(request, bucket="auth_verify_otp", max_requests=10, window_seconds=60)

    user = db.query(User).filter(User.email == payload.email).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Bu e-posta adresine ait kullanıcı bulunamadı.",
        )

    otp_record = (
        db.query(EmailOTP)
        .filter(EmailOTP.user_id == user.id, EmailOTP.otp_code == payload.otp_code)
        .order_by(EmailOTP.id.desc())
        .first()
    )

    if not otp_record:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Girilen 6 haneli OTP doğrulama kodu hatalı.",
        )

    if otp_record.expires_at < datetime.utcnow():
        db.delete(otp_record)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="OTP kodunun süresi (15 dk) dolmuş. Lütfen tekrar giriş veya kayıt deneyerek yeni kod alın.",
        )

    user.is_verified = True
    db.query(EmailOTP).filter(EmailOTP.user_id == user.id).delete()
    db.commit()
    db.refresh(user)

    security_logger.info(f"[AUTH] E-posta OTP doğrulaması başarılı -> user_id={user.id}")

    access_token = create_access_token(user.id, user.token_version)
    refresh_token = create_refresh_token(user.id, user.token_version)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=_to_user_profile_out(user),
    )


@app.post(
    "/auth/login",
    response_model=TokenResponse,
    tags=["Kimlik Doğrulama (Auth)"],
)
def login_user(
    payload: LoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Güvenli Oturum Açma (JWT Access + Refresh Token):
    - Brute-Force Koruması: IP başına dakikada maksimum 5 deneme.
    - E-posta doğrulaması (is_verified=True) yapılmamış hesapların girişine izin verilmez.
    """
    rate_limiter.check(request, bucket="auth_login", max_requests=5, window_seconds=60)

    user = db.query(User).filter(User.email == payload.email).first()
    if not user or not verify_password(payload.password, user.hashed_password):
        security_logger.warning("[AUTH] Başarısız giriş denemesi.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="E-posta adresi veya şifre hatalı.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Hesabınız dondurulmuş veya kapatılmış durumda.",
        )

    if not user.is_verified:
        _issue_email_otp(db, user)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="E-posta adresiniz henüz doğrulanmamış. Yeni 6 haneli OTP kodunuz gönderildi (terminali kontrol edin).",
        )

    access_token = create_access_token(user.id, user.token_version)
    refresh_token = create_refresh_token(user.id, user.token_version)
    security_logger.info(f"[AUTH] Başarılı giriş -> user_id={user.id}")

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=_to_user_profile_out(user),
    )


@app.post(
    "/auth/refresh",
    response_model=TokenResponse,
    tags=["Kimlik Doğrulama (Auth)"],
)
def refresh_user_token(
    payload: RefreshTokenRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Refresh Token kullanarak yeni Access + Refresh Token çifti üretir (Token Rotation).
    Flutter Dio Interceptor tarafından 401 alındığında otomatik çağrılır.
    """
    rate_limiter.check(request, bucket="auth_refresh", max_requests=15, window_seconds=60)

    claims = decode_token(payload.refresh_token, expected_type="refresh")
    user_id = claims.get("sub")
    token_version = claims.get("tv", 1)

    user = db.query(User).filter(User.id == user_id).first()
    if not user or not user.is_active or user.token_version != token_version:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Yenileme oturumu geçersiz veya sonlandırılmış.",
        )

    new_access = create_access_token(user.id, user.token_version)
    new_refresh = create_refresh_token(user.id, user.token_version)
    return TokenResponse(
        access_token=new_access,
        refresh_token=new_refresh,
        user=_to_user_profile_out(user),
    )


@app.get(
    "/auth/me",
    response_model=UserProfileOut,
    tags=["Kimlik Doğrulama (Auth)"],
)
def get_my_profile(current_user: User = Depends(get_current_active_user)):
    """Giriş yapmış kullanıcının profil bilgilerini (PII maskeli olarak) döner."""
    return _to_user_profile_out(current_user)


def _resolve_account_target_user(
    payload: AccountActionRequest,
    header_user: Optional[User],
    db: Session,
) -> User:
    """
    Kullanıcıyı şu 3 yöntemden biriyle çözümler:
    1. Swagger sağ üstteki 'Authorize 🔒' butonu (HTTP Authorization: Bearer Header)
    2. Request Body içindeki 'access_token' alanı
    3. Request Body içindeki 'email' (+ şifre doğrulaması) alanı
    """
    if header_user is not None:
        return header_user

    if payload.access_token and payload.access_token.strip() and payload.access_token.strip() != "string":
        raw_tok = payload.access_token.strip()
        if raw_tok.lower().startswith("bearer "):
            raw_tok = raw_tok[7:].strip()
        claims = decode_token(raw_tok, expected_type="access")
        uid = claims.get("sub")
        tv = claims.get("tv", 1)
        user = db.query(User).filter(User.id == uid).first()
        if not user or not user.is_active or user.token_version != tv:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Gönderilen access_token geçersiz veya süresi dolmuş.",
            )
        return user

    if payload.email and payload.email.strip() and payload.email.strip() != "string":
        normalized_email = payload.email.strip().lower()
        user = db.query(User).filter(User.email == normalized_email).first()
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Belirtilen e-posta adresine ait kullanıcı bulunamadı.",
            )
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bu hesap zaten dondurulmuş veya silinmiş durumda.",
            )
        return user

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=(
            "Kimlik doğrulama bilgisi eksik. Swagger sağ üstteki 'Authorize' butonuna "
            "access_token yapıştırabilir VEYA request body içindeki 'access_token' ya da "
            "'email' alanlarından birini doldurabilirsiniz."
        ),
        headers={"WWW-Authenticate": "Bearer"},
    )


@app.patch(
    "/auth/account",
    tags=["Kimlik Doğrulama (Auth)"],
)
def freeze_account(
    payload: AccountActionRequest,
    header_user: Optional[User] = Depends(get_optional_user),
    db: Session = Depends(get_db),
):
    """
    Hesap Dondurma (Soft-Delete):
    - Mevcut şifreyi doğrular, is_active=False yapar ve token_version'ı artırarak
      tüm cihazlardaki açık JWT oturumlarını anında düşürür.
    """
    current_user = _resolve_account_target_user(payload, header_user, db)

    if not verify_password(payload.password, current_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="İşlem onayı için girilen şifre hatalı.",
        )

    current_user.is_active = False
    current_user.token_version += 1
    if current_user.routine:
        current_user.routine.notification_enabled = False
        current_user.routine.fcm_token = None
    db.commit()

    security_logger.info(f"[AUTH] Hesap donduruldu (soft-delete) -> user_id={current_user.id}")
    return {
        "durum": "donduruldu",
        "mesaj": "Hesabınız güvenli bir şekilde donduruldu ve tüm aktif oturumlarınız kapatıldı.",
    }


@app.delete(
    "/auth/account",
    tags=["Kimlik Doğrulama (Auth)"],
)
def delete_and_anonymize_account(
    payload: AccountActionRequest,
    header_user: Optional[User] = Depends(get_optional_user),
    db: Session = Depends(get_db),
):
    """
    Hesabı Kalıcı Silme (Hard-Delete):
    - Kullanıcının şifresini doğrular.
    - Kullanıcının tüm rutinlerini, senaryolarını ve 'users' tablosundaki kaydını
      veritabanından tamamen (fiziksel olarak) siler.
    """
    current_user = _resolve_account_target_user(payload, header_user, db)

    if not verify_password(payload.password, current_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Hesap silme onayı için girilen şifre hatalı.",
        )

    deleted_user_id = current_user.id
    db.query(EmailOTP).filter(EmailOTP.user_id == deleted_user_id).delete()
    db.query(UserScenario).filter(UserScenario.user_id == deleted_user_id).delete()
    db.query(UserRoutine).filter(UserRoutine.user_id == deleted_user_id).delete()
    db.query(UserCustomRoutine).filter(UserCustomRoutine.user_id == deleted_user_id).delete()
    # Varsa daha önce anonimleştirilmiş hayalet kayıtları da temizle
    db.query(User).filter(User.email.like("deleted_%@anon.optiwear.local")).delete(synchronize_session=False)
    db.delete(current_user)
    db.commit()

    security_logger.info(f"[AUTH] Hesap veritabanından kalıcı olarak silindi (hard-delete) -> user_id={deleted_user_id}")
    return {
        "durum": "silindi",
        "mesaj": "Hesabınız ve tüm ilişkili verileriniz veritabanından kalıcı olarak tamamen silindi.",
    }


# ==========================================
# 2. GÜNLÜK RUTİN & SABAH BİLDİRİM SERVİSİ (/routines/*)
# ==========================================
@app.get(
    "/routines/me",
    response_model=RoutineOut,
    tags=["Günlük Rutin & Mobil Bildirim"],
)
def get_my_routine(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Kullanıcının uyanma saati ve günlük rutin tercihlerini döner."""
    routine = db.query(UserRoutine).filter(UserRoutine.user_id == current_user.id).first()
    if not routine:
        routine = UserRoutine(
            user_id=current_user.id,
            wake_up_time="07:30",
            sehir="İstanbul",
            ilce="",
            boy=175.0,
            kilo=75.0,
            terleme_egilimi="Hayır",
            notification_enabled=True,
        )
        db.add(routine)
        db.commit()
        db.refresh(routine)
    return routine


@app.put(
    "/routines/me",
    response_model=RoutineOut,
    tags=["Günlük Rutin & Mobil Bildirim"],
)
def update_my_routine(
    payload: RoutineUpdateRequest,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Flutter mobil uygulamasından kullanıcının uyanma saati (wake_up_time),
    konumu, boy/kilo verileri ve FCM bildirim anahtarını günceller.
    """
    routine = db.query(UserRoutine).filter(UserRoutine.user_id == current_user.id).first()
    if not routine:
        routine = UserRoutine(user_id=current_user.id)
        db.add(routine)

    routine.wake_up_time = payload.wake_up_time
    routine.sehir = payload.sehir
    routine.ilce = payload.ilce
    routine.lat = payload.lat
    routine.lon = payload.lon
    routine.boy = payload.boy
    routine.kilo = payload.kilo
    routine.terleme_egilimi = payload.terleme_egilimi
    routine.notification_enabled = payload.notification_enabled
    if payload.fcm_token is not None:
        routine.fcm_token = payload.fcm_token

    db.commit()
    db.refresh(routine)
    return routine


@app.post(
    "/routines/me/morning-brief",
    response_model=RecommendationResponse,
    tags=["Günlük Rutin & Mobil Bildirim"],
)
async def trigger_morning_routine_brief(
    request: Request,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Kullanıcının kayıtlı uyanma rutini (user_routines) ve kişisel termal
    hafızasını (user_scenarios) birleştirerek sabah kombin bildirimini üretir.
    """
    rate_limiter.check(request, bucket="morning_brief", max_requests=10, window_seconds=60)

    routine = db.query(UserRoutine).filter(UserRoutine.user_id == current_user.id).first()
    if not routine:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Kayıtlı günlük rutin bulunamadı. Lütfen önce /routines/me üzerinden rutininizi kaydedin.",
        )

    req_model = RecommendationRequest(
        sehir=routine.sehir,
        ilce=routine.ilce,
        lat=routine.lat,
        lon=routine.lon,
        boy=routine.boy,
        kilo=routine.kilo,
        terleme_egilimi=routine.terleme_egilimi,
        gecmis_senaryolar=[],
    )
    return await get_recommendation(
        user_data=req_model,
        request=request,
        db=db,
        current_user=current_user,
    )


def _to_custom_routine_out(item: UserCustomRoutine) -> CustomRoutineOut:
    notify_time = _compute_10_min_before(item.routine_time)
    return CustomRoutineOut(
        id=item.id,
        user_id=item.user_id,
        routine_title=item.routine_title,
        routine_time=item.routine_time,
        notify_time=notify_time,
        days_of_week=item.days_of_week,
        is_enabled=bool(getattr(item, "is_enabled", True)),
        notification_message=(
            f"🔔 '{item.routine_title}' ({item.routine_time}) rutinin yaklaşıyor! "
            "Dışarısı serin olabilir, katmanlı ve iyi giyindiğinden emin ol."
        ),
        sound_asset="routine_alert.mp3",
        created_at=item.created_at,
    )


@app.get(
    "/routines/custom",
    response_model=List[CustomRoutineOut],
    tags=["Günlük Rutin & Mobil Bildirim"],
)
def list_custom_routines(
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_user),
):
    """Kullanıcının eklediği özel günlük rutinleri (ve 10 dk önceki bildirim saatlerini) listeler."""
    query = db.query(UserCustomRoutine)
    if current_user is not None:
        query = query.filter(UserCustomRoutine.user_id == current_user.id)
    else:
        query = query.filter(UserCustomRoutine.user_id.is_(None))
    rows = query.order_by(UserCustomRoutine.routine_time.asc()).all()
    return [_to_custom_routine_out(r) for r in rows]


@app.post(
    "/routines/custom",
    response_model=CustomRoutineOut,
    status_code=status.HTTP_201_CREATED,
    tags=["Günlük Rutin & Mobil Bildirim"],
)
def create_custom_routine(
    payload: CustomRoutineCreate,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_user),
):
    """
    Kullanıcının yeni bir özel rutin (Örn: 'Sabah İşe Gidiş', '08:00', 'Pzt,Sal,Çar,Per,Cum')
    kaydetmesini sağlar ve 10 dk önceki (07:50) zamanlanmış sesli bildirim bilgisini döner.
    """
    if isinstance(payload.days_of_week, list):
        days_str = ",".join(
            _XSS_DANGEROUS_CHARS.sub("", d.strip()) for d in payload.days_of_week if d.strip()
        )
    else:
        days_str = _XSS_DANGEROUS_CHARS.sub("", (payload.days_of_week or "").strip())

    if not days_str:
        days_str = "Pzt,Sal,Çar,Per,Cum,Cmt,Paz"

    uid = current_user.id if current_user is not None else None
    new_routine = UserCustomRoutine(
        user_id=uid,
        routine_title=payload.routine_title,
        routine_time=payload.routine_time,
        days_of_week=days_str[:100],
    )
    db.add(new_routine)
    db.commit()
    db.refresh(new_routine)
    return _to_custom_routine_out(new_routine)


@app.delete(
    "/routines/custom/{routine_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    tags=["Günlük Rutin & Mobil Bildirim"],
)
def delete_custom_routine(
    routine_id: int,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_user),
):
    """Kayıtlı bir özel rutini ID'sine göre siler."""
    query = db.query(UserCustomRoutine).filter(UserCustomRoutine.id == routine_id)
    if current_user is not None:
        query = query.filter(UserCustomRoutine.user_id == current_user.id)
    item = query.first()
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Silinmek istenen özel rutin bulunamadı.",
        )
    db.delete(item)
    db.commit()
    return None


@app.patch(
    "/routines/custom/{routine_id}/toggle",
    response_model=CustomRoutineOut,
    tags=["Günlük Rutin & Mobil Bildirim"],
)
def toggle_custom_routine(
    routine_id: int,
    is_enabled: bool = True,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_user),
):
    """Kayıtlı bir özel rutinin bildirimini açar veya kapatır (Switch)."""
    query = db.query(UserCustomRoutine).filter(UserCustomRoutine.id == routine_id)
    if current_user is not None:
        query = query.filter(UserCustomRoutine.user_id == current_user.id)
    item = query.first()
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Güncellenmek istenen rutin bulunamadı.",
        )
    item.is_enabled = is_enabled
    db.commit()
    db.refresh(item)
    return _to_custom_routine_out(item)


# ==========================================
# 3. GENEL & HAVA DURUMU / ÖNERİ ENDPOINT'LERİ
# ==========================================
@app.get("/")
def root():
    return {
        "proje": "OptiWear API (v5.1)",
        "mesaj": "OptiWear Güvenli Hava Durumu, Rutin & Kıyafet Öneri AI 8001 portunda çalışıyor!",
        "dokumantasyon": "http://127.0.0.1:8001/docs",
        "endpoints": [
            "POST /auth/register",
            "POST /auth/login",
            "POST /auth/refresh",
            "GET /auth/me",
            "PATCH /auth/account (Hesap Dondur)",
            "DELETE /auth/account (Hesap Sil & Anonimleştir)",
            "GET /routines/me",
            "PUT /routines/me",
            "POST /routines/me/morning-brief",
            "GET /scenarios",
            "POST /scenarios",
            "DELETE /scenarios/{scenario_id}",
            "GET /ip-location",
            "POST /get-recommendation",
        ],
    }


@app.get("/ip-location")
async def get_ip_location():
    """
    Masaüstü tarayıcılarda HTML5 Geolocation izni veya GPS donanımı olmadığında
    kullanıcının konumunu (İl, İlçe, Enlem, Boylam) IP üzerinden yedek olarak bulur.
    """
    transport = httpx.AsyncHTTPTransport(local_address="0.0.0.0")
    try:
        async with httpx.AsyncClient(transport=transport, timeout=6.0) as client:
            res = await client.get("http://ip-api.com/json/?fields=status,countryCode,regionName,city,lat,lon")
            if res.status_code == 200:
                data = res.json()
                if data.get("status") == "success":
                    return {
                        "city": data.get("regionName") or data.get("city") or "Ankara",
                        "district": data.get("city") or "",
                        "lat": round(float(data["lat"]), 4),
                        "lon": round(float(data["lon"]), 4),
                    }
    except Exception:
        pass
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Otomatik konum servisine ulaşılamadı.",
    )


@app.get("/scenarios", response_model=List[ScenarioOut])
def list_scenarios(
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_user),
):
    """Kullanıcının kaydettiği geçmiş senaryoları yeniden eskiye listeler."""
    query = db.query(UserScenario)
    if current_user is not None:
        query = query.filter(UserScenario.user_id == current_user.id)
    else:
        query = query.filter(UserScenario.user_id.is_(None))
    return query.order_by(UserScenario.id.desc()).all()


@app.post("/scenarios", response_model=List[ScenarioOut], status_code=status.HTTP_201_CREATED)
def create_scenario(
    payload: ScenarioCreate,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_user),
):
    """Tekli veya çoklu kişisel termal deneyim senaryosu kaydeder."""
    items_to_add: List[str] = []

    if payload.scenario_text and payload.scenario_text.strip():
        items_to_add.append(payload.scenario_text.strip())

    if payload.scenarios:
        for s in payload.scenarios:
            if s and s.strip() and s.strip() != "string":
                items_to_add.append(s.strip())

    if not items_to_add:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="En az bir geçerli senaryo metni girmelisiniz.",
        )

    uid = current_user.id if current_user is not None else None
    created_records: List[UserScenario] = []
    for text_val in items_to_add:
        sanitized_text = _XSS_DANGEROUS_CHARS.sub("", text_val)[:500]
        new_item = UserScenario(user_id=uid, scenario_text=sanitized_text)
        db.add(new_item)
        created_records.append(new_item)

    db.commit()
    for rec in created_records:
        db.refresh(rec)

    return created_records


@app.delete("/scenarios/{scenario_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_scenario(
    scenario_id: int,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_user),
):
    """Kayıtlı bir senaryoyu ID'sine göre siler."""
    query = db.query(UserScenario).filter(UserScenario.id == scenario_id)
    if current_user is not None:
        query = query.filter(UserScenario.user_id == current_user.id)
    item = query.first()
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Silinmek istenen senaryo bulunamadı.",
        )
    db.delete(item)
    db.commit()
    return None


@app.post("/get-recommendation", response_model=RecommendationResponse)
async def get_recommendation(
    user_data: RecommendationRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_user),
):
    # Firewall Hız Sınırı: Gemini API kota koruması (Dakikada max 15 istek)
    rate_limiter.check(request, bucket="get_recommendation", max_requests=15, window_seconds=60)

    # 1. Mikro-lokasyon (İl+İlçe veya GPS koordinatı) hava, rüzgar ve WMO hava olayı verisini çek
    weather = await fetch_weather_data(
        sehir=user_data.sehir,
        ilce=user_data.ilce,
        lat=user_data.lat,
        lon=user_data.lon,
    )

    uid = current_user.id if current_user is not None else None

    # 2. İstek içinde doğrudan gönderilen yeni senaryolar varsa veritabanına kaydet
    if user_data.gecmis_senaryolar:
        existing_query = db.query(UserScenario)
        if uid is not None:
            existing_query = existing_query.filter(UserScenario.user_id == uid)
        else:
            existing_query = existing_query.filter(UserScenario.user_id.is_(None))
        existing_texts = {r.scenario_text for r in existing_query.all()}

        for s in user_data.gecmis_senaryolar:
            cleaned_s = _XSS_DANGEROUS_CHARS.sub("", (s or "").strip())[:500]
            if cleaned_s and cleaned_s != "string" and cleaned_s not in existing_texts:
                db.add(UserScenario(user_id=uid, scenario_text=cleaned_s))
                existing_texts.add(cleaned_s)
        db.commit()

    # 3. Veritabanındaki geçmiş kullanıcı senaryolarını çek
    scenario_query = db.query(UserScenario)
    if uid is not None:
        scenario_query = scenario_query.filter(UserScenario.user_id == uid)
    else:
        scenario_query = scenario_query.filter(UserScenario.user_id.is_(None))

    saved_rows = scenario_query.order_by(UserScenario.id.desc()).limit(15).all()
    past_scenarios = [row.scenario_text for row in saved_rows]

    # 4. VKE hesapla ve tüm bağlamı Gemini AI'a gönder
    boy_metre = user_data.boy / 100.0
    vke = round(user_data.kilo / (boy_metre ** 2), 2)

    oneri_metni = await generate_ai_recommendation(
        user_data=user_data,
        resolved_location=weather["resolved_city"],
        temp=weather["temp"],
        feels_like=weather["feels_like"],
        wind_speed=weather["wind_speed"],
        weather_status=weather["weather_status"],
        vke=vke,
        past_scenarios=past_scenarios,
    )

    return RecommendationResponse(
        sehir=weather["resolved_city"],
        sicaklik=weather["temp"],
        hissedilen_sicaklik=weather["feels_like"],
        ruzgar_hizi=weather["wind_speed"],
        wmo_kodu=weather["wmo_code"],
        hava_durumu_durumu=weather["weather_status"],
        vke=vke,
        kullanilan_senaryo_sayisi=len(past_scenarios),
        oneri=oneri_metni,
    )


# ==========================================
# 4. HIZLI HAVA DURUMU ARAMA (YAPAY ZEKASIZ - TOKEN TASARRUFLU)
# ==========================================
@app.get(
    "/weather/current",
    response_model=CurrentWeatherResponse,
    tags=["Hızlı Hava Durumu & Seyahat Modu"],
)
async def get_current_weather_quick(
    sehir: str = "İstanbul",
    ilce: Optional[str] = "",
    lat: Optional[float] = None,
    lon: Optional[float] = None,
):
    """
    Gemini AI'ı ÇAĞIRMADAN sadece mevcut fetch_weather_data fonksiyonunu kullanarak
    belirtilen İl/İlçe veya koordinatın anlık hava durumunu (sıcaklık, hissedilen,
    rüzgar hızı, WMO kodu ve hava olayı) hızlıca döner.
    """
    weather = await fetch_weather_data(sehir=sehir, ilce=ilce, lat=lat, lon=lon)
    return CurrentWeatherResponse(
        sehir=weather["resolved_city"],
        sicaklik=weather["temp"],
        hissedilen_sicaklik=weather["feels_like"],
        ruzgar_hizi=weather["wind_speed"],
        wmo_kodu=weather["wmo_code"],
        hava_durumu_durumu=weather["weather_status"],
    )


@app.get(
    "/weather/hourly-alert",
    response_model=HourlyAlertResponse,
    tags=["Hızlı Hava Durumu & Seyahat Modu"],
)
async def check_hourly_weather_shift(
    sehir: str = "İstanbul",
    ilce: Optional[str] = "",
):
    """
    Kullanıcının şehrindeki önümüzdeki 12 saatlik (hourly) hava tahminini inceler.
    Gün içinde sıcaklık 8°C'den fazla oynayacaksa veya aniden Yağmur/Kar/Dolu/Fırtına
    başlayacaksa uyarı üretir (Flutter Workmanager görevi tarafından kullanılır).
    """
    transport = httpx.AsyncHTTPTransport(local_address="0.0.0.0")
    async with httpx.AsyncClient(transport=transport, timeout=10.0) as client:
        geo_res = await client.get(
            "https://geocoding-api.open-meteo.com/v1/search",
            params={"name": ilce.strip() or sehir.strip(), "count": 1, "language": "tr", "format": "json"},
        )
        results = geo_res.json().get("results") or []
        if not results:
            raise HTTPException(status_code=404, detail="Şehir koordinatı bulunamadı.")
        lat_val = results[0]["latitude"]
        lon_val = results[0]["longitude"]
        resolved_name = results[0].get("name") or sehir

        meteo_res = await client.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": lat_val,
                "longitude": lon_val,
                "hourly": "temperature_2m,weather_code,wind_speed_10m",
                "forecast_hours": 12,
                "timezone": "auto",
            },
        )
        hourly = meteo_res.json().get("hourly") or {}
        temps = [float(t) for t in (hourly.get("temperature_2m") or [15.0])]
        codes = [int(c) for c in (hourly.get("weather_code") or [0])]
        winds = [float(w) for w in (hourly.get("wind_speed_10m") or [5.0])]

        min_t = round(min(temps), 1)
        max_t = round(max(temps), 1)
        diff = round(max_t - min_t, 1)

        statuses = [
            map_wmo_weather_code(c, t, w) for c, t, w in zip(codes, temps, winds)
        ]
        initial_status = statuses[0] if statuses else "Güneşli"
        severe_events = [
            s for s in statuses[1:] if s in ("Yağmurlu", "Karlı", "Dolu", "Rüzgarlı") and s != initial_status
        ]
        abrupt_event = severe_events[0] if severe_events else None

        has_alert = diff >= 8.0 or abrupt_event is not None
        if has_alert:
            reasons = []
            if diff >= 8.0:
                reasons.append(f"sıcaklık {min_t}°C ile {max_t}°C arasında ({diff}°C fark) değişecek")
            if abrupt_event:
                reasons.append(f"hava aniden '{abrupt_event}' durumuna dönecek")
            msg = f"Dikkat! Bugün {resolved_name} konumunda {' ve '.join(reasons)}. Yanına koruyucu ek katman almayı unutma!"
        else:
            msg = f"{resolved_name} için önümüzdeki saatlerde ani bir hava değişimi beklenmiyor."

        return HourlyAlertResponse(
            sehir=resolved_name,
            uyari_var_mi=has_alert,
            sicaklik_farki=diff,
            min_sicaklik=min_t,
            max_sicaklik=max_t,
            ani_hava_olayi=abrupt_event,
            bildirim_basligi=f"OptiWear Ani Hava Uyarısı • {resolved_name}",
            bildirim_mesaji=msg,
        )


# ==========================================
# 5. SEYAHAT / BAVUL HAZIRLAMA MODU (POST /recommendation/travel)
# ==========================================
@app.post(
    "/recommendation/travel",
    response_model=TravelRecommendationResponse,
    tags=["Hızlı Hava Durumu & Seyahat Modu"],
)
async def create_travel_packing_recommendation(
    payload: TravelRecommendationRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_user),
):
    """
    Hedef şehir ve başlangıç-bitiş tarihleri için Open-Meteo daily parametreleriyle
    çok günlük hava durumu verisini çeker ve Gemini AI ile kullanıcının VKE/terleme
    profiline uygun seyahat valizi ve kombin listesi hazırlar.
    """
    rate_limiter.check(request, bucket="travel_recommendation", max_requests=10, window_seconds=60)

    transport = httpx.AsyncHTTPTransport(local_address="0.0.0.0")
    search_query = (payload.hedef_ilce or "").strip() or payload.hedef_sehir.strip()

    async with httpx.AsyncClient(transport=transport, timeout=12.0) as client:
        geo_res = await client.get(
            "https://geocoding-api.open-meteo.com/v1/search",
            params={"name": search_query, "count": 5, "language": "tr", "format": "json"},
        )
        candidates = geo_res.json().get("results") or []
        if not candidates and payload.hedef_ilce:
            geo_res = await client.get(
                "https://geocoding-api.open-meteo.com/v1/search",
                params={"name": payload.hedef_sehir.strip(), "count": 5, "language": "tr", "format": "json"},
            )
            candidates = geo_res.json().get("results") or []

        if not candidates:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"'{payload.hedef_sehir}' için konum koordinatları bulunamadı.",
            )

        best = candidates[0]
        lat_val = best["latitude"]
        lon_val = best["longitude"]
        resolved_city = (
            f"{payload.hedef_sehir.strip()}, {payload.hedef_ilce.strip()}"
            if payload.hedef_ilce and payload.hedef_ilce.strip()
            else (best.get("name") or payload.hedef_sehir.strip())
        )

        # Open-Meteo Daily API çağrısı (Tarih aralığı destekli, aralık dışıysa 7 günlük tahmin)
        meteo_params = {
            "latitude": lat_val,
            "longitude": lon_val,
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,wind_speed_10m_max",
            "timezone": "auto",
            "start_date": payload.baslangic_tarihi.strip(),
            "end_date": payload.bitis_tarihi.strip(),
        }
        meteo_res = await client.get("https://api.open-meteo.com/v1/forecast", params=meteo_params)
        if meteo_res.status_code != 200:
            # Eğer seçilen tarih Open-Meteo 16 günlük penceresi dışındaysa 5 günlük tahmine düş
            fallback_params = {
                "latitude": lat_val,
                "longitude": lon_val,
                "daily": "weather_code,temperature_2m_max,temperature_2m_min,wind_speed_10m_max",
                "timezone": "auto",
                "forecast_days": 5,
            }
            meteo_res = await client.get("https://api.open-meteo.com/v1/forecast", params=fallback_params)

        daily = meteo_res.json().get("daily") or {}
        dates = daily.get("time") or []
        max_temps = daily.get("temperature_2m_max") or []
        min_temps = daily.get("temperature_2m_min") or []
        winds = daily.get("wind_speed_10m_max") or []
        codes = daily.get("weather_code") or []

        day_forecasts: List[TravelDayForecast] = []
        for idx in range(min(len(dates), 10)):
            d_str = str(dates[idx])
            t_max = round(float(max_temps[idx]), 1)
            t_min = round(float(min_temps[idx]), 1)
            w_max = round(float(winds[idx]), 1)
            c_val = int(codes[idx])
            status_label = map_wmo_weather_code(c_val, (t_max + t_min) / 2.0, w_max)
            day_forecasts.append(
                TravelDayForecast(
                    tarih=d_str,
                    min_sicaklik=t_min,
                    max_sicaklik=t_max,
                    ruzgar_hizi=w_max,
                    wmo_kodu=c_val,
                    hava_durumu_durumu=status_label,
                )
            )

    boy_m = payload.boy / 100.0
    vke = round(payload.kilo / (boy_m ** 2), 2)

    uid = current_user.id if current_user is not None else None
    scenario_q = db.query(UserScenario)
    if uid is not None:
        scenario_q = scenario_q.filter(UserScenario.user_id == uid)
    else:
        scenario_q = scenario_q.filter(UserScenario.user_id.is_(None))
    past_scenarios = [r.scenario_text for r in scenario_q.order_by(UserScenario.id.desc()).limit(10).all()]

    days_summary = "\n".join(
        f"- {d.tarih}: En düşük {d.min_sicaklik}°C, En yüksek {d.max_sicaklik}°C, "
        f"Rüzgar: {d.ruzgar_hizi} km/s, Hava Olayı: {d.hava_durumu_durumu}"
        for d in day_forecasts
    )
    scenarios_summary = (
        "\n".join(f"- {s}" for s in past_scenarios)
        if past_scenarios
        else "- Kayıtlı geçmiş senaryo bulunmuyor."
    )

    travel_prompt = (
        f"Kullanıcı {payload.baslangic_tarihi} ile {payload.bitis_tarihi} tarihleri arasında "
        f"'{resolved_city}' konumuna seyahat edecek.\n"
        f"Fiziksel Profili: Boy {payload.boy} cm, Kilo {payload.kilo} kg, VKE: {vke}, "
        f"Hareket edince çabuk terleme eğilimi: {payload.terleme_egilimi}.\n"
        f"Geçmiş Termal Deneyimleri:\n{scenarios_summary}\n\n"
        f"Seyahat Günlerinin Hava Tahmini:\n{days_summary}\n\n"
        "Görev: Bu kişinin profiline, VKE değerine ve gideceği şehirdeki günlük hava/rüzgar/yağış "
        "durumuna uygun olarak pratik bir seyahat valizi (bavul) hazırlama listesi ve günlere göre "
        "katmanlı kombin stratejisi hazırla. Yanıtını akıcı ve net Türkçe olarak 4-6 cümlede sun."
    )

    dummy_req = RecommendationRequest(
        sehir=resolved_city,
        ilce="",
        boy=payload.boy,
        kilo=payload.kilo,
        terleme_egilimi=payload.terleme_egilimi,
        gecmis_senaryolar=[travel_prompt],
    )
    avg_temp = (
        round(sum((d.max_sicaklik + d.min_sicaklik) / 2.0 for d in day_forecasts) / len(day_forecasts), 1)
        if day_forecasts
        else 15.0
    )
    max_wind = max((d.ruzgar_hizi for d in day_forecasts), default=10.0)
    primary_status = day_forecasts[0].hava_durumu_durumu if day_forecasts else "Güneşli"

    valiz_metni = await generate_ai_recommendation(
        user_data=dummy_req,
        resolved_location=f"{resolved_city} ({len(day_forecasts)} Günlük Seyahat Valizi)",
        temp=avg_temp,
        feels_like=avg_temp,
        wind_speed=max_wind,
        weather_status=primary_status,
        vke=vke,
        past_scenarios=[travel_prompt],
    )

    return TravelRecommendationResponse(
        hedef_sehir=resolved_city,
        baslangic_tarihi=payload.baslangic_tarihi,
        bitis_tarihi=payload.bitis_tarihi,
        gun_sayisi=len(day_forecasts),
        vke=vke,
        gunluk_tahminler=day_forecasts,
        valiz_onerisi=valiz_metni,
    )


@app.get(
    "/notifications/smart-engagement",
    tags=["Günlük Rutin & Mobil Bildirim"],
)
def generate_smart_daytime_engagement_schedule():
    """
    Kamusal / Kurumsal uygulama standartlarında 08:00 - 22:00 (Gündüz/Akşam)
    penceresinde rastgele (jittered) 3 bildirim saati ve mesajı üretir.
    Gece 22:00 - Sabah 08:00 (Sessiz Saatler) aralığında bildirim üretilmez.
    """
    import random

    pool = [
        {
            "baslik": "🌤️ Öğle Saatleri Yaklaşıyor!",
            "mesaj": "Sıcaklık gün içi zirvesine doğru çıkıyor. Kalın giyindiysen terlememek için dış katmanını hafifletmeyi unutma!",
        },
        {
            "baslik": "🧥 Akşamüstü Serinliği Başlıyor",
            "mesaj": "Güneş etkisini kaybederken hissedilen sıcaklık düşüyor. Dışarıdaysan rüzgarlığını veya üst katmanını hazır tut.",
        },
        {
            "baslik": "🧠 Bugün Termal Konforun Nasıldı?",
            "mesaj": "Bugünkü kıyafetlerinle terledin mi yoksa üşüdün mü? OptiWear hafızana 1 cümle ekle, yarın çok daha nokta atışı önerelim!",
        },
        {
            "baslik": "✨ Yarının Kombinini Şimdiden Planla",
            "mesaj": "Sabah dolap karşısında vakit kaybetme! Yarının hava olayına ve VKE profiline uygun kombinin OptiWear'da hazır.",
        },
        {
            "baslik": "🌬️ Rüzgar ve Hissedilen Sıcaklık Kontrolü",
            "mesaj": "Termometreye aldanma! Rüzgar hızı hissedilen sıcaklığı değiştirebilir, dışarı çıkmadan önce OptiWear'a göz at.",
        },
    ]
    selected = random.sample(pool, 3)
    slots = [
        ("Kuşluk / Öğle Öncesi Dilimi (09:00-12:59)", random.randint(9, 12), random.randint(0, 59)),
        ("Öğleden Sonra / Çıkış Dilimi (14:00-17:59)", random.randint(14, 17), random.randint(0, 59)),
        ("Akşam / Yarın Hazırlık Dilimi (19:00-21:45)", random.randint(19, 21), random.randint(0, 45)),
    ]

    schedule = []
    for idx, (label, hh, mm) in enumerate(slots):
        schedule.append(
            {
                "dilim": label,
                "rastgele_saat": f"{hh:02d}:{mm:02d}",
                "baslik": selected[idx]["baslik"],
                "mesaj": selected[idx]["mesaj"],
                "ses": "routine_alert.mp3",
            }
        )

    return {
        "aktif_pencere": "08:00 - 22:00",
        "sessiz_saatler": "22:00 - 08:00 (Gece Rahatsız Etmeme Modu Aktif)",
        "planlanan_bildirimler": schedule,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="127.0.0.1", port=8001, reload=True)
