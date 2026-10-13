import json
import math
import os
import time

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI, RateLimitError
from pypdf import PdfReader

app = FastAPI(title="Wise Learner API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
client = OpenAI()  # lit OPENAI_API_KEY (et OPENAI_BASE_URL) dans l'environnement
MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
MAX_CHARS = int(os.getenv("MAX_CHARS", "12000"))      # texte du PDF envoyé à l'IA
NB_QUESTIONS = int(os.getenv("NB_QUESTIONS", "30"))   # minimum de questions
BATCH = int(os.getenv("QUIZ_BATCH", "10"))            # questions par appel IA

SUMMARY_PROMPT = """Tu es un professeur pédagogue. Rédige en français un résumé DÉTAILLÉ et EXPLICITE du texte fourni :
1) INTRODUCTION : contexte et objectif du document ;
2) puis chaque idée principale développée section par section, avec les définitions, explications, exemples, chiffres et termes importants du texte ;
3) CONCLUSION : « À RETENIR » avec 6 à 8 points essentiels.
Texte brut uniquement (pas de markdown : ni #, ni **). Titres de sections en MAJUSCULES, listes avec « • ». Longueur : 600 à 900 mots.
Réponds UNIQUEMENT en JSON : {"summary": "..."}"""

QUIZ_PROMPT = """Tu es un professeur. À partir du texte fourni, génère exactement __N__ questions à choix multiple en français, variées et de difficulté progressive (compréhension, application, détails importants).
__AVOID__
Réponds UNIQUEMENT en JSON : {"questions": [{"q": "question", "options": ["A", "B", "C", "D"], "answer": 0, "explanation": "pourquoi"}]}
4 options par question ; "answer" = index (0 à 3) de la bonne réponse, répartie sur les 4 positions."""


def ask_json(system: str, user: str, max_tokens: int) -> dict:
    last = None
    for attempt in range(5):
        try:
            res = client.chat.completions.create(
                model=MODEL,
                response_format={"type": "json_object"},
                max_tokens=max_tokens,
                messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
            )
            return json.loads(res.choices[0].message.content)
        except RateLimitError as e:  # limite par minute (offre gratuite) : on patiente
            last = e
            time.sleep(15 * (attempt + 1))
        except (json.JSONDecodeError, TypeError) as e:  # réponse vide ou tronquée
            last = e
    raise HTTPException(502, f"Erreur IA : {last}")


def valid(q) -> bool:
    return (
        isinstance(q, dict)
        and isinstance(q.get("q"), str)
        and isinstance(q.get("options"), list)
        and len(q["options"]) == 4
        and isinstance(q.get("answer"), int)
        and 0 <= q["answer"] <= 3
    )


def summarize(text: str) -> str:
    data = ask_json(SUMMARY_PROMPT, text, 3500)
    return str(data.get("summary", "")).strip()


def build_quiz(text: str) -> list:
    parts = 3
    size = math.ceil(len(text) / parts)
    chunks = [text[i * size:(i + 1) * size] for i in range(parts)]
    questions, seen = [], set()
    tries = 0
    max_tries = math.ceil(NB_QUESTIONS / BATCH) + 4
    while len(questions) < NB_QUESTIONS and tries < max_tries:
        n = min(BATCH, NB_QUESTIONS - len(questions))
        avoid = ""
        if questions:
            avoid = "Ne répète pas ces questions déjà posées : " + " | ".join(q["q"] for q in questions[-20:])
        prompt = QUIZ_PROMPT.replace("__N__", str(n)).replace("__AVOID__", avoid)
        data = ask_json(prompt, chunks[tries % parts], 4000)
        for q in data.get("questions", []):
            key = q["q"].strip().lower() if valid(q) else None
            if key and key not in seen:
                seen.add(key)
                questions.append(q)
        tries += 1
    return questions


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/process")
def process(file: UploadFile = File(...)):
    if not (file.filename or "").lower().endswith(".pdf"):
        raise HTTPException(400, "Le fichier doit être un PDF.")
    try:
        reader = PdfReader(file.file)
        text = "\n".join(page.extract_text() or "" for page in reader.pages).strip()
    except Exception:
        raise HTTPException(400, "Impossible de lire ce PDF.")
    if len(text) < 50:
        raise HTTPException(422, "Aucun texte exploitable (PDF scanné ?).")
    text = text[:MAX_CHARS]
    try:
        return {"summary": summarize(text), "questions": build_quiz(text)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(502, f"Erreur IA : {e}")