import time

from fastapi import FastAPI, Request

from src.routes import router, http_requests_total, http_request_duration

app = FastAPI(
    title="GL Payment Gateway",
    version="1.0.0",
)


# cria as tabelas quando a app inicia
@app.on_event("startup")
def startup():
    from src.database import engine, Base
    from src.models import Transaction  # noqa - precisa importar pra registrar o model

    Base.metadata.create_all(bind=engine)
    print("tabelas criadas")


# middleware de metricas
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    # nao medir o endpoint de metricas
    if request.url.path == "/metrics":
        return await call_next(request)

    start = time.time()
    response = await call_next(request)
    duration = time.time() - start

    http_requests_total.labels(
        method=request.method,
        route=request.url.path,
        status_code=str(response.status_code),
    ).inc()
    http_request_duration.labels(
        method=request.method,
        route=request.url.path,
    ).observe(duration)

    return response


app.include_router(router)

print("app iniciado")
