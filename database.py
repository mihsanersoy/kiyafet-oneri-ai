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
    phone_number_enc = Column(String(500), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
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
        if "user_scenarios" in inspector.get_table_names():
            cols = [c["name"] for c in inspector.get_columns("user_scenarios")]
            if "user_id" not in cols:
                with engine.begin() as conn:
                    conn.execute(
                        text("ALTER TABLE user_scenarios ADD COLUMN user_id VARCHAR(36)")
                    )
                print("[Veritabanı] user_scenarios tablosuna user_id sütunu eklendi.")
    except Exception as mig_exc:
        print(f"[Veritabanı] Şema kontrol uyarısı: {mig_exc}")


def get_db():
    """FastAPI Dependency Injection için veritabanı oturumu."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
