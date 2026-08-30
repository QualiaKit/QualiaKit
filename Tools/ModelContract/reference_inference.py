#!/usr/bin/env python3
"""Offline reference tokenizer, Core ML runner, fixture generator, and verifier.

Generation is an explicit maintainer operation.  Normal verification is read-only:

    python3 Tools/ModelContract/reference_inference.py --verify

The protected model and vocabulary are read only from QUALIAKIT_TEST_MODEL_PATH
and QUALIAKIT_TEST_VOCAB_PATH unless a test-only explicit override is supplied.
No dependency is downloaded and no network API is used.
"""

from __future__ import annotations

import argparse
import copy
import datetime
import hashlib
import json
import math
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import unicodedata
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "Models/current/manifest.json"
SCHEMA_PATH = ROOT / "Models/current/manifest.schema.json"
CHECKSUMS_PATH = ROOT / "Models/current/checksums.json"
HELPER_PATH = ROOT / "Tools/ModelContract/coreml_inference.swift"
CURRENT_RUNTIME_SOURCE_PATH = ROOT / "Sources/QualiaBert/BertModelWrapper.swift"
CURRENT_TOKENIZER_SOURCE_PATH = ROOT / "Sources/QualiaBert/BertTokenizer.swift"
CURRENT_RUNTIME_TEST_PATH = ROOT / "Tests/QualiaKitTests/CurrentModelContractTests.swift"
LOCK_PATH = ROOT / "Tools/ModelContract/requirements.lock"
LABELS = [f"LABEL_{index}" for index in range(5)]
MODEL_COMPONENTS = {
    "Manifest.json": "a655c85265418a3c567fc48869e4bab5271b2340e33b7b67bdc395f3874bb302",
    "Data/com.apple.CoreML/model.mlmodel": "f7ac2156e756a2aacd1cca8cc3f3aded5e7b143147270ea0aea374747a609a42",
    "Data/com.apple.CoreML/weights/weight.bin": "26c028484b4df267933afbfa3ef9ca421dc7450d48bd02c720146bd4444da2f2",
}
VOCAB_SHA256 = "78106a3d3ae8600d1ba573b967b9bb731d2c2282957cbc6e26ab20935c3da02b"
CONTRACT_VERSION = "current-russian-v1"
FIXTURE_VERSION = "current-russian-fixture-v1"
GOLDEN_ROOT = ROOT / "Tests/Golden/current"
GOLDEN_DIRECTORY = GOLDEN_ROOT / FIXTURE_VERSION
CORPUS_PATH = GOLDEN_DIRECTORY / "corpus-v1.json"
GOLDEN_PATH = GOLDEN_DIRECTORY / "fixture-v1.json"
CALIBRATION_PATH = GOLDEN_DIRECTORY / "calibration-v1.json"
RUN_REPORT_PATH = GOLDEN_DIRECTORY / "run-report-v1.json"
MANIFEST_SNAPSHOT_PATH = GOLDEN_DIRECTORY / "manifest.json"
INDEX_PATH = GOLDEN_DIRECTORY / "index.json"
VERIFICATION_EVIDENCE_PATH = GOLDEN_DIRECTORY / "verification-v1.json"
MODEL_IDENTIFIER = "rub-sentiment-coreml-local-audit"
MODEL_VERSION = "sha256-f7ac2156e756a2aa"
PINNED_PYTHON_VERSION = (3, 14, 0)
PINNED_PYTHON_VERSION_STRING = "3.14.0"
PINNED_PYTHON_COMMAND = "python3.14"
PROBE_ERRORS = (
    "checksum-inventory",
    "holdout-overrun",
    "incomplete-fixture",
    "missing-model-component",
    "published-overwrite",
    "unsupported-schema",
    "vocabulary-checksum",
)


class ContractError(RuntimeError):
    def __init__(self, stage: str, artifact: str, detail: str):
        super().__init__(f"contract-error[{stage}:{artifact}]: {detail}")


def bootstrap_pinned_python() -> None:
    """Re-exec with the locked interpreter when `python3` resolves elsewhere."""
    if sys.version_info[:3] == PINNED_PYTHON_VERSION:
        return
    candidate = shutil.which(PINNED_PYTHON_COMMAND)
    if candidate is None or Path(candidate).resolve() == Path(sys.executable).resolve():
        raise ContractError(
            "environment",
            "python",
            f"lock requires {PINNED_PYTHON_VERSION_STRING}, observed {platform.python_version()}; "
            f"{PINNED_PYTHON_COMMAND} is unavailable",
        )
    try:
        os.execv(candidate, [candidate, str(Path(__file__).resolve()), *sys.argv[1:]])
    except OSError as error:
        raise ContractError(
            "environment", "python", f"failed to launch {PINNED_PYTHON_COMMAND}: {error}"
        ) from error


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise ContractError("read", path.name, str(error)) from error
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def read_json(path: Path) -> Any:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError("parse", path.name, str(error)) from error


def write_generated_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode())


def package_identity_sha256() -> str:
    lines = [f"{path}:{MODEL_COMPONENTS[path]}" for path in sorted(MODEL_COMPONENTS)]
    return sha256_bytes(("\n".join(lines) + "\n").encode())


def build_corpus() -> dict[str, Any]:
    cases: list[dict[str, Any]] = []

    def add(identifier: str, text: str, *categories: str) -> None:
        cases.append({
            "id": identifier,
            "text": text,
            "languageHint": "ru",
            "categories": list(categories),
            "source": "authored-sanitized",
        })

    add("edge-empty", "", "whitespace")
    add("edge-whitespace", " \t\n  ", "whitespace")
    add("unicode-yo", "Ёжик идёт под тёплый дождь.", "yo_e", "punctuation")
    add("unicode-e", "Ежик идет под теплый дождь.", "yo_e", "punctuation")
    add("dash-hyphen", "Старый дом — не конец пути.", "dash_variants", "negation")
    add("dash-en", "Тихий лес – безопасное место.", "dash_variants")
    add("dash-em", "Шаг — пауза — ещё один шаг.", "dash_variants", "yo_e")
    add("quotes-angle", "Он прошептал: «Я рядом».", "quote_variants")
    add("quotes-curly", "Она ответила: “Это не сон”.", "quote_variants", "negation")
    add("quotes-ascii", "Голос сказал: \"Не бойся\".", "quote_variants", "negation")
    add("ellipsis-unicode", "Дверь медленно открылась…", "ellipses")
    add("ellipsis-ascii", "Дверь медленно открылась...", "ellipses")
    add("emoji-light", "В окне зажёгся свет ✨", "emoji", "yo_e")
    add("emoji-alarm", "Сирена замолчала 🚨, все целы.", "emoji")
    add("emoji-family", "Семья вернулась домой 👨‍👩‍👧‍👦", "emoji")
    add("mixed-latin", "Система SAFE, но экран всё ещё мигает.", "mixed_scripts", "yo_e")
    add("mixed-number", "Сектор B-12 закрыт до 07:30.", "mixed_scripts", "dash_variants")
    add("mixed-cyrillic-latin", "Код доступа alphaБета42 не принят.", "mixed_scripts", "negation")
    add("case-lower", "это только начало", "casing")
    add("case-title", "Это Только Начало", "casing")
    add("case-upper", "ЭТО ТОЛЬКО НАЧАЛО", "casing")
    add("unknown-long", "сверхквазипсевдонедоразумение", "unknown_words")
    add("unknown-symbols", "абракадабраxyz987 и qqqщщщ", "unknown_words", "mixed_scripts")
    add("punctuation-dense", "Стой!!! Кто там?! Никого; показалось.", "punctuation")
    add("newline-dialogue", "— Ты слышал?\n— Нет, ничего.", "whitespace", "dash_variants", "negation")

    narrative = [
        "На лестнице погас свет, и шаги стали ближе.",
        "За окном качнулась ветка, хотя ветра не было.",
        "Письмо лежало на столе без подписи.",
        "Лифт остановился между этажами.",
        "Телефон зазвонил в пустой комнате.",
        "В коридоре появилась новая дверь.",
        "Часы пробили тринадцать раз.",
        "Собака смотрела в тёмный угол.",
        "На снегу виднелась одна цепочка следов.",
        "Ключ подошёл к старому замку.",
        "Герой спрятал карту и продолжил путь.",
        "Поезд медленно вошёл в туман.",
        "Радио поймало далёкий шёпот.",
        "Вода под мостом внезапно замерла.",
        "Книга открылась на последней странице.",
        "Фонарь мигнул и снова загорелся.",
        "Путники нашли тёплое убежище.",
        "Утром команда получила хорошие новости.",
        "Старый механизм наконец заработал.",
        "Друзья встретились у знакомого дома.",
        "Врач из вымышленной истории закончил смену.",
        "Капитан проверил маршрут перед отплытием.",
        "Музыка стихла перед началом спектакля.",
        "Ребёнок нашёл потерянную игрушку.",
        "Дождь закончился, и облака разошлись.",
        "Последний автобус ждал на остановке.",
        "Архив оказался аккуратно рассортирован.",
        "Экспедиция передала сигнал на базу.",
        "Сад наполнился запахом сирени.",
        "На площади зажглись праздничные огни.",
        "Разговор завершился спокойным согласием.",
        "Неизвестный силуэт исчез за поворотом.",
        "Комната казалась меньше, чем вчера.",
        "В стене тихо щёлкнул скрытый механизм.",
        "Песок под ногами начал едва заметно дрожать.",
        "Из закрытого шкафа донёсся стук.",
        "Карта показывала дорогу, которой не существовало.",
        "В зеркале отражалось открытое окно.",
        "Свеча погасла без причины.",
        "На пороге лежал свежий букет.",
    ]
    for index, text in enumerate(narrative, 1):
        categories = ["production_like"]
        if "не " in text or "Не" in text or "которой не" in text:
            categories.append("negation")
        if "ё" in text or "Ё" in text:
            categories.append("yo_e")
        add(f"narrative-{index:03d}", text, *categories)

    negations = [
        "Я не боюсь этого пустого коридора.",
        "Это вовсе не плохая новость.",
        "Никто не пострадал во время учебной тревоги.",
        "Опасность не подтвердилась.",
        "Неожиданный шум оказался звуком дождя.",
        "Герой никогда не открывает дверь без проверки.",
        "Мы не потеряли карту, она лежит в рюкзаке.",
        "Ни один сигнал не указывал на угрозу.",
        "Не было ни крика, ни следов борьбы.",
        "Странный силуэт оказался обычной вешалкой.",
        "Система не обнаружила ошибок.",
        "Я едва не забыл выключить фонарь.",
        "Нельзя сказать, что путь был опасным.",
        "Он не только вернулся, но и привёл помощь.",
        "Тишина здесь не означает беду.",
    ]
    for index, text in enumerate(negations, 1):
        add(f"negation-{index:03d}", text, "negation", "production_like")

    hard_negatives = [
        "Ужасно вкусный пирог исчез за минуту.",
        "Страшно красивый закат окрасил море.",
        "Убийственный темп репетиции всем понравился.",
        "Кровь дракона — название безалкогольного напитка.",
        "Фильм ужасов оказался доброй пародией.",
        "Мёртвая петля была фигурой на авиашоу.",
        "В игре герой получил безопасный учебный удар.",
        "Кошмарный свитер подарили на шуточный праздник.",
        "Опасно близкий счёт сделал матч интереснее.",
        "Тревога была только плановой проверкой.",
        "Монстр на плакате рекламировал детский спектакль.",
        "Призрак оказался рисунком на занавеске.",
        "Взрыв смеха раздался в зрительном зале.",
        "Роковой аккорд завершил весёлую песню.",
        "Пугающе точный прогноз помог путешественникам.",
    ]
    for index, text in enumerate(hard_negatives, 1):
        add(f"hard-negative-{index:03d}", text, "hard_negative", "production_like")

    short_variants = [
        "Да.", "Нет.", "Возможно.", "Тихо.", "Слишком тихо.", "Всё хорошо.",
        "Путь свободен.", "Свет погас.", "Дверь открыта.", "Сигнал принят.",
    ]
    for index, text in enumerate(short_variants, 1):
        add(f"short-{index:03d}", text, "production_like")

    add("truncation-125", " ".join(["и"] * 125), "truncation")
    add("truncation-126", " ".join(["и"] * 126), "truncation")
    add("truncation-127", " ".join(["и"] * 127), "truncation")
    add("truncation-wordpiece", " ".join(["путешественники"] * 80), "truncation")

    required = {
        "yo_e", "dash_variants", "quote_variants", "ellipses", "emoji",
        "mixed_scripts", "negation", "hard_negative", "casing", "unknown_words", "truncation",
    }
    present = {category for case in cases for category in case["categories"]}
    if len(cases) < 100 or not required.issubset(present):
        raise AssertionError("curated corpus coverage invariant failed")
    if len({case["id"] for case in cases}) != len(cases):
        raise AssertionError("curated corpus case ids must be unique")
    return {
        "schemaVersion": 1,
        "fixtureVersion": FIXTURE_VERSION,
        "license": "repository MIT license; authored sanitized text; no production user text",
        "caseCount": len(cases),
        "requiredCoverage": sorted(required),
        "cases": cases,
    }


