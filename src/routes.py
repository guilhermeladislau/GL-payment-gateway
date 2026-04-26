import uuid
import os
import socket
from datetime import datetime

from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, text
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, generate_latest

from src.database import get_db
from src.models import Transaction

router = APIRouter()

# metricas prometheus
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


# pydantic models
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


# ===================== HEALTH =====================

@router.get("/health")
async def health():
    instance = os.getenv("INSTANCE_NAME", socket.gethostname())
    return {"status": "ok", "instance": instance}


@router.get("/health/live")
async def liveness():
    instance = os.getenv("INSTANCE_NAME", socket.gethostname())
    return {"status": "ok", "instance": instance}


@router.get("/health/ready")
async def readiness(db: AsyncSession = Depends(get_db)):
    instance = os.getenv("INSTANCE_NAME", socket.gethostname())
    environment = os.getenv("ENVIRONMENT", "development")

    # checar banco
    try:
        await db.execute(text("SELECT 1"))
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


# ===================== TRANSAÇÕES =====================

@router.post("/transactions", status_code=201)
async def create_transaction(data: TransactionCreate, db: AsyncSession = Depends(get_db)):
    # validar dados manualmente
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
    await db.flush()
    await db.refresh(transaction)

    # incrementar metrica
    transactions_counter.labels(card_type=data.card_type, status=data.status).inc()

    print(f"Transação criada: id={transaction.id}")

    return TransactionOut.model_validate(transaction)


@router.get("/transactions")
async def list_transactions(
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    # buscar transacoes
    query = select(Transaction).offset(skip).limit(limit).order_by(Transaction.created_at.desc())
    result = await db.execute(query)
    transactions = result.scalars().all()

    # contar total
    count_query = select(func.count()).select_from(Transaction)
    count_result = await db.execute(count_query)
    total = count_result.scalar_one()

    return {
        "data": [TransactionOut.model_validate(t) for t in transactions],
        "total": total,
    }


@router.get("/transactions/{transaction_id}")
async def get_transaction(transaction_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    query = select(Transaction).where(Transaction.id == transaction_id)
    result = await db.execute(query)
    transaction = result.scalar_one_or_none()

    if transaction is None:
        raise HTTPException(status_code=404, detail="Transação não encontrada")

    return TransactionOut.model_validate(transaction)


# ===================== METRICAS =====================

@router.get("/metrics")
async def get_metrics():
    output = generate_latest()
    return Response(content=output, media_type="text/plain; version=0.0.4; charset=utf-8")
