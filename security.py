import base64
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import time
import uuid
from collections import defaultdict, deque
from typing import Any, Deque, Dict, Optional, Tuple

from dotenv import load_dotenv
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from database import User, get_db

load_dotenv()

# ==========================================
# 1. Güvenlik Yapılandırması & Anahtarlar
# ==========================================
JWT_SECRET_KEY = os.getenv(
    "JWT_SECRET_KEY",
    "optiwear-default-dev-secret-change-in-production-256bit-key",
).strip()
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("JWT_ACCESS_TOKEN_EXPIRE_MINUTES", "15"))
REFRESH_TOKEN_EXPIRE_DAYS = int(os.getenv("JWT_REFRESH_TOKEN_EXPIRE_DAYS", "7"))

_RAW_PII_KEY = os.getenv(
    "PII_ENCRYPTION_KEY",
    "optiwear-pii-encryption-key-change-in-prod-32b",
).strip()
PII_DERIVED_KEY = hashlib.sha256(_RAW_PII_KEY.encode("utf-8")).digest()
FERNET_KEY_B64 = base64.urlsafe_b64encode(PII_DERIVED_KEY)

# İsteğe bağlı argon2-cffi ve cryptography paketlerini yükle
try:
    from argon2 import PasswordHasher
    from argon2.exceptions import VerifyMismatchError

    _argon2_hasher = PasswordHasher(
        time_cost=3, memory_cost=65536, parallelism=4, hash_len=32, salt_len=16
    )
    HAS_ARGON2 = True
except ImportError:
    _argon2_hasher = None
    HAS_ARGON2 = False

try:
    from cryptography.fernet import Fernet

    _fernet = Fernet(FERNET_KEY_B64)
    HAS_FERNET = True
except ImportError:
    _fernet = None
    HAS_FERNET = False


# ==========================================
# 2. PII Log Maskeleme Filtresi (Sızıntı Önleme)
# ==========================================
class PIILogFilter(logging.Filter):
    """
    Log kayıtlarında şifre, telefon numarası ve JWT token gibi hassas verilerin
    açık metin olarak görünmesini engeller.
    """

    _PATTERNS = [
        (re.compile(r'("password"\s*:\s*)"[^"]*"', re.IGNORECASE), r'\1"***REDACTED***"'),
        (re.compile(r'("phone_number"\s*:\s*)"[^"]*"', re.IGNORECASE), r'\1"***REDACTED***"'),
        (re.compile(r"(Bearer\s+)[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+"), r"\1***REDACTED_JWT***"),
        (re.compile(r"(\+?90|0)?5\d{2}[\s\-]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}"), "***REDACTED_PHONE***"),
    ]

    def filter(self, record: logging.LogRecord) -> bool:
        msg = record.getMessage()
        for pattern, replacement in self._PATTERNS:
            msg = pattern.sub(replacement, msg)
        record.msg = msg
        record.args = ()
        return True


logger = logging.getLogger("optiwear.security")
if not logger.handlers:
    handler = logging.StreamHandler()
    handler.addFilter(PIILogFilter())
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)