class ReferenceTokenizer:
    def __init__(self, vocab_path: Path):
        try:
            lines = vocab_path.read_text(encoding="utf-8").splitlines()
        except OSError as error:
            raise ContractError("tokenizer", "vocabulary", str(error)) from error
        self.vocab: dict[str, int] = {}
        self.tokens_by_id: dict[int, str] = {}
        for index, line in enumerate(lines):
            if line:
                if line in self.vocab:
                    raise ContractError("tokenizer", "vocabulary", "duplicate nonblank token")
                self.vocab[line] = index
                self.tokens_by_id[index] = line
        if len(self.vocab) != 119_547:
            raise ContractError("tokenizer", "vocabulary", "expected 119547 unique nonblank records")
        expected_specials = {"[PAD]": 0, "[UNK]": 100, "[CLS]": 101, "[SEP]": 102, "[MASK]": 103}
        for token, expected_id in expected_specials.items():
            if self.vocab.get(token) != expected_id:
                raise ContractError("tokenizer", "vocabulary", f"special token {token} has unexpected id")

    @staticmethod
    def split_words(value: str) -> list[str]:
        words: list[str] = []
        current: list[str] = []
        for character in value:
            if character.isspace() or unicodedata.category(character).startswith("P"):
                if current:
                    words.append("".join(current))
                    current = []
            else:
                current.append(character)
        if current:
            words.append("".join(current))
        return words

    def wordpiece(self, word: str) -> list[str]:
        if word in self.vocab:
            return [word]
        output: list[str] = []
        remaining = word
        while remaining:
            found: tuple[str, int] | None = None
            for length in range(len(remaining), 0, -1):
                prefix = remaining[:length]
                candidate = prefix if not output else f"##{prefix}"
                if candidate in self.vocab:
                    found = (candidate, length)
                    break
            if found is None:
                return ["[UNK]"]
            output.append(found[0])
            remaining = remaining[found[1]:]
        return output

    def tokenize(self, text: str) -> dict[str, Any]:
        lowered = text.lower()
        unpadded = ["[CLS]"]
        for word in self.split_words(lowered):
            unpadded.extend(self.wordpiece(word))
        unpadded.append("[SEP]")
        pre_truncation_count = len(unpadded)
        if len(unpadded) > 128:
            unpadded = unpadded[:127] + ["[SEP]"]
        token_count = len(unpadded)
        tokens = unpadded + ["[PAD]"] * (128 - token_count)
        input_ids = [self.vocab.get(token, 100) for token in tokens]
        return {
            "normalizedText": lowered,
            "tokens": tokens,
            "inputIds": input_ids,
            "attentionMask": [1] * token_count + [0] * (128 - token_count),
            "tokenTypeIds": [0] * 128,
            "preTruncationTokenCount": pre_truncation_count,
            "wasTruncated": pre_truncation_count > 128,
        }


def validate_model_assets(model_path: Path) -> None:
    if not model_path.is_dir():
        raise ContractError("asset", "current-model", "missing model package directory")
    for relative, expected in MODEL_COMPONENTS.items():
        component = model_path / relative
        if not component.is_file():
            raise ContractError("asset", relative, "missing required model component")
        actual = sha256_file(component)
        if actual != expected:
            raise ContractError("checksum", relative, f"expected {expected}, observed {actual}")


def validate_vocabulary_asset(vocab_path: Path) -> None:
    if not vocab_path.is_file():
        raise ContractError("asset", "current-vocabulary", "missing vocabulary file")
    actual_vocab = sha256_file(vocab_path)
    if actual_vocab != VOCAB_SHA256:
        raise ContractError("checksum", "current-vocabulary", f"expected {VOCAB_SHA256}, observed {actual_vocab}")


def validate_assets(model_path: Path, vocab_path: Path) -> None:
    validate_model_assets(model_path)
    validate_vocabulary_asset(vocab_path)


def tool_output(arguments: list[str]) -> str:
    try:
        result = subprocess.run(arguments, check=True, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=120)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise ContractError("environment", arguments[0], str(error)) from error
    return result.stdout.strip()


def validate_environment() -> dict[str, Any]:
    if sys.version_info[:3] != PINNED_PYTHON_VERSION:
        raise ContractError(
            "environment",
            "python",
            f"lock requires {PINNED_PYTHON_VERSION_STRING}, observed {platform.python_version()}",
        )
    if not shutil.which("xcrun"):
        raise ContractError("environment", "xcrun", "required Xcode tool is unavailable")
    swift = tool_output(["xcrun", "swift", "--version"]).splitlines()[0]
    xcode = tool_output(["xcodebuild", "-version"]).splitlines()
    compiler = tool_output(["xcrun", "coremlcompiler", "version"])
    if "6.3.3" not in swift or xcode[:1] != ["Xcode 26.6"] or compiler != "3520.5.1":
        raise ContractError("environment", "requirements.lock", "Swift, Xcode, or Core ML compiler differs from pinned lock")
    return {
        "python": platform.python_version(),
        "pythonImplementation": platform.python_implementation(),
        "swift": swift,
        "xcode": xcode[0],
        "xcodeBuild": xcode[1].removeprefix("Build version ") if len(xcode) > 1 else "unknown",
        "coremlcompiler": compiler,
        "os": platform.mac_ver()[0],
        "architecture": platform.machine(),
        "backend": "CoreML",
        "computeUnits": "cpuOnly",
        "seedPolicy": "not exposed by Core ML prediction API",
        "networkDependencies": [],
    }


