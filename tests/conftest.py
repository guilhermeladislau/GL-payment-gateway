import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from src.database import Base, get_db

# criar o engine de teste ANTES de importar a app
# isso evita que o startup tente conectar ao postgres
TEST_DB_URL = "sqlite://"

test_engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestSession = sessionmaker(test_engine, expire_on_commit=False)


def override_get_db():
    db = TestSession()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


# Precisa importar DEPOIS de configurar o override
# e sobrescrever o engine no modulo database pra o startup funcionar
import src.database as db_module
db_module.engine = test_engine

from src.main import app  # noqa: E402

app.dependency_overrides[get_db] = override_get_db


@pytest.fixture(autouse=True)
def setup_db():
    Base.metadata.create_all(bind=test_engine)
    yield
    Base.metadata.drop_all(bind=test_engine)


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c