# ==========================================
# 3. Şifre Hashleme (Argon2id / Bellek-Zorlu Scrypt)
# ==========================================
def hash_password(plain_password: str) -> str:
    """
    Kullanıcı şifresini Argon2id (veya Python yerleşik bellek-zorlu scrypt KDF)
    kullanarak güvenli ve tuzlanmış (salted) biçimde özetler.
    """
    if HAS_ARGON2 and _argon2_hasher is not None:
        return _argon2_hasher.hash(plain_password)

    salt = secrets.token_bytes(16)
    derived = hashlib.scrypt(
        plain_password.encode("utf-8"),
        salt=salt,
        n=16384,
        r=8,
        p=1,
        dklen=32,
    )
    return f"scrypt$16384$8$1${base64.b64encode(salt).decode()}${base64.b64encode(derived).decode()}"


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Zamanlama saldırılarına (Timing Attack) dayanıklı sabit zamanlı şifre doğrulaması.
    """
    if not plain_password or not hashed_password:
        return False

    try:
        if hashed_password.startswith("$argon2") and HAS_ARGON2 and _argon2_hasher is not None:
            return _argon2_hasher.verify(hashed_password, plain_password)

        if hashed_password.startswith("scrypt$"):
            parts = hashed_password.split("$")
            if len(parts) != 6:
                return False
            _, n_str, r_str, p_str, salt_b64, expected_b64 = parts
            salt = base64.b64decode(salt_b64.encode())
            expected = base64.b64decode(expected_b64.encode())
            candidate = hashlib.scrypt(
                plain_password.encode("utf-8"),
                salt=salt,
                n=int(n_str),
                r=int(r_str),
                p=int(p_str),
                dklen=len(expected),
            )
            return secrets.compare_digest(candidate, expected)
    except Exception:
        return False

    return False


# ==========================================
# 4. PII Veri Şifreleme (Encryption at Rest)
# ==========================================
def encrypt_pii(plaintext: str) -> str:
    """
    Telefon numarası gibi hassas PII verilerini veritabanına kaydetmeden önce
    Fernet (AES-128-CBC + HMAC-SHA256) ile şifreler.
    """
    if not plaintext:
        return ""
    raw_bytes = plaintext.strip().encode("utf-8")
    if HAS_FERNET and _fernet is not None:
        return "fernet:" + _fernet.encrypt(raw_bytes).decode("utf-8")

    # Standart kütüphane HMAC-SHA256 + CTR akış şifrelemesi (Fallback)
    nonce = secrets.token_bytes(16)
    keystream = b""
    counter = 0
    while len(keystream) < len(raw_bytes):
        block = hmac.new(
            PII_DERIVED_KEY, nonce + counter.to_bytes(4, "big"), hashlib.sha256
        ).digest()
        keystream += block
        counter += 1
    cipher = bytes(a ^ b for a, b in zip(raw_bytes, keystream[: len(raw_bytes)]))
    mac = hmac.new(PII_DERIVED_KEY, nonce + cipher, hashlib.sha256).digest()
    payload = base64.urlsafe_b64encode(nonce + mac + cipher).decode("utf-8")
    return f"hmac_ctr:{payload}"


def decrypt_pii(ciphertext: str) -> str:
    """Veritabanındaki şifreli PII verisini çözer."""
    if not ciphertext:
        return ""
    try:
        if ciphertext.startswith("fernet:") and HAS_FERNET and _fernet is not None:
            token = ciphertext[len("fernet:") :].encode("utf-8")
            return _fernet.decrypt(token).decode("utf-8")

        if ciphertext.startswith("hmac_ctr:"):
            raw = base64.urlsafe_b64decode(ciphertext[len("hmac_ctr:") :].encode("utf-8"))
            nonce, mac, cipher = raw[:16], raw[16:48], raw[48:]
            expected_mac = hmac.new(PII_DERIVED_KEY, nonce + cipher, hashlib.sha256).digest()
            if not secrets.compare_digest(mac, expected_mac):
                return ""
            keystream = b""
            counter = 0
            while len(keystream) < len(cipher):
                block = hmac.new(
                    PII_DERIVED_KEY, nonce + counter.to_bytes(4, "big"), hashlib.sha256
                ).digest()
                keystream += block
                counter += 1
            plain = bytes(a ^ b for a, b in zip(cipher, keystream[: len(cipher)]))
            return plain.decode("utf-8")
    except Exception:
        return ""
    return ""


def mask_phone_number(phone: str) -> str:
    """Telefon numarasını API yanıtlarında güvenli göstermek için maskeler (Örn: +905******45)."""
    cleaned = re.sub(r"\s+", "", phone or "")
    if len(cleaned) < 6:
        return "***"
    return f"{cleaned[:4]}{'*' * (len(cleaned) - 6)}{cleaned[-2:]}"


# ==========================================
# 5. JWT (Access Token & Refresh Token) Motoru
# ==========================================
def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("utf-8")


def _b64url_decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode((data + padding).encode("utf-8"))


def _encode_jwt(payload: Dict[str, Any]) -> str:
    header = {"alg": JWT_ALGORITHM, "typ": "JWT"}
    header_b64 = _b64url_encode(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    payload_b64 = _b64url_encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{header_b64}.{payload_b64}".encode("utf-8")
    signature = hmac.new(JWT_SECRET_KEY.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{header_b64}.{payload_b64}.{_b64url_encode(signature)}"


def _decode_jwt(token: str) -> Dict[str, Any]:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Geçersiz JWT formatı.")
    header_b64, payload_b64, signature_b64 = parts
    signing_input = f"{header_b64}.{payload_b64}".encode("utf-8")
    expected_sig = hmac.new(JWT_SECRET_KEY.encode("utf-8"), signing_input, hashlib.sha256).digest()
    actual_sig = _b64url_decode(signature_b64)
    if not secrets.compare_digest(expected_sig, actual_sig):
        raise ValueError("JWT imzası doğrulanamadı.")
    payload = json.loads(_b64url_decode(payload_b64).decode("utf-8"))
    now = int(time.time())
    if payload.get("exp") and int(payload["exp"]) < now:
        raise ValueError("Oturum süresi (JWT) dolmuş.")
    return payload


def create_access_token(user_id: str, token_version: int = 1) -> str:
    now = int(time.time())
    payload = {
        "sub": user_id,
        "tv": token_version,
        "type": "access",
        "jti": str(uuid.uuid4()),
        "iat": now,
        "exp": now + (ACCESS_TOKEN_EXPIRE_MINUTES * 60),
    }
    return _encode_jwt(payload)


def create_refresh_token(user_id: str, token_version: int = 1) -> str:
    now = int(time.time())
    payload = {
        "sub": user_id,
        "tv": token_version,
        "type": "refresh",
        "jti": str(uuid.uuid4()),
        "iat": now,
        "exp": now + (REFRESH_TOKEN_EXPIRE_DAYS * 86400),
    }
    return _encode_jwt(payload)


def decode_token(token: str, expected_type: str = "access") -> Dict[str, Any]:
    try:
        payload = _decode_jwt(token)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        )
    if payload.get("type") != expected_type:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Geçersiz token tipi. Beklenen: {expected_type}",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return payload


# ==========================================
# 6. FastAPI Kimlik Doğrulama Bağımlılıkları (Dependencies)
# ==========================================
bearer_scheme = HTTPBearer(auto_error=False)


def get_current_active_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """
    Korumalı uç noktalarda JWT Access Token'ı doğrular, kullanıcının
    aktif (is_active=True) ve token_version'ının güncel olduğunu kontrol eder.
    """
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Kimlik doğrulama bilgisi (Bearer Token) eksik.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_token(credentials.credentials, expected_type="access")
    user_id = payload.get("sub")
    token_version = payload.get("tv", 1)

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Kullanıcı bulunamadı.",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Hesabınız dondurulmuş veya silinmiş durumda.",
        )

    if user.token_version != token_version:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Oturumunuz sonlandırılmış. Lütfen tekrar giriş yapın.",
        )

    return user


def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> Optional[User]:
    """
    Hem giriş yapmış mobil kullanıcıları hem de üyeliksiz web kullanıcılarını
    destekleyen uç noktalar için opsiyonel kullanıcı çözümleyici.
    """
    if credentials is None or not credentials.credentials:
        return None
    try:
        return get_current_active_user(credentials=credentials, db=db)
    except HTTPException:
        return None


# ==========================================
# 7. Firewall & Brute-Force Koruması (Rate Limiter)
# ==========================================
class SlidingWindowRateLimiter:
    """
    IP + Uç Nokta bazlı Kayan Pencere (Sliding Window) Hız Sınırlandırıcı.
    SlowAPI kurulu olsun veya olmasın, özellikle /auth/login ve /auth/register
    üzerinde brute-force saldırılarını kesin olarak engeller.
    """

    def __init__(self) -> None:
        self._hits: Dict[str, Deque[float]] = defaultdict(deque)

    @staticmethod
    def _get_client_ip(request: Request) -> str:
        forwarded = request.headers.get("X-Forwarded-For")
        if forwarded:
            return forwarded.split(",")[0].strip()
        if request.client and request.client.host:
            return request.client.host
        return "127.0.0.1"

    def check(self, request: Request, bucket: str, max_requests: int, window_seconds: int) -> None:
        ip = self._get_client_ip(request)
        key = f"{bucket}:{ip}"
        now = time.time()
        q = self._hits[key]

        while q and (now - q[0]) > window_seconds:
            q.popleft()

        if len(q) >= max_requests:
            retry_after = int(window_seconds - (now - q[0])) + 1
            logger.warning(f"[FIREWALL] Rate limit aşıldı -> Hedef: {bucket} | IP: {ip}")
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    f"Çok fazla deneme yaptınız (Maksimum {max_requests} istek / {window_seconds} sn). "
                    f"Lütfen {retry_after} saniye sonra tekrar deneyin."
                ),
                headers={"Retry-After": str(retry_after)},
            )

        q.append(now)


rate_limiter = SlidingWindowRateLimiter()
