import uuid

import pytest
from httpx import AsyncClient


class TestAPI:

    @pytest.mark.asyncio
    async def test_health(self, client: AsyncClient):
        resp = await client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    @pytest.mark.asyncio
    async def test_criar_transacao(self, client: AsyncClient):
        payload = {
            "amount": 150.75,
            "card_type": "credit",
            "card_number_hash": "abc123",
            "status": "approved",
        }
        resp = await client.post("/transactions", json=payload)
        assert resp.status_code == 201
        data = resp.json()
        assert data["amount"] == 150.75
        assert "id" in data

    @pytest.mark.asyncio
    async def test_listar_transacoes(self, client: AsyncClient):
        resp = await client.get("/transactions")
        assert resp.status_code == 200
        assert resp.json()["data"] == []

    @pytest.mark.asyncio
    async def test_buscar_por_id(self, client: AsyncClient):
        # criar primeiro
        payload = {
            "amount": 100.0,
            "card_type": "debit",
            "card_number_hash": "hash123",
            "status": "approved",
        }
        create_resp = await client.post("/transactions", json=payload)
        tx_id = create_resp.json()["id"]

        # buscar
        resp = await client.get(f"/transactions/{tx_id}")
        assert resp.status_code == 200
        assert resp.json()["id"] == tx_id

    @pytest.mark.asyncio
    async def test_transacao_nao_encontrada(self, client: AsyncClient):
        fake_id = str(uuid.uuid4())
        resp = await client.get(f"/transactions/{fake_id}")
        assert resp.status_code == 404

    @pytest.mark.asyncio
    async def test_dados_invalidos(self, client: AsyncClient):
        payload = {
            "amount": -10,
            "card_type": "pix",
            "card_number_hash": "",
            "status": "xxx",
        }
        resp = await client.post("/transactions", json=payload)
        assert resp.status_code == 422
