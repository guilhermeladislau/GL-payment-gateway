import uuid

from fastapi.testclient import TestClient


class TestAPI:

    def test_health(self, client: TestClient):
        resp = client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    def test_criar_transacao(self, client: TestClient):
        payload = {
            "amount": 150.75,
            "card_type": "credit",
            "card_number_hash": "abc123",
            "status": "approved",
        }
        resp = client.post("/transactions", json=payload)
        assert resp.status_code == 201
        data = resp.json()
        assert data["amount"] == 150.75
        assert "id" in data

    def test_listar_transacoes(self, client: TestClient):
        resp = client.get("/transactions")
        assert resp.status_code == 200
        assert resp.json()["data"] == []

    def test_buscar_por_id(self, client: TestClient):
        # criar primeiro
        payload = {
            "amount": 100.0,
            "card_type": "debit",
            "card_number_hash": "hash123",
            "status": "approved",
        }
        create_resp = client.post("/transactions", json=payload)
        tx_id = create_resp.json()["id"]

        # buscar
        resp = client.get(f"/transactions/{tx_id}")
        assert resp.status_code == 200
        assert resp.json()["id"] == tx_id

    def test_transacao_nao_encontrada(self, client: TestClient):
        fake_id = str(uuid.uuid4())
        resp = client.get(f"/transactions/{fake_id}")
        assert resp.status_code == 404

    def test_dados_invalidos(self, client: TestClient):
        payload = {
            "amount": -10,
            "card_type": "pix",
            "card_number_hash": "",
            "status": "xxx",
        }
        resp = client.post("/transactions", json=payload)
        assert resp.status_code == 422
