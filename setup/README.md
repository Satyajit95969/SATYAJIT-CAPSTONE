# Setup — fresh Windows machine

One command per step, in order. Run everything from PowerShell at the repo
root unless noted otherwise. Every script under `setup/` is safe to re-run
and never deletes anything.

This snapshot deliberately excludes: the DAIC-WOZ dataset itself, any
derived per-participant artifacts, and TLS keys/certificates. You'll supply
the dataset yourself (step 6) and generate your own device identity (step
8) — that's by design, not an oversight; see step 8 for why.

---

## 1. Prerequisites — install these manually first

| Tool | Verified version | Official download |
|---|---|---|
| Python | **3.11.9** (any 3.11.x should work; this exact patch is what the working `.venv` was built with — read from `.venv/pyvenv.cfg`, not guessed) | https://www.python.org/downloads/release/python-3119/ |
| Git for Windows | any recent | https://git-scm.com/download/win |
| Rust (via rustup) | 1.95.x verified, no strict minimum pinned in `Cargo.toml` (edition 2021) | https://rustup.rs |
| MongoDB Server | 8.0.x | https://www.mongodb.com/try/download/community |
| Ollama | any recent | https://ollama.com/download |

Git for Windows is listed separately from "you'll need git to clone" —
this project also uses the `openssl.exe` that ships inside Git's
`mingw64\bin` to verify the enrollment client certificate (step 8). Make
sure Git is installed even if you already have another git client.

Run `setup\01_check_prereqs.ps1` after installing these to confirm
everything is on PATH.

---

## 2. Clone the repo

```powershell
git clone <this-repo-url> Capstone-
cd Capstone-
```

Nothing further needed — this snapshot was pushed as the repo's default
branch (`main`), so a plain clone already has you on the right branch.

---

## 3. Create the venv and install dependencies

```powershell
.\setup\02_install_python_deps.ps1
```

This installs from **`setup/requirements.freeze.txt`**, not the repo-root
`requirements.lock.txt` or `requirements.txt`. Why — this repo has three
dependency manifests and they disagree:

- `requirements.lock.txt` pins **`torch==2.10.0`** — wrong. The actual,
  exercised, working environment runs **`torch==2.8.0+cu128`**.
