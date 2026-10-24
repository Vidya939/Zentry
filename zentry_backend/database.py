
import os
from datetime import datetime, timedelta, timezone

from dotenv import load_dotenv
from sqlalchemy import URL, create_engine, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker

load_dotenv()

IST = timezone(timedelta(hours=5, minutes=30))


def ist_now() -> datetime:
    """Return the current IST time as a timezone-naive datetime for MySQL DATETIME."""
    return datetime.now(IST).replace(tzinfo=None)

def ist_iso(value: datetime | None) -> str | None:
    """Serialize an IST wall-clock datetime with an explicit +05:30 offset."""
    if value is None:
        return None

    if value.tzinfo is None:
        value = value.replace(tzinfo=IST)
    else:
        value = value.astimezone(IST)

    return value.isoformat(timespec="seconds")

database_url = URL.create(
    drivername="mysql+pymysql",
    username=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
    host=os.getenv("DB_HOST", "127.0.0.1"),
    port=int(os.getenv("DB_PORT", "3306")),
    database=os.getenv("DB_NAME", "zentry_db"),
    query={"charset": "utf8mb4"},
)

engine = create_engine(
    database_url,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    pool_recycle=1800,
)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
)


class Base(DeclarativeBase):
    pass


def test_database_connection():
    with engine.connect() as connection:
        result = connection.execute(text("SELECT DATABASE()"))
        database_name = result.scalar_one()
        return database_name
