import uuid
import os
import socket
from datetime import datetime

from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import Response
from sqlalchemy.orm import Session
from sqlalchemy import select, func, text
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, generate_latest

from src.database import get_db
from src.models import Transaction

router = APIRouter()

# --- metricas ---

http_requests_total = Counter(
    "gateway_http_requests_total",
    "Total de requests HTTP",
    ["method", "route", "status_code"],
)
http_request_duration = Histogram(
    "gateway_http_request_duration_seconds",
    "Duracao dos requests",
    ["method", "route"],
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 5.0),
)
transactions_counter = Counter(
    "gateway_transactions_total",
    "Total de transacoes",
    ["card_type", "status"],
)


class TransactionCreate(BaseModel):
    amount: float
    card_type: str
    card_number_hash: str
    status: str = "pending"


class TransactionOut(BaseModel):
    id: uuid.UUID
    amount: float
    card_type: str
    card_number_hash: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


# health checks

@router.get("/health")
def health():
    instance = os.getenv("INSTANCE_NAME", socket.gethostname())
    return {"status": "ok", "instance": instance}


@router.get("/health/live")
def liveness():
    instance = os.getenv("INSTANCE_NAME", socket.gethostname())
    return {"status": "ok", "instance": instance}


@router.get("/health/ready")
def readiness(db: Session = Depends(get_db)):
    instance = os.getenv("INSTANCE_NAME", socket.gethostname())
    environment = os.getenv("ENVIRONMENT", "development")

    try:
        db.execute(text("SELECT 1"))
        db_status = {"status": "ok", "details": "Conexão ativa"}
    except Exception as e:
        print(f"Erro no health check do banco: {e}")
        db_status = {"status": "error", "details": str(e)}

    if db_status["status"] == "ok":
        overall = "ok"
    else:
        overall = "degraded"

    return {
        "status": overall,
        "instance": instance,
        "environment": environment,
        "checks": {"database": db_status},
    }


# transações

@router.post("/transactions", status_code=201)
def create_transaction(data: TransactionCreate, db: Session = Depends(get_db)):
    if data.amount <= 0:
        raise HTTPException(status_code=422, detail="Amount deve ser maior que 0")

    if data.card_type not in ["credit", "debit"]:
        raise HTTPException(status_code=422, detail="card_type deve ser 'credit' ou 'debit'")

    if data.status not in ["approved", "declined", "pending"]:
        raise HTTPException(status_code=422, detail="status invalido")

    if not data.card_number_hash:
        raise HTTPException(status_code=422, detail="card_number_hash nao pode ser vazio")

    print(f"Criando transação: amount={data.amount}, card_type={data.card_type}")

    # criar no banco
    transaction = Transaction(
        amount=data.amount,
        card_type=data.card_type,
        card_number_hash=data.card_number_hash,
        status=data.status,
    )
    db.add(transaction)
    db.flush()
    db.refresh(transaction)

    # incrementar metrica
    transactions_counter.labels(card_type=data.card_type, status=data.status).inc()

    print(f"Transação criada: id={transaction.id}")

    return TransactionOut.model_validate(transaction)


@router.get("/transactions")
def list_transactions(
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=100),
    db: Session = Depends(get_db),
):
    # buscar transacoes
    query = select(Transaction).offset(skip).limit(limit).order_by(Transaction.created_at.desc())
    result = db.execute(query)
    transactions = result.scalars().all()

    # contar total
    count_query = select(func.count()).select_from(Transaction)
    count_result = db.execute(count_query)
    total = count_result.scalar_one()

    return {
        "data": [TransactionOut.model_validate(t) for t in transactions],
        "total": total,
    }


@router.get("/transactions/{transaction_id}")
def get_transaction(transaction_id: uuid.UUID, db: Session = Depends(get_db)):
    query = select(Transaction).where(Transaction.id == transaction_id)
    result = db.execute(query)
    transaction = result.scalar_one_or_none()

    if transaction is None:
        raise HTTPException(status_code=404, detail="Transação não encontrada")

    return TransactionOut.model_validate(transaction)


@router.get("/metrics")
def get_metrics():
    return Response(
        content=generate_latest(),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )
