import os
import uuid
from datetime import datetime
from dotenv import load_dotenv
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    create_engine,
    inspect,
    text,
)
from sqlalchemy.orm import declarative_base, relationship, sessionmaker

load_dotenv()

# Proje kök dizininde mutlak (absolute) scenarios.db dosya yolu
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SQLITE_DB_PATH = os.path.join(BASE_DIR, "scenarios.db")
FALLBACK_SQLITE_URL = f"sqlite:///{SQLITE_DB_PATH}"

# İsteğe bağlı PostgreSQL bağlantısı (.env içinde DATABASE_URL tanımlıysa)
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()

Base = declarative_base()


class User(Base):
    """
    OptiWear Güvenli Kullanıcı Tablosu (users)
    - id: Tahmin edilemez UUIDv4 (IDOR saldırılarına karşı)
    - email: Benzersiz ve indeksli
    - hashed_password: Argon2id / Scrypt ile tuzlanmış özet
    - phone_number_enc: Veritabanı sızıntılarına karşı Fernet/AES ile şifrelenmiş telefon
    - is_active: Soft-delete / hesap dondurma mekanizması
    - token_version: Hesap dondurulduğunda tüm JWT'leri anında iptal etmek için sayaç
    """

    __tablename__ = "users"

    id = Column(
        String(36),
        primary_key=True,
        index=True,
        default=lambda: str(uuid.uuid4()),
    )
    email = Column(String(255), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    full_name = Column(String(120), nullable=False)
    # Veritabanında Fernet/AES ile şifrelenmiş olarak saklanır (Encryption at Rest)
    phone_number = Column(String(500), nullable=False)
    avatar_base64 = Column(String, nullable=True)
    default_location_name = Column(String(150), default="İstanbul", nullable=True)
    default_admin1 = Column(String(150), default="İstanbul", nullable=True)
    default_country = Column(String(100), default="Türkiye", nullable=True)
    default_lat = Column(Float, default=41.0082, nullable=True)
    default_lon = Column(Float, default=28.9784, nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    is_verified = Column(Boolean, default=False, nullable=False)
    token_version = Column(Integer, default=1, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    routine = relationship(
        "UserRoutine",
        back_populates="user",
        uselist=False,
        cascade="all, delete-orphan",
    )
    scenarios = relationship(
        "UserScenario",
        back_populates="user",
        cascade="all, delete-orphan",
    )
    custom_routines = relationship(
        "UserCustomRoutine",
        back_populates="user",
        cascade="all, delete-orphan",
    )
    otps = relationship(
        "EmailOTP",
        back_populates="user",
        cascade="all, delete-orphan",
    )

    def __repr__(self) -> str:
        # PII Koruması: Loglarda telefon veya şifre özeti asla gösterilmez
        return f"<User id={self.id} active={self.is_active}>"


class UserRoutine(Base):
    """
    Kullanıcının Günlük Uyanma Saati ve Rutin Bildirim Tercihleri (user_routines)
    Flutter mobil uygulaması üzerinden sabah kombin bildirimi için kullanılır.
    """

    __tablename__ = "user_routines"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(
        String(36),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        index=True,
        nullable=False,
    )
    wake_up_time = Column(String(5), default="07:30", nullable=False)  # HH:MM
    sehir = Column(String(100), default="İstanbul", nullable=False)
    ilce = Column(String(100), nullable=True)
    lat = Column(Float, nullable=True)
    lon = Column(Float, nullable=True)
    boy = Column(Float, default=175.0, nullable=False)
    kilo = Column(Float, default=75.0, nullable=False)
    terleme_egilimi = Column(String(20), default="Hayır", nullable=False)
    notification_enabled = Column(Boolean, default=True, nullable=False)
    fcm_token = Column(String(500), nullable=True)
    updated_at = Column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )

    user = relationship("User", back_populates="routine")


class UserCustomRoutine(Base):
    """
    Kullanıcının Özel Günlük Rutinleri (user_custom_routines)
    Örn: 'Sabah İşe Gidiş' - '08:00' - 'Pzt,Sal,Çar,Per,Cum'
    Rutin saatinden 10 dakika önce yerel/zamanlanmış bildirim tetiklemek için kullanılır.
    """

    __tablename__ = "user_custom_routines"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(
        String(36),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=True,
    )
    routine_title = Column(String(150), nullable=False)
    routine_time = Column(String(5), nullable=False)  # HH:MM
    days_of_week = Column(String(100), default="Pzt,Sal,Çar,Per,Cum,Cmt,Paz", nullable=False)
    lead_minutes = Column(Integer, default=15, nullable=False)
    notification_summary = Column(String(600), nullable=True)
    is_enabled = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="custom_routines")


class EmailOTP(Base):
    """
    6 Haneli E-Posta Doğrulama Kodları Tablosu (email_otps)
    Kullanıcı kayıt olduğunda üretilir ve 15 dakika boyunca geçerlidir.
    """

    __tablename__ = "email_otps"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(
        String(36),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    otp_code = Column(String(6), nullable=False)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="otps")


class UserScenario(Base):
    """
    Kişisel Termal Hafıza Senaryoları (user_scenarios)
    Hem giriş yapmış kullanıcıya (user_id) hem de web misafir oturumuna uyumludur.
    """

    __tablename__ = "user_scenarios"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(
        String(36),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=True,
    )
    scenario_text = Column(String(500), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="scenarios")


def _create_db_engine():
    if DATABASE_URL:
        try:
            pg_engine = create_engine(DATABASE_URL, pool_pre_ping=True)
            with pg_engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            print("[Veritabanı] PostgreSQL bağlantısı aktif.")
            return pg_engine
        except Exception as exc:
            print(
                f"[Veritabanı] PostgreSQL'e bağlanılamadı ({exc}). "
                f"Lokal SQLite ({SQLITE_DB_PATH}) kullanılıyor."
            )

    sqlite_engine = create_engine(
        FALLBACK_SQLITE_URL,
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
    )
    print(f"[Veritabanı] Lokal SQLite aktif -> {SQLITE_DB_PATH}")
    return sqlite_engine


engine = _create_db_engine()
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def init_db():
    """
    Tabloları oluşturur ve mevcut user_scenarios tablosunda user_id sütunu yoksa
    veri kaybı olmadan güvenli şekilde ekler.
    """
    Base.metadata.create_all(bind=engine)
    try:
        inspector = inspect(engine)
        table_names = inspector.get_table_names()
        if "user_scenarios" in table_names:
            cols = [c["name"] for c in inspector.get_columns("user_scenarios")]
            if "user_id" not in cols:
                with engine.begin() as conn:
                    conn.execute(
                        text("ALTER TABLE user_scenarios ADD COLUMN user_id VARCHAR(36)")
                    )
                print("[Veritabanı] user_scenarios tablosuna user_id sütunu eklendi.")
        if "users" in table_names:
            u_cols = [c["name"] for c in inspector.get_columns("users")]
            if "phone_number" not in u_cols:
                with engine.begin() as conn:
                    conn.execute(
                        text("ALTER TABLE users ADD COLUMN phone_number VARCHAR(500) DEFAULT ''")
                    )
                print("[Veritabanı] users tablosuna phone_number sütunu eklendi.")
            if "is_verified" not in u_cols:
                with engine.begin() as conn:
                    conn.execute(
                        text("ALTER TABLE users ADD COLUMN is_verified BOOLEAN DEFAULT 0")
                    )
                print("[Veritabanı] users tablosuna is_verified sütunu eklendi.")
            for col_name, col_def in [
                ("avatar_base64", "TEXT"),
                ("default_location_name", "VARCHAR(150) DEFAULT 'İstanbul'"),
                ("default_admin1", "VARCHAR(150) DEFAULT 'İstanbul'"),
                ("default_country", "VARCHAR(100) DEFAULT 'Türkiye'"),
                ("default_lat", "FLOAT DEFAULT 41.0082"),
                ("default_lon", "FLOAT DEFAULT 28.9784"),
            ]:
                if col_name not in u_cols:
                    with engine.begin() as conn:
                        conn.execute(text(f"ALTER TABLE users ADD COLUMN {col_name} {col_def}"))
                    print(f"[Veritabanı] users tablosuna {col_name} sütunu eklendi.")
            if "phone_number_enc" in u_cols:
                try:
                    with engine.begin() as conn:
                        conn.execute(
                            text("ALTER TABLE users DROP COLUMN phone_number_enc")
                        )
                    print("[Veritabanı] users tablosundaki eski phone_number_enc sütunu kaldırıldı.")
                except Exception:
                    with engine.begin() as conn:
                        conn.execute(text("DROP TABLE IF EXISTS users"))
                    Base.metadata.create_all(bind=engine)
                    print("[Veritabanı] users tablosu yeni şemayla yeniden oluşturuldu.")
        if "user_custom_routines" in table_names:
            cr_cols = [c["name"] for c in inspector.get_columns("user_custom_routines")]
            if "is_enabled" not in cr_cols:
                with engine.begin() as conn:
                    conn.execute(
                        text("ALTER TABLE user_custom_routines ADD COLUMN is_enabled BOOLEAN DEFAULT 1")
                    )
                print("[Veritabanı] user_custom_routines tablosuna is_enabled sütunu eklendi.")
            if "lead_minutes" not in cr_cols:
                with engine.begin() as conn:
                    conn.execute(
                        text("ALTER TABLE user_custom_routines ADD COLUMN lead_minutes INTEGER DEFAULT 15")
                    )
                print("[Veritabanı] user_custom_routines tablosuna lead_minutes sütunu eklendi.")
            if "notification_summary" not in cr_cols:
                with engine.begin() as conn:
                    conn.execute(
                        text("ALTER TABLE user_custom_routines ADD COLUMN notification_summary VARCHAR(600)")
                    )
                print("[Veritabanı] user_custom_routines tablosuna notification_summary sütunu eklendi.")
    except Exception as mig_exc:
        print(f"[Veritabanı] Şema kontrol uyarısı: {mig_exc}")


def get_db():
    """FastAPI Dependency Injection için veritabanı oturumu."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