- `requirements.txt` (267 lines) is a broader, partly-aspirational list.
  It includes optional media-processing packages (`spacy`, `librosa`,
  `webrtcvad`, `openai-whisper`, `mediapipe`, `pyannote.audio`) that were
  **never installed** in the verified environment — the pipeline has
  documented fallback behavior for all of them (you'll see `Optional
  dependency 'X' could not be imported` WARNING lines in client logs;
  that's expected, not a failure). It also has real version drift on core
  packages relative to what's actually installed and tested: `numpy`
  1.26→2.4, `pandas` 2.3→3.0, `grpcio` 1.62→1.83, `cryptography` 45→50,
  `opencv-python` 4.11→5.0.
- `setup/requirements.freeze.txt` is a straight `pip freeze` of the real,
  exercised venv (56 packages) — this is the one that's actually been
  verified to work end-to-end, and what the install script uses.

**Torch is installed separately, before the rest of the freeze file.** The
freeze file pins `torch==2.8.0+cu128` (and matching `torchaudio`/
`torchvision`) — that `+cu128` local-version suffix is **not a real PyPI
release**; a plain `pip install -r` on that line fails on a fresh machine.
`setup/02_install_python_deps.ps1` handles this correctly:
1. Detects whether an NVIDIA GPU is present (`nvidia-smi` on PATH).
2. Installs `torch==2.8.0` / `torchaudio==2.8.0` / `torchvision==0.23.0`
   from the matching official wheel index — `https://download.pytorch.org/whl/cu128`
   if a GPU was detected, `https://download.pytorch.org/whl/cpu` otherwise
   — **before** anything else.
3. Installs the rest of `setup/requirements.freeze.txt` with the three
   torch lines stripped out, so pip never tries to re-resolve them from
   PyPI.

No GPU: same torch/torchaudio/torchvision versions, CPU backend —
`torch.cuda.is_available()` reports `False` and training is slower (this
project's own runs used a GPU), but everything still works.

---

## 4. Pull the narrative-generation model

```powershell
ollama pull phi3:mini
```

Used by `scripts/clinical_narrative_agent.py` and
`scripts/privacy_explanation_agent.py` (both default `--model phi3:mini`,
localhost-only Ollama calls — no external network use).

---

## 5. Build the orchestrator

```powershell
.\setup\03_build_orchestrator.ps1
```

`protoc` is **not** required — `tonic-build`/`prost-build` (pinned in
`server/orchestration_agent/Cargo.toml`) bundle their own; verified by a
real `cargo build --release` succeeding with no `protoc` on this machine's
PATH.

---

## 6. Place the dataset

You said you already have the dataset. The live pipeline reads it from
exactly this path (read directly from `runtime/pipeline.py`'s
`_MULTIMODAL_PARQUET` constant, not assumed):

```
dataset_build\daic_records_multimodal_participant_only.parquet
```

Relative to the repo root. Create the `dataset_build\` folder if it
doesn't already exist (it's gitignored — the folder itself is fine to
have locally, only its generated `*.json` audit files are excluded from
this repo).

---

## 7. Place the MentalBERT model

**Not in the repo.** The live code loads it exclusively from (read from
`MENTALBERT_PRETRAIN` in `installer/runtime/agents/trainer/trainer_mentalbert_privacy.py`):

```
%USERPROFILE%\.federated\models\mentalbert\
```

This needs the standard HuggingFace files for `mental/mental-bert-base-uncased`
(config.json, tokenizer files, and either `pytorch_model.bin` or
`model.safetensors`). If you have HuggingFace Hub access to that gated
repo, download it there; otherwise the trainer falls back to
`bert-base-uncased` automatically.

(A stray, empty, broken git submodule reference used to exist in this repo
at `installer/runtime/models/mentalbert/mental-bert-base-uncased` — it
contained zero actual bytes and no live code ever read it. Removed from
this snapshot; ignore any mention of that path elsewhere in older docs.)

---

## 8. First run needs fresh TPM enrollment — this is intentional

Every device gets its own hardware-backed (TPM/CNG) ECDSA key and its own
client certificate, issued by the orchestrator after a one-time OTP
handshake. **Keys and certificates from the original machine will not, and
must not, work here** — that's the whole point of hardware-backed device
identity, not a setup bug to work around.

With the orchestrator running (see `MENTOR_DEMO_RUNBOOK.md`):

```powershell
.\.venv\Scripts\python.exe enroll_step5.py <path-to-orchestrator-log>
```

This reads the OTP automatically from the orchestrator's own log output.
Full expected output and cert-verification commands: `RUNBOOK.md`, section
9 ("Device Enrollment").

---

## 9. Verify everything

```powershell
.\setup\04_verify.ps1
```

Read-only. Imports every key package, checks `ollama list` for
`phi3:mini`, and prints the exact paths for the dataset parquet, the
MentalBERT model, and the device certificate, with whether each exists yet
— safe to re-run after each of steps 6/7/8 to check progress.

---

## 10. Running the pipeline

Once steps 1–9 are green: `MENTOR_DEMO_RUNBOOK.md` at the repo root walks
through starting MongoDB, starting the orchestrator, and running a full
client round end to end. `RUNBOOK.md` has more detail on each individual
step and troubleshooting (§18 has a symptom-indexed table).

**One script that won't run out of the box: `scripts/demo_predictions.py`.**
It reads one specific client session's XAI/receipt artifacts from
`~/.federated/data/anchor_session_backups/client-405c6057ab84/`, which is
deliberately **not** in this repo — it's derived from the licensed
DAIC-WOZ corpus (a real participant ID, label, and transcript token
excerpts), so it's excluded from this snapshot on purpose, the same way
the dataset itself is. The script will refuse to run without it (a loud,
explicit error, not a silent failure) — that's correct, intended
behavior, not a bug to work around. To use it: get that directory through
a private channel from the original machine, or run a full client round
yourself (step 10 above) to generate a fresh session and point the script
at its own `explain_logs/xai_ig_<session_id>_<timestamp>.json` via
`--xai-report`.
