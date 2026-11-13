import os
from datetime import datetime
from dotenv import load_dotenv
from sqlalchemy import Column, DateTime, Integer, String, create_engine, text
from sqlalchemy.orm import declarative_base, sessionmaker

load_dotenv()

# Proje kök dizininde mutlak (absolute) scenarios.db dosya yolu
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SQLITE_DB_PATH = os.path.join(BASE_DIR, "scenarios.db")
FALLBACK_SQLITE_URL = f"sqlite:///{SQLITE_DB_PATH}"

# İsteğe bağlı PostgreSQL bağlantısı (.env içinde DATABASE_URL tanımlıysa)
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()

Base = declarative_base()


class UserScenario(Base):
    __tablename__ = "user_scenarios"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    scenario_text = Column(String(500), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


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
    """Tabloları scenarios.db (veya PostgreSQL) üzerinde oluşturur."""
    Base.metadata.create_all(bind=engine)


def get_db():
    """FastAPI Dependency Injection için veritabanı oturumu."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
