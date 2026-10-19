import os

from fastapi import FastAPI

app = FastAPI(title="Service_Template")
SERVICE_NAME = os.getenv("SERVICE_NAME", "Service_Template")

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.get("/readyz")
def readyz():
    return {"status": "ready"}

@app.get("/hello/{name}")
def hello(name: str):
    return {"message": f"Hello {name}, from {SERVICE_NAME}"}