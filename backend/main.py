import io
import json
import os

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI
from pypdf import PdfReader

app = FastAPI(title="Wise Learner API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
client = OpenAI()  # lit OPENAI_API_KEY dans l'environnement
MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

PROMPT = """Tu es un assistant pédagogique. À partir du texte fourni, réponds UNIQUEMENT en JSON :
{"summary": "résumé clair en français, 150 à 250 mots",
 "questions": [{"q": "question", "options": ["A","B","C","D"], "answer": 0, "explanation": "pourquoi"}]}
Génère exactement 5 questions à choix multiple, 4 options chacune, "answer" = index (0 à 3) de la bonne réponse."""


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/process")
async def process(file: UploadFile = File(...)):
    if not (file.filename or "").lower().endswith(".pdf"):
        raise HTTPException(400, "Le fichier doit être un PDF.")
    try:
        reader = PdfReader(io.BytesIO(await file.read()))
        text = "\n".join(page.extract_text() or "" for page in reader.pages).strip()
    except Exception:
        raise HTTPException(400, "Impossible de lire ce PDF.")
    if len(text) < 50:
        raise HTTPException(422, "Aucun texte exploitable (PDF scanné ?).")
    try:
        res = client.chat.completions.create(
            model=MODEL,
            response_format={"type": "json_object"},
            messages=[{"role": "system", "content": PROMPT}, {"role": "user", "content": text[:30000]}],
        )
        return json.loads(res.choices[0].message.content)
    except Exception as e:
        raise HTTPException(502, f"Erreur IA : {e}")