@contextmanager
def compiled_tools(model_path: Path) -> Iterator[tuple[Path, Path, str]]:
    directory = tempfile.TemporaryDirectory(prefix="qualia-model-contract-private-")
    cache = Path(directory.name)
    cache.chmod(0o700)
    compilation_identifier = uuid.uuid4().hex
    helper_sha = sha256_file(HELPER_PATH)
    helper = cache / f"coreml-inference-{helper_sha[:16]}"
    model = cache / "RuBSentimentModel.mlmodelc"
    module_cache = cache / "module-cache"
    module_cache.mkdir(mode=0o700)
    try:
        environment = dict(os.environ)
        environment["CLANG_MODULE_CACHE_PATH"] = str(module_cache)
        environment["SWIFT_MODULECACHE_PATH"] = str(module_cache)
        try:
            subprocess.run(["xcrun", "swiftc", "-O", str(HELPER_PATH), "-o", str(helper)],
                           check=True, env=environment, timeout=180)
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            raise ContractError("compile", "coreml_inference.swift", str(error)) from error
        helper.chmod(0o700)
        try:
            subprocess.run(["xcrun", "coremlcompiler", "compile", str(model_path), str(cache)],
                           check=True, timeout=300, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            raise ContractError("compile", "current-model", str(error)) from error
        yield helper, model, compilation_identifier
    finally:
        directory.cleanup()


def run_helper(
    helper: Path,
    compiled_model: Path,
    compilation_identifier: str,
    tokenized: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    request = {"cases": [{
        "id": item["id"],
        "inputIds": item["inputIds"],
        "attentionMask": item["attentionMask"],
        "tokenTypeIds": item["tokenTypeIds"],
    } for item in tokenized]}
    with tempfile.TemporaryDirectory(prefix="qualia-contract-run-") as directory:
        request_path = Path(directory) / "request.json"
        response_path = Path(directory) / "response.json"
        request_path.write_bytes(canonical_bytes(request))
        started = time.monotonic()
        try:
            result = subprocess.run([str(helper), str(compiled_model), str(request_path), str(response_path)],
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=900)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ContractError("inference", "current-model", str(error)) from error
        ended = time.monotonic()
        if result.returncode != 0:
            diagnostic = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "helper failed"
            raise ContractError("inference", "current-model", diagnostic[:400])
        response = read_json(response_path)
    if response.get("helperSchemaVersion") != 1 or response.get("computeUnits") != "cpuOnly":
        raise ContractError("inference", "helper-response", "unsupported helper response or compute policy")
    process_identifier = response.get("processIdentifier")
    if not isinstance(process_identifier, int) or process_identifier <= 0:
        raise ContractError("inference", "helper-response", "fresh process identifier is missing")
    cases = response.get("cases")
    if not isinstance(cases, list) or len(cases) != len(tokenized):
        raise ContractError("serialization", "helper-response", "incomplete case output")
    expected_ids = [item["id"] for item in tokenized]
    if [item.get("id") for item in cases] != expected_ids:
        raise ContractError("serialization", "helper-response", "case identity/order mismatch")
    for item in cases:
        raw = item.get("rawOutputs")
        if set(raw or {}) != set(LABELS) or item.get("predictedLabel") not in LABELS:
            raise ContractError("output-contract", "classLabel_probs", "declared and observed label spaces differ")
        if not all(isinstance(raw[label], (int, float)) and math.isfinite(raw[label]) for label in LABELS):
            raise ContractError("output-contract", "classLabel_probs", "non-finite or non-numeric raw output")
    return cases, {
        "processIdentifier": process_identifier,
        "startedMonotonicSeconds": started,
        "endedMonotonicSeconds": ended,
        "durationSeconds": ended - started,
        "computeUnits": "cpuOnly",
        "helperSourceSha256": sha256_file(HELPER_PATH),
        "helperExecutableSha256": sha256_file(helper),
        "privateCompilationDirectory": True,
        "privateCompilationIdentifier": compilation_identifier,
    }


def run_fresh_compilation(
    model_path: Path, tokenized: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Compile the helper and model privately for exactly one fresh process sample."""
    with compiled_tools(model_path) as (helper, compiled_model, compilation_identifier):
        return run_helper(helper, compiled_model, compilation_identifier, tokenized)


def run_current_swift_runtime(
    model_path: Path, tokenized: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Run the production BertModelWrapper inside a fresh XCTest process with its default policy."""
    with tempfile.TemporaryDirectory(prefix="qualia-current-runtime-capture-") as directory:
        cache = Path(directory)
        cache.chmod(0o700)
        request_path = cache / "request.json"
        response_path = cache / "response.json"
        request = {"cases": [{
            "id": item["id"],
            "inputIds": item["inputIds"],
            "attentionMask": item["attentionMask"],
        } for item in tokenized]}
        request_path.write_bytes(canonical_bytes(request))
        environment = dict(os.environ)
        environment["QUALIAKIT_TEST_MODEL_PATH"] = str(model_path)
        environment["QUALIAKIT_CONTRACT_CAPTURE_REQUEST_PATH"] = str(request_path)
        environment["QUALIAKIT_CONTRACT_CAPTURE_RESPONSE_PATH"] = str(response_path)
        environment["CLANG_MODULE_CACHE_PATH"] = str(cache / "clang-module-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(cache / "swift-module-cache")
        started = time.monotonic()
        try:
            result = subprocess.run(
                [
                    "swift", "test", "--filter",
                    "CurrentModelContractTests/testCurrentSwiftRuntimeMatchesCommittedIndependentGolden",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=environment,
                timeout=900,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ContractError("runtime-parity", "BertModelWrapper", str(error)) from error
        ended = time.monotonic()
        if result.returncode != 0:
            diagnostic = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "helper failed"
            raise ContractError("runtime-parity", "BertModelWrapper", diagnostic[:400])
        response = read_json(response_path)
        if response.get("helperSchemaVersion") != 1 or response.get("computeUnits") != "production-default":
            raise ContractError("runtime-parity", "helper-response", "unexpected production helper policy")
        process_identifier = response.get("processIdentifier")
        if not isinstance(process_identifier, int) or process_identifier <= 0:
            raise ContractError("runtime-parity", "helper-response", "fresh process identifier is missing")
        cases = response.get("cases")
        expected_ids = [item["id"] for item in tokenized]
        if not isinstance(cases, list) or [item.get("id") for item in cases] != expected_ids:
            raise ContractError("runtime-parity", "helper-response", "case identity/order mismatch")
        for item in cases:
            value = item.get("value")
            if not isinstance(value, (int, float)) or not math.isfinite(value):
                raise ContractError("runtime-parity", item.get("id", "case"), "non-finite wrapper output")
        return cases, {
            "processIdentifier": process_identifier,
            "startedMonotonicSeconds": started,
            "endedMonotonicSeconds": ended,
            "durationSeconds": ended - started,
            "computeUnits": "production-default",
            "productionSourceSha256": sha256_file(CURRENT_RUNTIME_SOURCE_PATH),
            "testHarnessSourceSha256": sha256_file(CURRENT_RUNTIME_TEST_PATH),
            "invocation": "swift test --filter CurrentModelContractTests/testCurrentSwiftRuntimeMatchesCommittedIndependentGolden",
        }


def stable_softmax(raw: dict[str, float]) -> dict[str, float]:
    maximum = max(raw.values())
    exponentials = {label: math.exp(raw[label] - maximum) for label in LABELS}
    denominator = sum(exponentials.values())
    return {label: exponentials[label] / denominator for label in LABELS}


def floating_values(item: dict[str, Any]) -> dict[str, float]:
    raw = item["rawOutputs"]
    softmax = stable_softmax(raw)
    values = {f"rawOutputs.{label}": float(raw[label]) for label in LABELS}
    values.update({f"stableSoftmax.{label}": softmax[label] for label in LABELS})
    values["currentSwiftTransform.value"] = float(
        item.get("currentSwiftTransformValue", softmax["LABEL_2"] - softmax["LABEL_0"])
    )
    return values


def percentile(sorted_values: list[float], probability: float) -> float:
    if not sorted_values:
        return 0.0
    rank = (len(sorted_values) - 1) * probability
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return sorted_values[lower]
    fraction = rank - lower
    return sorted_values[lower] * (1.0 - fraction) + sorted_values[upper] * fraction


def distribution(values: list[float]) -> dict[str, Any]:
    ordered = sorted(values)
    return {
        "count": len(ordered),
        "min": ordered[0] if ordered else 0.0,
        "p50": percentile(ordered, 0.50),
        "p95": percentile(ordered, 0.95),
        "p99": percentile(ordered, 0.99),
        "max": ordered[-1] if ordered else 0.0,
    }


def compare_run(baseline: list[dict[str, Any]], observed: list[dict[str, Any]]) -> dict[str, list[float]]:
    deltas: dict[str, list[float]] = {field: [] for field in floating_values(baseline[0])}
    for expected, actual in zip(baseline, observed, strict=True):
        if expected["id"] != actual["id"]:
            raise ContractError("calibration", "case-order", "process run changed case order")
        expected_values = floating_values(expected)
        actual_values = floating_values(actual)
        for field in deltas:
            deltas[field].append(abs(actual_values[field] - expected_values[field]))
    return deltas


def make_tokenized_cases(corpus: dict[str, Any], tokenizer: ReferenceTokenizer) -> list[dict[str, Any]]:
    result = []
    for case in corpus["cases"]:
        tokenized = tokenizer.tokenize(case["text"])
        tokenized["id"] = case["id"]
        tokenized["categories"] = case["categories"]
        tokenized["text"] = case["text"]
        result.append(tokenized)
    return result


def make_golden(
    corpus: dict[str, Any],
    tokenized: list[dict[str, Any]],
    raw_cases: list[dict[str, Any]],
    corpus_path: Path = CORPUS_PATH,
) -> dict[str, Any]:
    cases = []
    raw_by_id = {item["id"]: item for item in raw_cases}
    for item in tokenized:
        raw_item = raw_by_id[item["id"]]
        raw = {label: float(raw_item["rawOutputs"][label]) for label in LABELS}
        softmax = stable_softmax(raw)
        current_value = softmax["LABEL_2"] - softmax["LABEL_0"]
        text_bytes = item["text"].encode()
        normalized_bytes = item["normalizedText"].encode()
        cases.append({
            "id": item["id"],
            "contractVersion": CONTRACT_VERSION,
            "fixtureVersion": FIXTURE_VERSION,
            "modelIdentifier": MODEL_IDENTIFIER,
            "modelVersion": MODEL_VERSION,
            "inputMetadata": {
                "languageHint": "ru",
                "categories": item["categories"],
                "textSha256": sha256_bytes(text_bytes),
                "utf8ByteCount": len(text_bytes),
                "unicodeScalarCount": len(item["text"]),
                "normalization": {
                    "lowercaseApplied": True,
                    "unicodeNormalization": "none",
                    "normalizedTextSha256": sha256_bytes(normalized_bytes),
                    "normalizedUnicodeScalarCount": len(item["normalizedText"]),
                },
            },
            "tokens": item["tokens"],
            "inputIds": item["inputIds"],
            "attentionMask": item["attentionMask"],
            "tokenTypeIds": item["tokenTypeIds"],
            "preTruncationTokenCount": item["preTruncationTokenCount"],
            "wasTruncated": item["wasTruncated"],
            "rawOutputs": raw,
            "predictedLabel": raw_item["predictedLabel"],
            "transformedScores": {"stableSoftmax": softmax},
            "currentSwiftTransform": {
                "kind": "second-softmax-label2-minus-label0",
                "negativeAssumption": "LABEL_0",
                "positiveAssumption": "LABEL_2",
                "value": current_value,
            },
            "finalSemanticMapping": {
                "status": "unknown",
                "productSignal": None,
                "reason": "no primary label-semantics evidence",
            },
        })
    return {
        "schemaVersion": 1,
        "contractVersion": CONTRACT_VERSION,
        "fixtureVersion": FIXTURE_VERSION,
        "modelIdentifier": MODEL_IDENTIFIER,
        "modelVersion": MODEL_VERSION,
        "corpusSha256": sha256_file(corpus_path),
        "caseCount": len(cases),
        "generatedBy": "Tools/ModelContract/reference_inference.py --generate",
        "cases": cases,
    }


def calibrate_current_swift_runtime(
    model_path: Path,
    tokenized: list[dict[str, Any]],
    baseline_raw: list[dict[str, Any]],
) -> dict[str, Any]:
    reference = {
        item["id"]: floating_values(item)["currentSwiftTransform.value"]
        for item in baseline_raw
    }
    calibration_runs: list[dict[str, Any]] = []
    holdout_runs: list[dict[str, Any]] = []

    def fresh_run(index: int, phase: str) -> dict[str, Any]:
        cases, execution = run_current_swift_runtime(model_path, tokenized)
        return {
            "processSequence": index,
            "phase": phase,
            "freshOSProcess": True,
            **execution,
            "cases": cases,
        }

    def deltas(run: dict[str, Any]) -> list[float]:
        return [abs(float(item["value"]) - reference[item["id"]]) for item in run["cases"]]

    for index in range(1, 11):
        calibration_runs.append(fresh_run(index, "calibration"))

    while True:
        observed_deltas = [delta for run in calibration_runs for delta in deltas(run)]
        measured_distribution = distribution(observed_deltas)
        tolerance = measured_distribution["max"]
        holdout_runs = []
        exceeded = False
        first_sequence = len(calibration_runs) + 1
        for offset in range(5):
            run = fresh_run(first_sequence + offset, "holdout")
            maximum = max(deltas(run))
            run["maximumDelta"] = maximum
            run["withinFixedTolerance"] = maximum <= tolerance
            holdout_runs.append(run)
            exceeded = exceeded or not run["withinFixedTolerance"]
        if not exceeded:
            break
        calibration_runs.extend(holdout_runs)
        if len(calibration_runs) > 50:
            raise ContractError(
                "calibration", "BertModelWrapper", "could not establish a five-process holdout"
            )

    return {
        "schemaVersion": 1,
        "field": "currentSwiftRuntimeDefault.value",
        "referenceField": "currentSwiftTransform.value",
        "protocol": {
            "comparison": "absolute",
            "corpusScope": "full",
            "sequentialProcesses": True,
            "productionCodeInvoked": "Sources/QualiaBert/BertModelWrapper.swift",
            "computeUnits": "production-default",
            "modelReloadedEachProcess": True,
            "minimumCalibrationProcesses": 10,
            "minimumHoldoutProcesses": 5,
        },
        "referenceCases": [{"id": identifier, "value": value} for identifier, value in reference.items()],
        "calibrationProcessCount": len(calibration_runs),
        "holdoutProcessCount": len(holdout_runs),
        "distribution": measured_distribution,
        "absoluteTolerance": tolerance,
        "calibrationRuns": calibration_runs,
        "holdoutRuns": holdout_runs,
    }


def calibrate(model_path: Path, tokenized: list[dict[str, Any]],
              baseline_raw: list[dict[str, Any]], environment: dict[str, Any]) -> dict[str, Any]:
    calibration_runs: list[dict[str, Any]] = []
    holdout_runs: list[dict[str, Any]] = []

    def fresh_run(index: int, phase: str) -> dict[str, Any]:
        raw, execution = run_fresh_compilation(model_path, tokenized)
        for item in raw:
            item["floatingValues"] = floating_values(item)
        return {
            "processSequence": index,
            "phase": phase,
            "freshOSProcess": True,
            **execution,
            "cases": raw,
        }

    for index in range(1, 11):
        calibration_runs.append(fresh_run(index, "calibration"))

    while True:
        combined: dict[str, list[float]] = {field: [] for field in floating_values(baseline_raw[0])}
        for run in calibration_runs:
            deltas = compare_run(baseline_raw, run["cases"])
            for field, values in deltas.items():
                combined[field].extend(values)
        distributions = {field: distribution(values) for field, values in combined.items()}
        tolerances = {field: values["max"] for field, values in distributions.items()}

        holdout_runs = []
        first_sequence = len(calibration_runs) + 1
        exceeded = False
        for offset in range(5):
            run = fresh_run(first_sequence + offset, "holdout")
            deltas = compare_run(baseline_raw, run["cases"])
            run["maximumDeltaByField"] = {field: max(values) for field, values in deltas.items()}
            run["withinFixedTolerance"] = all(
                run["maximumDeltaByField"][field] <= tolerances[field] for field in tolerances
            )
            holdout_runs.append(run)
            exceeded = exceeded or not run["withinFixedTolerance"]
        if not exceeded:
            break
        calibration_runs.extend(holdout_runs)
        if len(calibration_runs) > 50:
            raise ContractError("calibration", "fresh-process", "could not establish a five-process holdout")

    current_runtime = calibrate_current_swift_runtime(model_path, tokenized, baseline_raw)
    return {
        "schemaVersion": 1,
        "contractVersion": CONTRACT_VERSION,
        "fixtureVersion": FIXTURE_VERSION,
        "protocol": {
            "comparison": "absolute",
            "reference": "fixture generation fresh process",
            "corpusScope": "full",
            "sequentialProcesses": True,
            "modelReloadedEachProcess": True,
            "modelRecompiledEachProcess": True,
            "privateCompilationPerProcess": True,
            "minimumCalibrationProcesses": 10,
            "minimumHoldoutProcesses": 5,
        },
        "environment": environment,
        "referenceCases": [{
            "id": item["id"],
            "floatingValues": floating_values(item),
        } for item in baseline_raw],
        "calibrationProcessCount": len(calibration_runs),
        "holdoutProcessCount": len(holdout_runs),
        "distributions": distributions,
        "absoluteToleranceByField": tolerances,
        "calibrationRuns": calibration_runs,
        "holdoutRuns": holdout_runs,
        "currentSwiftRuntimeDefault": current_runtime,
    }


def update_manifest(
    calibration: dict[str, Any],
    corpus_path: Path = CORPUS_PATH,
    golden_path: Path = GOLDEN_PATH,
    calibration_path: Path = CALIBRATION_PATH,
    write: bool = True,
) -> dict[str, Any]:
    manifest = read_json(MANIFEST_PATH)
    absolute_tolerances = dict(calibration["absoluteToleranceByField"])
    current_runtime = calibration["currentSwiftRuntimeDefault"]
    absolute_tolerances["currentSwiftRuntimeDefault.value"] = current_runtime["absoluteTolerance"]
    manifest["floatingPointTolerance"] = {
        "comparison": "absolute",
        "derivation": "maximum observed full-corpus fresh-process delta for CPU reference outputs and production-default BertModelWrapper parity",
        "absoluteByField": absolute_tolerances,
        "calibrationProcessCount": calibration["calibrationProcessCount"],
        "holdoutProcessCount": calibration["holdoutProcessCount"],
        "runtimeCalibrationProcessCount": current_runtime["calibrationProcessCount"],
        "runtimeHoldoutProcessCount": current_runtime["holdoutProcessCount"],
    }
    manifest["fixture"]["caseCount"] = read_json(corpus_path)["caseCount"]
    manifest["fixture"]["corpusSha256"] = sha256_file(corpus_path)
    manifest["fixture"]["goldenSha256"] = sha256_file(golden_path)
    manifest["fixture"]["calibrationSha256"] = sha256_file(calibration_path)
    if write:
        write_generated_json(MANIFEST_PATH, manifest)
    return manifest


def build_run_report(
    environment: dict[str, Any],
    durations: dict[str, float],
    baseline_execution: dict[str, Any],
    manifest: dict[str, Any],
    corpus: dict[str, Any],
    manifest_path: Path = MANIFEST_PATH,
    corpus_path: Path = CORPUS_PATH,
    golden_path: Path = GOLDEN_PATH,
    calibration_path: Path = CALIBRATION_PATH,
) -> dict[str, Any]:
    unknowns = [
        "model.source", "model.trainingDataset", "model.license", "model.redistributionRights",
        "model.domain", "model.classBalance", "tokenizer.trainingIdentity", "tokenizer.trainingVersion",
        "tokenizer.pairContextTemplate", "outputs.kind", "outputs.labelSemantics",
    ]
    return {
        "schemaVersion": 1,
        "status": "generated",
        "contractVersion": CONTRACT_VERSION,
        "fixtureVersion": FIXTURE_VERSION,
        "modelIdentifier": MODEL_IDENTIFIER,
        "modelVersion": MODEL_VERSION,
        "caseCount": corpus["caseCount"],
        "environment": environment,
        "computePolicy": {"backend": "CoreML", "computeUnits": "cpuOnly", "parallelInference": False},
        "durationsSeconds": durations,
        "baselineFreshProcess": baseline_execution,
        "checksums": {
            "modelPackageIdentitySha256": package_identity_sha256(),
            "modelComponents": MODEL_COMPONENTS,
            "vocabularySha256": VOCAB_SHA256,
            "manifestSha256": sha256_file(manifest_path),
            "schemaSha256": sha256_file(SCHEMA_PATH),
            "corpusSha256": sha256_file(corpus_path),
            "goldenSha256": sha256_file(golden_path),
            "calibrationSha256": sha256_file(calibration_path),
            "requirementsLockSha256": sha256_file(LOCK_PATH),
        },
        "warnings": [
            "Protected model and vocabulary redistribution remains blocked.",
            "All label meanings remain unknown; no product semantic signal is emitted.",
            "Current Swift runtime behavior is serialized for archaeology, not endorsed as semantics.",
        ],
        "unknownContractFields": unknowns,
        "paritySummary": {
            "referenceTokenizerCorpus": "exact fixture generated",
            "currentSwiftTokenizer": "verified by CurrentModelContractTests when protected vocabulary is available",
            "rawOutputs": "fresh-process absolute tolerance",
            "currentSwiftTransform": "serialized independently and compared with production BertModelWrapper",
        },
        "runtimeRefactorGate": manifest["runtimeRefactorGate"],
    }


def swift_build_input_paths() -> list[str]:
    """Return package-graph and source/resource inputs compiled by the attested commands."""
    paths = ["Package.swift"]
    if (ROOT / "Package.resolved").is_file():
        paths.append("Package.resolved")
    for directory in (ROOT / "Sources", ROOT / "Tests" / "QualiaKitTests"):
        paths.extend(
            str(path.relative_to(ROOT))
            for path in sorted(directory.rglob("*"))
            if path.is_file()
        )
    return sorted(set(paths))


def attested_paths() -> list[str]:
    bundle = f"Tests/Golden/current/{FIXTURE_VERSION}"
    paths = [
        ".github/workflows/ci.yml",
        "Models/current/manifest.json",
        "Models/current/manifest.schema.json",
        "Models/current/MODEL_CARD.md",
        "Tools/ModelContract/reference_inference.py",
        "Tools/ModelContract/coreml_inference.swift",
        "Tools/ModelContract/requirements.lock",
        f"{bundle}/manifest.json",
        f"{bundle}/corpus-v1.json",
        f"{bundle}/fixture-v1.json",
        f"{bundle}/calibration-v1.json",
        f"{bundle}/run-report-v1.json",
        f"{bundle}/index.json",
    ]
    return sorted(set(paths + swift_build_input_paths()))


def checksum_inventory() -> dict[str, Any]:
    bundle = f"Tests/Golden/current/{FIXTURE_VERSION}"
    paths = attested_paths()
    verification = f"{bundle}/verification-v1.json"
    if (ROOT / verification).is_file():
        paths.append(verification)
    return {
        "schemaVersion": 1,
        "algorithm": "SHA-256",
        "excludesSelf": "Models/current/checksums.json",
        "files": {path: sha256_file(ROOT / path) for path in paths},
    }


def fixture_index(directory: Path = GOLDEN_DIRECTORY) -> dict[str, Any]:
    files = {
        path.name: sha256_file(path)
        for path in (
            directory / "manifest.json",
            directory / "corpus-v1.json",
            directory / "fixture-v1.json",
            directory / "calibration-v1.json",
            directory / "run-report-v1.json",
        )
    }
    return {
        "schemaVersion": 1,
        "contractVersion": CONTRACT_VERSION,
        "fixtureVersion": FIXTURE_VERSION,
        "files": files,
    }


def validate_fixture_index() -> None:
    index = read_json(INDEX_PATH)
    expected = fixture_index()
    if index != expected:
        raise ContractError("checksum", "index.json", "versioned fixture index differs from its files")
    if MANIFEST_SNAPSHOT_PATH.read_bytes() != MANIFEST_PATH.read_bytes():
        raise ContractError(
            "immutability", "manifest.json", "versioned manifest snapshot differs from normative manifest"
        )


def resolve_ref(root_schema: dict[str, Any], reference: str) -> dict[str, Any]:
    if not reference.startswith("#/"):
        raise ContractError("schema", "manifest.schema.json", "only local JSON Schema references are supported")
    node: Any = root_schema
    for component in reference[2:].split("/"):
        node = node[component]
    return node


def validate_schema_value(value: Any, schema: dict[str, Any], root_schema: dict[str, Any], path: str) -> None:
    if "$ref" in schema:
        validate_schema_value(value, resolve_ref(root_schema, schema["$ref"]), root_schema, path)
        return
    if "const" in schema and value != schema["const"]:
        raise ContractError("schema", "manifest.json", f"{path} must equal {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        raise ContractError("schema", "manifest.json", f"{path} is outside the allowed enum")
    for keyword, required_matches in (("oneOf", 1), ("anyOf", None)):
        if keyword not in schema:
            continue
        matches = 0
        for branch in schema[keyword]:
            try:
                validate_schema_value(value, branch, root_schema, path)
                matches += 1
            except ContractError:
                pass
        if keyword == "oneOf" and matches != required_matches:
            raise ContractError("schema", "manifest.json", f"{path} must match exactly one schema branch")
        if keyword == "anyOf" and matches == 0:
            raise ContractError("schema", "manifest.json", f"{path} must match at least one schema branch")
    expected_type = schema.get("type")
    type_matches = {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
    }
    if expected_type:
        allowed_types = expected_type if isinstance(expected_type, list) else [expected_type]
        if not any(type_matches.get(candidate, False) for candidate in allowed_types):
            raise ContractError("schema", "manifest.json", f"{path} must be one of {allowed_types}")
    if isinstance(value, dict):
        if len(value) < schema.get("minProperties", 0):
            raise ContractError("schema", "manifest.json", f"{path} has too few properties")
        for key in schema.get("required", []):
            if key not in value:
                raise ContractError("schema", "manifest.json", f"{path}.{key} is required")
        properties = schema.get("properties", {})
        additional = schema.get("additionalProperties", True)
        if additional is False:
            extras = set(value) - set(properties)
            if extras:
                raise ContractError("schema", "manifest.json", f"{path} has unsupported fields {sorted(extras)}")
        for key, child in properties.items():
            if key in value:
                validate_schema_value(value[key], child, root_schema, f"{path}.{key}")
        if isinstance(additional, dict):
            for key in set(value) - set(properties):
                validate_schema_value(value[key], additional, root_schema, f"{path}.{key}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            raise ContractError("schema", "manifest.json", f"{path} has too few items")
        if schema.get("uniqueItems") and len({json.dumps(item, sort_keys=True) for item in value}) != len(value):
            raise ContractError("schema", "manifest.json", f"{path} items must be unique")
        if "items" in schema:
            for index, item in enumerate(value):
                validate_schema_value(item, schema["items"], root_schema, f"{path}[{index}]")
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            raise ContractError("schema", "manifest.json", f"{path} is too short")
        if "pattern" in schema and not re.fullmatch(schema["pattern"], value):
            raise ContractError("schema", "manifest.json", f"{path} has invalid format")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if value < schema.get("minimum", value):
            raise ContractError("schema", "manifest.json", f"{path} is below its minimum")


def validate_manifest_document(manifest: dict[str, Any], schema: dict[str, Any]) -> None:
    """Validate reusable v1 structure and cross-field consistency, without freezing current unknowns."""
    validate_schema_value(manifest, schema, schema, "manifest")
    labels = manifest["outputs"]["labels"]
    label_names = [item["name"] for item in labels]
    if len(label_names) != len(set(label_names)):
        raise ContractError("schema", "manifest.json", "output label names must be unique")

    def has_verified_value(state: Any) -> bool:
        return isinstance(state, dict) and state.get("status") == "verified" and "value" in state

    conditions = manifest["runtimeRefactorGate"]["conditions"]
    actual_states = {
        "labelSemantics": "resolved"
        if all(has_verified_value(item["semanticMeaning"]) for item in labels)
        else "unresolved",
        "outputKind": "resolved"
        if has_verified_value(manifest["outputs"]["kind"])
        else "unresolved",
        "tokenizerTrainingParity": "resolved"
        if all(has_verified_value(manifest["tokenizer"][field])
               for field in ("trainingIdentity", "trainingVersion", "contextPairSupport"))
        else "unresolved",
    }
    provenance_states = [
        manifest["model"][field]
        for field in ("task", "architectureFamily", "license")
    ] + [
        manifest["provenance"][field]
        for field in ("source", "dataset", "domain", "classBalance", "trainingConfiguration")
    ]
    actual_states["provenance"] = (
        "resolved" if all(has_verified_value(state) for state in provenance_states)
        else "unresolved"
    )
    for name, actual in actual_states.items():
        if conditions[name] != actual:
            raise ContractError(
                "gate", "manifest.json", f"{name} is {conditions[name]} but evidence is {actual}"
            )


def validate_manifest() -> dict[str, Any]:
    schema = read_json(SCHEMA_PATH)
    manifest = read_json(MANIFEST_PATH)
    validate_manifest_document(manifest, schema)
    return manifest


def validate_current_contract_instance(manifest: dict[str, Any]) -> None:
    """Validate checksum-bound identity, without preventing later v1 evidence resolution."""
    if manifest["contractVersion"] != CONTRACT_VERSION:
        raise ContractError("identity", "manifest.json", "current contract version mismatch")
    if manifest["model"]["identifier"] != MODEL_IDENTIFIER or manifest["model"]["version"] != MODEL_VERSION:
        raise ContractError("identity", "manifest.json", "current model identity mismatch")
    if manifest["model"]["componentSha256"] != MODEL_COMPONENTS:
        raise ContractError("identity", "manifest.json", "current model component checksums mismatch")
    if manifest["tokenizer"]["vocabularySha256"] != VOCAB_SHA256:
        raise ContractError("identity", "manifest.json", "current vocabulary checksum mismatch")
    if [item["name"] for item in manifest["outputs"]["labels"]] != LABELS:
        raise ContractError("output-contract", "manifest.json", "current label order/space mismatch")


def schema_compatibility_self_test() -> list[str]:
    schema = read_json(SCHEMA_PATH)
    manifest = read_json(MANIFEST_PATH)
    validate_manifest_document(manifest, schema)
    scenarios = ["current-manifest"]

    optional = copy.deepcopy(manifest)
    optional["futureOptionalField"] = {"preservesV1Meaning": True}
    validate_manifest_document(optional, schema)
    scenarios.append("optional-addition")

    resolved = copy.deepcopy(manifest)
    resolved["model"]["license"] = {
        "status": "verified",
        "value": "Apache-2.0",
        "evidence": "checksum-bound primary license record",
    }
    for index, label in enumerate(resolved["outputs"]["labels"]):
        label["semanticMeaning"] = {
            "status": "verified",
            "value": {"canonicalMeaning": f"canonical-meaning-{index}"},
            "evidence": "checksum-bound primary dataset label schema",
        }
        label["productSignal"] = f"verified-signal-{index}"
    resolved["outputs"]["kind"] = {
        "status": "verified",
        "value": "logits",
        "evidence": "reproducible checksum-bound graph extraction",
    }
    resolved["tokenizer"]["trainingIdentity"] = {
        "status": "verified",
        "value": "bert-base-multilingual-cased-tokenizer",
        "evidence": "checksum-bound primary tokenizer record",
    }
    resolved["tokenizer"]["trainingVersion"] = {
        "status": "verified",
        "value": "1.0.0",
        "evidence": "checksum-bound primary tokenizer lockfile",
    }
    resolved["tokenizer"]["contextPairSupport"] = {
        "status": "verified",
        "value": {"mode": "singleText", "template": "[CLS] text [SEP]"},
        "evidence": "checksum-bound primary training input template",
    }
    resolved["model"]["task"] = {
        "status": "verified",
        "value": "sentiment-classification",
        "evidence": "checksum-bound primary model record",
    }
    resolved["model"]["architectureFamily"] = {
        "status": "verified",
        "value": {"family": "BERT", "version": "verified-checkpoint-v1"},
        "evidence": "checksum-bound primary model record",
    }
    sample_sha256 = "0" * 64
    resolved["provenance"]["source"] = {
        "status": "verified",
        "value": {
            "identifier": "primary-model-repository",
            "revision": "verified-revision",
            "artifactSha256": sample_sha256,
        },
        "evidence": "checksum-bound primary source record",
    }
    resolved["provenance"]["dataset"] = {
        "status": "verified",
        "value": {
            "identifier": "primary-training-dataset",
            "version": "verified-version",
            "license": "Apache-2.0",
        },
        "evidence": "checksum-bound primary dataset record",
    }
    resolved["provenance"]["domain"] = {
        "status": "verified",
        "value": ["reviews"],
        "evidence": "checksum-bound primary dataset documentation",
    }
    resolved["provenance"]["classBalance"] = {
        "status": "verified",
        "value": {"split": "train", "countsByLabel": {"LABEL_0": 100}},
        "evidence": "checksum-bound primary dataset statistics",
    }
    resolved["provenance"]["trainingConfiguration"] = {
        "status": "verified",
        "value": {
            "trainingArtifactSha256": sample_sha256,
            "exportArtifactSha256": sample_sha256,
            "environmentLockSha256": sample_sha256,
        },
        "evidence": "checksum-bound primary training and export records",
    }
    resolved["runtimeRefactorGate"]["conditions"] = {
        name: "resolved" for name in (
            "labelSemantics", "outputKind", "provenance", "tokenizerTrainingParity"
        )
    }
    resolved["runtimeRefactorGate"]["status"] = "open"
    validate_manifest_document(resolved, schema)
    scenarios.append("compatible-resolved-evidence")

    def must_reject(mutated: dict[str, Any], name: str) -> None:
        try:
            validate_manifest_document(mutated, schema)
        except ContractError:
            scenarios.append(name)
            return
        raise ContractError("schema-self-test", name, "invalid manifest was accepted")

    unsupported = copy.deepcopy(manifest)
    unsupported["schemaVersion"] = 2
    must_reject(unsupported, "unsupported-schema-version")
    missing = copy.deepcopy(manifest)
    missing.pop("model")
    must_reject(missing, "missing-required-field")
    wrong_type = copy.deepcopy(manifest)
    wrong_type["inputs"]["input_ids"]["shape"] = "1x128"
    must_reject(wrong_type, "incompatible-field-type")
    unknown_without_owner = copy.deepcopy(manifest)
    unknown_without_owner["model"]["license"].pop("owner")
    must_reject(unknown_without_owner, "unknown-without-owner")
    verified_without_value = copy.deepcopy(manifest)
    verified_without_value["model"]["license"] = {
        "status": "verified",
        "evidence": "checksum-bound primary license record",
    }
    must_reject(verified_without_value, "verified-without-value")
    verified_without_evidence = copy.deepcopy(manifest)
    verified_without_evidence["model"]["license"] = {
        "status": "verified",
        "value": "Apache-2.0",
    }
    must_reject(verified_without_evidence, "verified-without-evidence")
    invalid_output_kind = copy.deepcopy(resolved)
    invalid_output_kind["outputs"]["kind"]["value"] = "probably_logits"
    must_reject(invalid_output_kind, "unknown-output-kind")
    labels_without_values = copy.deepcopy(resolved)
    labels_without_values["outputs"]["labels"][0]["semanticMeaning"].pop("value")
    must_reject(labels_without_values, "resolved-label-condition-without-semantic-values")
    tokenizer_without_values = copy.deepcopy(resolved)
    tokenizer_without_values["tokenizer"]["trainingIdentity"].pop("value")
    must_reject(tokenizer_without_values, "resolved-tokenizer-condition-without-contract-values")
    provenance_without_values = copy.deepcopy(resolved)
    provenance_without_values["provenance"]["source"].pop("value")
    must_reject(provenance_without_values, "resolved-provenance-condition-without-structured-values")
    numeric_product_signal = copy.deepcopy(manifest)
    numeric_product_signal["outputs"]["labels"][0]["productSignal"] = 7
    must_reject(numeric_product_signal, "invalid-product-signal-type")
    extra_condition = copy.deepcopy(manifest)
    extra_condition["runtimeRefactorGate"]["conditions"]["futureCondition"] = "unresolved"
    must_reject(extra_condition, "extra-gate-condition")
    open_with_unresolved = copy.deepcopy(manifest)
    open_with_unresolved["runtimeRefactorGate"]["status"] = "open"
    must_reject(open_with_unresolved, "open-with-unresolved-condition")
    return scenarios


def validate_integrity_inventory(
    inventory: dict[str, Any] | None = None, root: Path = ROOT
) -> None:
    inventory = inventory if inventory is not None else read_json(CHECKSUMS_PATH)
    if inventory.get("schemaVersion") != 1 or inventory.get("algorithm") != "SHA-256":
        raise ContractError("checksum", "checksums.json", "unsupported checksum inventory")
    for relative, expected in inventory.get("files", {}).items():
        path = root / relative
        if not path.is_file():
            raise ContractError("checksum", relative, "declared file is missing")
        actual = sha256_file(path)
        if actual != expected:
            raise ContractError("checksum", relative, f"expected {expected}, observed {actual}")


def validate_fixture_structure(golden: dict[str, Any], corpus: dict[str, Any], manifest: dict[str, Any]) -> None:
    required_case_fields = {
        "id", "contractVersion", "fixtureVersion", "modelIdentifier", "modelVersion", "inputMetadata",
        "tokens", "inputIds", "attentionMask", "tokenTypeIds", "preTruncationTokenCount", "wasTruncated",
        "rawOutputs", "predictedLabel", "transformedScores", "currentSwiftTransform", "finalSemanticMapping",
    }
    if golden.get("caseCount") != corpus["caseCount"] or len(golden.get("cases", [])) != corpus["caseCount"]:
        raise ContractError("serialization", "fixture-v1.json", "case count is incomplete")
    for case in golden["cases"]:
        if set(case) != required_case_fields:
            raise ContractError("serialization", case.get("id", "case"), "fixture fields are incomplete or unknown")
        if any(len(case[field]) != 128 for field in ("tokens", "inputIds", "attentionMask", "tokenTypeIds")):
            raise ContractError("serialization", case["id"], "token tensors must contain exactly 128 elements")
        if set(case["rawOutputs"]) != set(LABELS) or set(case["transformedScores"]["stableSoftmax"]) != set(LABELS):
            raise ContractError("serialization", case["id"], "five-label outputs are incomplete")
        values = list(case["rawOutputs"].values()) + list(case["transformedScores"]["stableSoftmax"].values())
        values.append(case["currentSwiftTransform"]["value"])
        if not all(isinstance(value, (int, float)) and math.isfinite(value) for value in values):
            raise ContractError("serialization", case["id"], "floating outputs must be finite")
        if case["finalSemanticMapping"] != {
            "status": "unknown", "productSignal": None, "reason": "no primary label-semantics evidence"
        }:
            raise ContractError("semantics", case["id"], "fixture invented a product-facing semantic mapping")
        for key, expected in (("contractVersion", CONTRACT_VERSION), ("fixtureVersion", FIXTURE_VERSION),
                              ("modelIdentifier", MODEL_IDENTIFIER), ("modelVersion", MODEL_VERSION)):
            if case[key] != expected:
                raise ContractError("identity", case["id"], f"{key} mismatch")
    if manifest["fixture"]["goldenSha256"] != sha256_file(GOLDEN_PATH):
        raise ContractError("checksum", "fixture-v1.json", "manifest golden checksum mismatch")


def compare_regenerated_fixture(
    committed: dict[str, Any], regenerated: dict[str, Any], tolerances: dict[str, float]
) -> None:
    top_level_discrete = (
        "schemaVersion",
        "contractVersion",
        "fixtureVersion",
        "modelIdentifier",
        "modelVersion",
        "corpusSha256",
        "caseCount",
        "generatedBy",
    )
    for field in top_level_discrete:
        if committed.get(field) != regenerated.get(field):
            raise ContractError(
                "regeneration", f"fixture-v1.json.{field}", "discrete value differs"
            )
    expected_cases = committed.get("cases", [])
    actual_cases = regenerated.get("cases", [])
    if len(expected_cases) != len(actual_cases):
        raise ContractError("regeneration", "fixture-v1.json.cases", "case count differs")

    floating_sections = {"rawOutputs", "transformedScores", "currentSwiftTransform"}
    for expected, actual in zip(expected_cases, actual_cases, strict=True):
        case_id = expected.get("id", "unknown")
        expected_discrete = {key: value for key, value in expected.items() if key not in floating_sections}
        actual_discrete = {key: value for key, value in actual.items() if key not in floating_sections}
        if expected_discrete != actual_discrete:
            differing = sorted(
                key for key in set(expected_discrete) | set(actual_discrete)
                if expected_discrete.get(key) != actual_discrete.get(key)
            )
            field = differing[0] if differing else "case"
            raise ContractError(
                "regeneration", f"fixture-v1.json.cases[{case_id}].{field}", "discrete value differs"
            )

        expected_transform = dict(expected["currentSwiftTransform"])
        actual_transform = dict(actual["currentSwiftTransform"])
        expected_value = float(expected_transform.pop("value"))
        actual_value = float(actual_transform.pop("value"))
        if expected_transform != actual_transform:
            raise ContractError(
                "regeneration",
                f"fixture-v1.json.cases[{case_id}].currentSwiftTransform",
                "discrete transform metadata differs",
            )

        comparisons = [("currentSwiftTransform.value", expected_value, actual_value)]
        for label in LABELS:
            comparisons.append((
                f"rawOutputs.{label}",
                float(expected["rawOutputs"][label]),
                float(actual["rawOutputs"][label]),
            ))
            comparisons.append((
                f"stableSoftmax.{label}",
                float(expected["transformedScores"]["stableSoftmax"][label]),
                float(actual["transformedScores"]["stableSoftmax"][label]),
            ))
        for field, expected_float, actual_float in comparisons:
            tolerance = float(tolerances[field])
            delta = abs(actual_float - expected_float)
            if not math.isfinite(actual_float) or delta > tolerance:
                raise ContractError(
                    "regeneration",
                    f"fixture-v1.json.cases[{case_id}].{field}",
                    f"absolute delta {delta!r} exceeds tolerance {tolerance!r}",
                )


def regeneration_comparator_self_test() -> list[str]:
    committed = read_json(GOLDEN_PATH)
    tolerances = {
        field: 1.0
        for field in floating_values({
            "rawOutputs": committed["cases"][0]["rawOutputs"],
            "currentSwiftTransformValue": committed["cases"][0]["currentSwiftTransform"]["value"],
        })
    }

    at_tolerance = copy.deepcopy(committed)
    at_tolerance["cases"][0]["rawOutputs"]["LABEL_0"] += 1.0
    compare_regenerated_fixture(committed, at_tolerance, tolerances)

    discrete = copy.deepcopy(committed)
    discrete["cases"][0]["attentionMask"][0] = 0
    try:
        compare_regenerated_fixture(committed, discrete, tolerances)
    except ContractError as error:
        if "attentionMask" not in str(error):
            raise
    else:
        raise ContractError("comparator-self-test", "discrete", "discrete mismatch was accepted")

    over_tolerance = copy.deepcopy(committed)
    over_tolerance["cases"][0]["rawOutputs"]["LABEL_0"] += 1.000001
    try:
        compare_regenerated_fixture(committed, over_tolerance, tolerances)
    except ContractError as error:
        if "delta" not in str(error) or "tolerance" not in str(error):
            raise
    else:
        raise ContractError("comparator-self-test", "floating", "over-tolerance delta was accepted")

    return ["discrete-mismatch-rejected", "float-at-tolerance-accepted", "float-over-tolerance-rejected"]


def validate_calibration(calibration: dict[str, Any], golden: dict[str, Any], manifest: dict[str, Any]) -> None:
    calibration_runs = calibration.get("calibrationRuns", [])
    holdout_runs = calibration.get("holdoutRuns", [])
    if len(calibration_runs) < 10 or len(holdout_runs) < 5:
        raise ContractError("calibration", "calibration-v1.json", "insufficient fresh processes")
    sequences = [run.get("processSequence") for run in calibration_runs + holdout_runs]
    if len(set(sequences)) != len(sequences) or sequences != sorted(sequences):
        raise ContractError("calibration", "calibration-v1.json", "process sequences overlap or are unordered")
    all_runs = calibration_runs + holdout_runs
    process_identifiers = [run.get("processIdentifier") for run in all_runs]
    if (not all(isinstance(identifier, int) and identifier > 0 for identifier in process_identifiers)
            or len(set(process_identifiers)) != len(process_identifiers)):
        raise ContractError("calibration", "calibration-v1.json", "fresh process identifiers are missing or reused")
    if not all(run.get("freshOSProcess") is True for run in calibration_runs + holdout_runs):
        raise ContractError("calibration", "calibration-v1.json", "every sample must be a fresh OS process")
    expected_compute_units = calibration.get("environment", {}).get("computeUnits")
    if expected_compute_units != "cpuOnly" or not all(
        run.get("computeUnits") == expected_compute_units for run in all_runs
    ):
        raise ContractError("calibration", "calibration-v1.json", "fresh processes must use the pinned CPU-only policy")
    expected_helper_source = sha256_file(HELPER_PATH)
    if not all(
        run.get("helperSourceSha256") == expected_helper_source
        and isinstance(run.get("helperExecutableSha256"), str)
        and len(run["helperExecutableSha256"]) == 64
        and run.get("privateCompilationDirectory") is True
        and isinstance(run.get("privateCompilationIdentifier"), str)
        and len(run["privateCompilationIdentifier"]) == 32
        for run in all_runs
    ):
        raise ContractError("calibration", "calibration-v1.json", "reference helper provenance is incomplete")
    compilation_identifiers = [run["privateCompilationIdentifier"] for run in all_runs]
    if len(set(compilation_identifiers)) != len(compilation_identifiers):
        raise ContractError("calibration", "calibration-v1.json", "private compilation was reused across samples")
    protocol = calibration.get("protocol", {})
    if (
        protocol.get("modelRecompiledEachProcess") is not True
        or protocol.get("privateCompilationPerProcess") is not True
    ):
        raise ContractError("calibration", "calibration-v1.json", "per-process private compilation is not declared")
    for earlier, later in zip(all_runs, all_runs[1:]):
        if earlier.get("endedMonotonicSeconds", math.inf) > later.get("startedMonotonicSeconds", -math.inf):
            raise ContractError("calibration", "calibration-v1.json", "fresh process intervals overlap")
    for run in all_runs:
        if not math.isclose(
            run.get("endedMonotonicSeconds", 0) - run.get("startedMonotonicSeconds", 0),
            run.get("durationSeconds", -1), rel_tol=0, abs_tol=1e-12,
        ):
            raise ContractError("calibration", "calibration-v1.json", "process duration does not match its interval")
    baseline = [{"id": case["id"], "rawOutputs": case["rawOutputs"],
                 "predictedLabel": case["predictedLabel"]} for case in golden["cases"]]
    expected_reference_cases = [{
        "id": item["id"], "floatingValues": floating_values(item)
    } for item in baseline]
    if calibration.get("referenceCases") != expected_reference_cases:
        raise ContractError("calibration", "calibration-v1.json", "stored reference values do not match the golden raw outputs")
    combined: dict[str, list[float]] = {field: [] for field in floating_values(baseline[0])}
    for run in calibration_runs:
        for item in run["cases"]:
            if item.get("floatingValues") != floating_values(item):
                raise ContractError("calibration", item.get("id", "case"), "stored floating values do not match raw process evidence")
        deltas = compare_run(baseline, run["cases"])
        for field, values in deltas.items():
            combined[field].extend(values)
    recomputed = {field: distribution(values) for field, values in combined.items()}
    if recomputed != calibration.get("distributions"):
        raise ContractError("calibration", "calibration-v1.json", "stored distributions do not match raw process evidence")
    tolerances = {field: values["max"] for field, values in recomputed.items()}
    if tolerances != calibration.get("absoluteToleranceByField"):
        raise ContractError("calibration", "calibration-v1.json", "tolerance is not the calibration maximum")
    published_tolerances = manifest["floatingPointTolerance"]["absoluteByField"]
    if any(published_tolerances.get(field) != value for field, value in tolerances.items()):
        raise ContractError("calibration", "manifest.json", "published reference tolerance differs from calibration")
    for run in holdout_runs:
        for item in run["cases"]:
            if item.get("floatingValues") != floating_values(item):
                raise ContractError("holdout", item.get("id", "case"), "stored floating values do not match raw process evidence")
        deltas = compare_run(baseline, run["cases"])
        maxima = {field: max(values) for field, values in deltas.items()}
        if maxima != run.get("maximumDeltaByField") or not all(maxima[field] <= tolerances[field] for field in tolerances):
            raise ContractError("holdout", "calibration-v1.json", "fresh-process holdout exceeded fixed tolerance")
    validate_current_runtime_calibration(
        calibration.get("currentSwiftRuntimeDefault"), golden, manifest
    )


def validate_current_runtime_calibration(
    runtime: Any, golden: dict[str, Any], manifest: dict[str, Any]
) -> None:
    if not isinstance(runtime, dict):
        raise ContractError("calibration", "calibration-v1.json", "production runtime calibration is missing")
    calibration_runs = runtime.get("calibrationRuns", [])
    holdout_runs = runtime.get("holdoutRuns", [])
    if len(calibration_runs) < 10 or len(holdout_runs) < 5:
        raise ContractError("calibration", "BertModelWrapper", "insufficient fresh runtime processes")
    all_runs = calibration_runs + holdout_runs
    sequences = [run.get("processSequence") for run in all_runs]
    identifiers = [run.get("processIdentifier") for run in all_runs]
    if sequences != sorted(sequences) or len(set(sequences)) != len(sequences):
        raise ContractError("calibration", "BertModelWrapper", "runtime process sequence is invalid")
    if not all(isinstance(identifier, int) and identifier > 0 for identifier in identifiers):
        raise ContractError("calibration", "BertModelWrapper", "runtime process identifier is missing")
    if len(set(identifiers)) != len(identifiers):
        raise ContractError("calibration", "BertModelWrapper", "runtime process was reused")
    source_sha = sha256_file(CURRENT_RUNTIME_SOURCE_PATH)
    test_harness_sha = sha256_file(CURRENT_RUNTIME_TEST_PATH)
    if not all(
        run.get("freshOSProcess") is True
        and run.get("computeUnits") == "production-default"
        and run.get("productionSourceSha256") == source_sha
        and run.get("testHarnessSourceSha256") == test_harness_sha
        and run.get("invocation")
        == "swift test --filter CurrentModelContractTests/testCurrentSwiftRuntimeMatchesCommittedIndependentGolden"
        for run in all_runs
    ):
        raise ContractError("calibration", "BertModelWrapper", "runtime provenance is incomplete")
    for earlier, later in zip(all_runs, all_runs[1:]):
        if earlier.get("endedMonotonicSeconds", math.inf) > later.get("startedMonotonicSeconds", -math.inf):
            raise ContractError("calibration", "BertModelWrapper", "runtime process intervals overlap")
    reference = {
        case["id"]: float(case["currentSwiftTransform"]["value"])
        for case in golden["cases"]
    }
    expected_reference = [{"id": identifier, "value": value} for identifier, value in reference.items()]
    if runtime.get("referenceCases") != expected_reference:
        raise ContractError("calibration", "BertModelWrapper", "runtime reference differs from golden")

    def run_deltas(run: dict[str, Any]) -> list[float]:
        cases = run.get("cases", [])
        if [item.get("id") for item in cases] != list(reference):
            raise ContractError("calibration", "BertModelWrapper", "runtime case identity/order mismatch")
        values = []
        for item in cases:
            value = item.get("value")
            if not isinstance(value, (int, float)) or not math.isfinite(value):
                raise ContractError("calibration", item.get("id", "case"), "invalid runtime value")
            values.append(abs(float(value) - reference[item["id"]]))
        return values

    observed = [delta for run in calibration_runs for delta in run_deltas(run)]
    measured = distribution(observed)
    tolerance = measured["max"]
    if runtime.get("distribution") != measured or runtime.get("absoluteTolerance") != tolerance:
        raise ContractError("calibration", "BertModelWrapper", "runtime tolerance is not the measured maximum")
    if manifest["floatingPointTolerance"]["absoluteByField"].get(
        "currentSwiftRuntimeDefault.value"
    ) != tolerance:
        raise ContractError("calibration", "manifest.json", "published runtime tolerance differs")
    for run in holdout_runs:
        maximum = max(run_deltas(run))
        if run.get("maximumDelta") != maximum or run.get("withinFixedTolerance") is not True:
            raise ContractError("holdout", "BertModelWrapper", "runtime holdout evidence is inconsistent")
        if maximum > tolerance:
            raise ContractError("holdout", "BertModelWrapper", "runtime holdout exceeded fixed tolerance")


def run_failure_probe(name: str, model_path: Path, vocab_path: Path) -> None:
    if name == "missing-model-component":
        with tempfile.TemporaryDirectory(prefix="qualia-probe-model-") as directory:
            validate_model_assets(Path(directory))
        return
    if name == "vocabulary-checksum":
        with tempfile.TemporaryDirectory(prefix="qualia-probe-vocab-") as directory:
            mutated = Path(directory) / "vocab.txt"
            mutated.write_text("tampered\n", encoding="utf-8")
            validate_vocabulary_asset(mutated)
        return
    if name == "unsupported-schema":
        schema = read_json(SCHEMA_PATH)
        manifest = read_json(MANIFEST_PATH)
        manifest["schemaVersion"] = 999
        validate_schema_value(manifest, schema, schema, "manifest")
        return
    if name == "incomplete-fixture":
        golden = copy.deepcopy(read_json(GOLDEN_PATH))
        golden["cases"][0].pop("tokenTypeIds")
        validate_fixture_structure(golden, read_json(CORPUS_PATH), read_json(MANIFEST_PATH))
        return
    if name == "checksum-inventory":
        inventory = copy.deepcopy(read_json(CHECKSUMS_PATH))
        first = next(iter(inventory["files"]))
        inventory["files"][first] = "0" * 64
        validate_integrity_inventory(inventory)
        return
    if name == "holdout-overrun":
        calibration = copy.deepcopy(read_json(CALIBRATION_PATH))
        item = calibration["holdoutRuns"][0]["cases"][0]
        item["rawOutputs"]["LABEL_0"] += 1.0
        item["floatingValues"] = floating_values(item)
        validate_calibration(calibration, read_json(GOLDEN_PATH), read_json(MANIFEST_PATH))
        return
    if name == "published-overwrite":
        generate(model_path, vocab_path)
        return
    raise ContractError("probe", name, "unknown failure probe")


def verify(model_path: Path, vocab_path: Path) -> dict[str, Any]:
    validate_integrity_inventory()
    validate_fixture_index()
    validate_assets(model_path, vocab_path)
    environment = validate_environment()
    manifest = validate_manifest()
    validate_current_contract_instance(manifest)
    corpus = read_json(CORPUS_PATH)
    expected_corpus = build_corpus()
    if canonical_bytes(corpus) != canonical_bytes(expected_corpus):
        raise ContractError("immutability", "corpus-v1.json", "corpus differs from the deterministic sanitized source")
    if manifest["fixture"]["corpusSha256"] != sha256_file(CORPUS_PATH):
        raise ContractError("checksum", "corpus-v1.json", "manifest corpus checksum mismatch")
    tokenizer = ReferenceTokenizer(vocab_path)
    tokenized = make_tokenized_cases(corpus, tokenizer)
    golden = read_json(GOLDEN_PATH)
    validate_fixture_structure(golden, corpus, manifest)
    for expected, actual in zip(golden["cases"], tokenized, strict=True):
        if expected["id"] != actual["id"]:
            raise ContractError("tokenizer", "fixture-v1.json", "case order mismatch")
        for field in ("tokens", "inputIds", "attentionMask", "tokenTypeIds", "preTruncationTokenCount", "wasTruncated"):
            if expected[field] != actual[field]:
                raise ContractError("tokenizer-parity", expected["id"], f"exact {field} mismatch")
    calibration = read_json(CALIBRATION_PATH)
    validate_calibration(calibration, golden, manifest)

    observed, execution = run_fresh_compilation(model_path, tokenized)
    tolerances = manifest["floatingPointTolerance"]["absoluteByField"]
    regenerated = make_golden(corpus, tokenized, observed)
    compare_regenerated_fixture(golden, regenerated, tolerances)
    comparator_scenarios = regeneration_comparator_self_test()
    baseline = [{"id": case["id"], "rawOutputs": case["rawOutputs"],
                 "predictedLabel": case["predictedLabel"]} for case in golden["cases"]]
    deltas = compare_run(baseline, observed)
    maxima = {field: max(values) for field, values in deltas.items()}
    exceeded = {field: value for field, value in maxima.items() if value > tolerances[field]}
    if exceeded:
        raise ContractError("inference-parity", "current-model", f"fresh process exceeded calibrated fields {sorted(exceeded)}")
    runtime_cases, runtime_execution = run_current_swift_runtime(model_path, tokenized)
    runtime_expected = {
        case["id"]: float(case["currentSwiftTransform"]["value"])
        for case in golden["cases"]
    }
    runtime_maximum = max(
        abs(float(case["value"]) - runtime_expected[case["id"]]) for case in runtime_cases
    )
    runtime_tolerance = tolerances["currentSwiftRuntimeDefault.value"]
    if runtime_maximum > runtime_tolerance:
        raise ContractError(
            "runtime-parity",
            "BertModelWrapper",
            f"absolute delta {runtime_maximum!r} exceeds tolerance {runtime_tolerance!r}",
        )
    for item in observed:
        softmax = stable_softmax(item["rawOutputs"])
        if not math.isclose(sum(softmax.values()), 1.0, abs_tol=1e-12):
            raise ContractError("transform", item["id"], "stable softmax is not normalized")
        if item["predictedLabel"] != max(LABELS, key=lambda label: item["rawOutputs"][label]):
            raise ContractError("output-kind", item["id"], "classifier label does not match raw-score argmax")
    stored_report = read_json(RUN_REPORT_PATH)
    if stored_report["checksums"]["manifestSha256"] != sha256_file(MANIFEST_PATH):
        raise ContractError("checksum", "run-report-v1.json", "run report manifest checksum mismatch")
    return {
        "schemaVersion": 1,
        "status": "passed",
        "contractVersion": CONTRACT_VERSION,
        "fixtureVersion": FIXTURE_VERSION,
        "modelIdentifier": MODEL_IDENTIFIER,
        "modelVersion": MODEL_VERSION,
        "caseCount": corpus["caseCount"],
        "freshProcessExecution": execution,
        "currentSwiftRuntimeExecution": runtime_execution,
        "maximumDeltaByField": maxima,
        "currentSwiftRuntimeMaximumDelta": runtime_maximum,
        "fixtureRegeneration": {
            "discreteFields": "exact",
            "floatingFields": "manifest absolute tolerance",
            "scenarios": comparator_scenarios,
        },
        "checksums": stored_report["checksums"],
        "environment": environment,
        "runtimeRefactorGate": manifest["runtimeRefactorGate"],
    }


def generate(model_path: Path, vocab_path: Path) -> dict[str, Any]:
    if GOLDEN_DIRECTORY.exists():
        raise ContractError(
            "immutability", FIXTURE_VERSION, "refusing to overwrite a published fixture version"
        )
    validate_assets(model_path, vocab_path)
    environment = validate_environment()
    GOLDEN_ROOT.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{FIXTURE_VERSION}-staging-", dir=GOLDEN_ROOT))
    staged_corpus = staging / "corpus-v1.json"
    staged_golden = staging / "fixture-v1.json"
    staged_calibration = staging / "calibration-v1.json"
    staged_report = staging / "run-report-v1.json"
    staged_manifest = staging / "manifest.json"
    staged_index = staging / "index.json"
    try:
        corpus = build_corpus()
        write_generated_json(staged_corpus, corpus)
        tokenizer = ReferenceTokenizer(vocab_path)
        tokenization_started = time.monotonic()
        tokenized = make_tokenized_cases(corpus, tokenizer)
        tokenization_duration = time.monotonic() - tokenization_started
        baseline_raw, baseline_execution = run_fresh_compilation(model_path, tokenized)
        transform_started = time.monotonic()
        golden = make_golden(corpus, tokenized, baseline_raw, staged_corpus)
        transform_duration = time.monotonic() - transform_started
        write_generated_json(staged_golden, golden)
        reference_baseline = [{
            "id": item["id"],
            "predictedLabel": item["predictedLabel"],
            "rawOutputs": item["rawOutputs"],
        } for item in baseline_raw]
        calibration = calibrate(model_path, tokenized, reference_baseline, environment)
        write_generated_json(staged_calibration, calibration)
        manifest = update_manifest(
            calibration, staged_corpus, staged_golden, staged_calibration, write=False
        )
        schema = read_json(SCHEMA_PATH)
        validate_schema_value(manifest, schema, schema, "manifest")
        write_generated_json(staged_manifest, manifest)
        report = build_run_report(
            environment,
            {
                "tokenizationCorpus": tokenization_duration,
                "baselineInferenceCorpus": baseline_execution["durationSeconds"],
                "transformCorpus": transform_duration,
            },
            baseline_execution,
            manifest,
            corpus,
            staged_manifest,
            staged_corpus,
            staged_golden,
            staged_calibration,
        )
        write_generated_json(staged_report, report)
        write_generated_json(staged_index, fixture_index(staging))
        os.replace(staging, GOLDEN_DIRECTORY)
        write_generated_json(MANIFEST_PATH, manifest)
        write_generated_json(CHECKSUMS_PATH, checksum_inventory())
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    return {
        "status": "generated",
        "caseCount": corpus["caseCount"],
        "calibrationProcessCount": calibration["calibrationProcessCount"],
        "holdoutProcessCount": calibration["holdoutProcessCount"],
        "absoluteToleranceByField": calibration["absoluteToleranceByField"],
    }


def run_recorded_command(command: str, arguments: list[str], environment: dict[str, str]) -> dict[str, Any]:
    started = time.monotonic()
    try:
        result = subprocess.run(
            arguments,
            cwd=ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=1800,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ContractError("attestation", command, str(error)) from error
    duration = time.monotonic() - started
    output = result.stdout or ""
    if result.returncode != 0:
        diagnostic = output.strip().splitlines()[-1] if output.strip() else "command failed"
        raise ContractError("attestation", command, diagnostic[:400])
    return {
        "command": command,
        "status": "passed",
        "exitCode": result.returncode,
        "durationSeconds": duration,
        "outputSha256": sha256_bytes(output.encode()),
    }


def record_verification_evidence(model_path: Path, vocab_path: Path) -> dict[str, Any]:
    """Run all declared commands with protected assets and publish only checksum-bound metadata."""
    validate_assets(model_path, vocab_path)
    environment_record = validate_environment()
    write_generated_json(CHECKSUMS_PATH, checksum_inventory())
    with tempfile.TemporaryDirectory(prefix="qualia-contract-attestation-") as directory:
        command_environment = dict(os.environ)
        command_environment["QUALIAKIT_TEST_MODEL_PATH"] = str(model_path)
        command_environment["QUALIAKIT_TEST_VOCAB_PATH"] = str(vocab_path)
        command_environment["CLANG_MODULE_CACHE_PATH"] = str(Path(directory) / "clang-module-cache")
        command_environment["SWIFT_MODULECACHE_PATH"] = str(Path(directory) / "swift-module-cache")
        commands = [
            run_recorded_command("swift build", ["swift", "build"], command_environment),
            run_recorded_command(
                "swift test --filter CurrentModelContractTests",
                ["swift", "test", "--filter", "CurrentModelContractTests"],
                command_environment,
            ),
            run_recorded_command(
                "python3 Tools/ModelContract/reference_inference.py --verify",
                [sys.executable, str(Path(__file__).resolve()), "--verify"],
                command_environment,
            ),
        ]
    files = {path: sha256_file(ROOT / path) for path in attested_paths()}
    swift_build_inputs = {
        path: files[path]
        for path in swift_build_input_paths()
    }
    evidence: dict[str, Any] = {
        "schemaVersion": 1,
        "status": "passed",
        "kind": "checksum-bound-protected-local-verification",
        "generatedAtUTC": datetime.datetime.now(datetime.UTC).isoformat(),
        "contractVersion": CONTRACT_VERSION,
        "fixtureVersion": FIXTURE_VERSION,
        "assetPolicy": {
            "modelEnvironmentVariable": "QUALIAKIT_TEST_MODEL_PATH",
            "vocabularyEnvironmentVariable": "QUALIAKIT_TEST_VOCAB_PATH",
            "protectedBytesCommitted": False,
            "protectedBytesEmbeddedInPublicCI": False,
        },
        "protectedAssets": {
            "modelPackageIdentitySha256": package_identity_sha256(),
            "modelComponents": MODEL_COMPONENTS,
            "vocabularySha256": VOCAB_SHA256,
        },
        "environment": environment_record,
        "commands": commands,
        "attestedFiles": files,
        "sourceClosureSha256": sha256_bytes(canonical_bytes(files)),
        "swiftBuildInputs": swift_build_inputs,
        "swiftBuildInputClosureSha256": sha256_bytes(canonical_bytes(swift_build_inputs)),
    }
    evidence["evidenceClosureSha256"] = sha256_bytes(canonical_bytes(evidence))
    write_generated_json(VERIFICATION_EVIDENCE_PATH, evidence)
    write_generated_json(CHECKSUMS_PATH, checksum_inventory())
    return verify_committed_evidence()


def verify_committed_evidence() -> dict[str, Any]:
    """Validate protected-run evidence without requiring protected assets on the current runner."""
    observed_environment = validate_environment()
    validate_integrity_inventory()
    validate_fixture_index()
    manifest = validate_manifest()
    validate_current_contract_instance(manifest)
    corpus = read_json(CORPUS_PATH)
    golden = read_json(GOLDEN_PATH)
    validate_fixture_structure(golden, corpus, manifest)
    validate_calibration(read_json(CALIBRATION_PATH), golden, manifest)
    evidence = read_json(VERIFICATION_EVIDENCE_PATH)
    if evidence.get("schemaVersion") != 1 or evidence.get("status") != "passed":
        raise ContractError("attestation", "verification-v1.json", "unsupported or failing evidence")
    expected_commands = [
        "swift build",
        "swift test --filter CurrentModelContractTests",
        "python3 Tools/ModelContract/reference_inference.py --verify",
    ]
    commands = evidence.get("commands", [])
    if [item.get("command") for item in commands] != expected_commands or not all(
        item.get("status") == "passed"
        and item.get("exitCode") == 0
        and isinstance(item.get("outputSha256"), str)
        and re.fullmatch(r"[0-9a-f]{64}", item["outputSha256"])
        for item in commands
    ):
        raise ContractError("attestation", "verification-v1.json", "declared command evidence is incomplete")
    expected_assets = {
        "modelPackageIdentitySha256": package_identity_sha256(),
        "modelComponents": MODEL_COMPONENTS,
        "vocabularySha256": VOCAB_SHA256,
    }
    if evidence.get("protectedAssets") != expected_assets:
        raise ContractError("attestation", "verification-v1.json", "protected asset identity mismatch")
    expected_policy = {
        "modelEnvironmentVariable": "QUALIAKIT_TEST_MODEL_PATH",
        "vocabularyEnvironmentVariable": "QUALIAKIT_TEST_VOCAB_PATH",
        "protectedBytesCommitted": False,
        "protectedBytesEmbeddedInPublicCI": False,
    }
    if evidence.get("assetPolicy") != expected_policy:
        raise ContractError("attestation", "verification-v1.json", "protected asset policy mismatch")
    files = {path: sha256_file(ROOT / path) for path in attested_paths()}
    if evidence.get("attestedFiles") != files:
        raise ContractError("attestation", "verification-v1.json", "attested source closure changed")
    if evidence.get("sourceClosureSha256") != sha256_bytes(canonical_bytes(files)):
        raise ContractError("attestation", "verification-v1.json", "source closure digest mismatch")
    swift_build_inputs = {
        path: files[path]
        for path in swift_build_input_paths()
    }
    if evidence.get("swiftBuildInputs") != swift_build_inputs:
        raise ContractError("attestation", "verification-v1.json", "Swift build input closure changed")
    if evidence.get("swiftBuildInputClosureSha256") != sha256_bytes(canonical_bytes(swift_build_inputs)):
        raise ContractError("attestation", "verification-v1.json", "Swift build input digest mismatch")
    closure = dict(evidence)
    declared_closure = closure.pop("evidenceClosureSha256", None)
    if declared_closure != sha256_bytes(canonical_bytes(closure)):
        raise ContractError("attestation", "verification-v1.json", "evidence closure digest mismatch")
    recorded_environment = evidence.get("environment", {})
    if (
        recorded_environment.get("python") != PINNED_PYTHON_VERSION_STRING
        or "6.3.3" not in recorded_environment.get("swift", "")
        or recorded_environment.get("xcode") != "Xcode 26.6"
        or recorded_environment.get("coremlcompiler") != "3520.5.1"
    ):
        raise ContractError("attestation", "verification-v1.json", "recorded toolchain differs from lock")
    return {
        "schemaVersion": 1,
        "status": "passed",
        "mode": "asset-free-checksum-bound-evidence",
        "contractVersion": CONTRACT_VERSION,
        "fixtureVersion": FIXTURE_VERSION,
        "caseCount": corpus["caseCount"],
        "sourceClosureSha256": evidence["sourceClosureSha256"],
        "evidenceClosureSha256": evidence["evidenceClosureSha256"],
        "currentEnvironment": observed_environment,
        "recordedEnvironment": recorded_environment,
        "commands": expected_commands,
    }


def asset_paths(arguments: argparse.Namespace) -> tuple[Path, Path]:
    model = arguments.model_path or os.environ.get("QUALIAKIT_TEST_MODEL_PATH")
    vocab = arguments.vocab_path or os.environ.get("QUALIAKIT_TEST_VOCAB_PATH")
    if not model:
        raise ContractError("environment", "QUALIAKIT_TEST_MODEL_PATH", "required variable is missing")
    if not vocab:
        raise ContractError("environment", "QUALIAKIT_TEST_VOCAB_PATH", "required variable is missing")
    return Path(model), Path(vocab)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    operation = parser.add_mutually_exclusive_group(required=True)
    operation.add_argument("--verify", action="store_true", help="read-only contract verification")
    operation.add_argument("--generate", action="store_true", help="maintainer-only immutable fixture generation")
    operation.add_argument(
        "--verify-committed-evidence",
        action="store_true",
        help="asset-free validation of checksum-bound protected-run evidence",
    )
    operation.add_argument("--record-verification-evidence", action="store_true", help=argparse.SUPPRESS)
    operation.add_argument("--schema-self-test", action="store_true", help=argparse.SUPPRESS)
    operation.add_argument("--comparator-self-test", action="store_true", help=argparse.SUPPRESS)
    operation.add_argument("--probe-error", choices=PROBE_ERRORS, help=argparse.SUPPRESS)
    parser.add_argument("--model-path", help=argparse.SUPPRESS)
    parser.add_argument("--vocab-path", help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    try:
        if arguments.schema_self_test:
            print(json.dumps({"status": "passed", "scenarios": schema_compatibility_self_test()}, sort_keys=True))
            return 0
        if arguments.comparator_self_test:
            print(json.dumps({"status": "passed", "scenarios": regeneration_comparator_self_test()}, sort_keys=True))
            return 0
        if arguments.verify_committed_evidence:
            print(json.dumps(verify_committed_evidence(), indent=2, sort_keys=True))
            return 0
        model_path, vocab_path = asset_paths(arguments)
        bootstrap_pinned_python()
        if arguments.probe_error:
            run_failure_probe(arguments.probe_error, model_path, vocab_path)
            raise ContractError("probe", arguments.probe_error, "mutation was incorrectly accepted")
        if arguments.record_verification_evidence:
            result = record_verification_evidence(model_path, vocab_path)
        else:
            result = verify(model_path, vocab_path) if arguments.verify else generate(model_path, vocab_path)
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except ContractError as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
