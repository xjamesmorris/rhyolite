#!/usr/bin/env python3

from __future__ import annotations

import ast
import contextlib
import copy
import dataclasses
import hashlib
import importlib.util
import io
import json
import os
import pathlib
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.parse
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
PLUGIN_ROOT = ROOT / "plugins/rhyolite"
BROKER_PATH = (
    PLUGIN_ROOT
    / "skills/readonly-repository-review/scripts"
    / "research-egress-broker.py"
)
POLICY_PATH = (
    PLUGIN_ROOT
    / "skills/readonly-repository-review"
    / "research-policy.json"
)
EVENT_INTEGER_CONTRACT_PATH = (
    PLUGIN_ROOT
    / "skills/readonly-repository-review"
    / "research-event-integers.json"
)
OUTPUT_HELPER = (
    PLUGIN_ROOT
    / "skills/readonly-repository-review/scripts/review-output.sh"
)
COPILOT_ADAPTER = PLUGIN_ROOT / "lib/harness/copilot.sh"
CLAUDE_ADAPTER = PLUGIN_ROOT / "lib/harness/claude.sh"
HARNESS_COMMON = PLUGIN_ROOT / "lib/harness/common.sh"
RUNNER = (
    PLUGIN_ROOT
    / "skills/readonly-repository-review/scripts/run-parallel-reviews.sh"
)
BROKER_LAUNCHER = (
    PLUGIN_ROOT
    / "skills/readonly-repository-review/scripts"
    / "launch-research-egress-broker.sh"
)
SNAPSHOT_BROKER_LAUNCHER = (
    PLUGIN_ROOT
    / "skills/readonly-repository-review/scripts"
    / "launch-snapshot-read-broker.sh"
)
SNAPSHOT_TRANSPORT_HELPER = (
    PLUGIN_ROOT / "skills/readonly-repository-review/scripts/snapshot-transport.sh"
)
RESEARCH_PROMPT = (
    PLUGIN_ROOT
    / "skills/readonly-repository-review/research-prompt.txt"
)
COPILOT_RESEARCH_AGENT = PLUGIN_ROOT / "agents/repo-research-worker.agent.md"
CLAUDE_RESEARCH_AGENT = (
    PLUGIN_ROOT / "claude/agents/repo-research-worker.md"
)
RESEARCH_SOURCE_SKILL = (
    PLUGIN_ROOT / "skills/research-source-assessment/SKILL.md"
)
SPEC = importlib.util.spec_from_file_location("research_egress_broker", BROKER_PATH)
assert SPEC and SPEC.loader
broker_module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = broker_module
SPEC.loader.exec_module(broker_module)


class StaticResolver:
    def __init__(self, addresses: list[str]) -> None:
        self.addresses = addresses

    def resolve(self, host: str, port: int, timeout_seconds: int) -> list[str]:
        del host, port, timeout_seconds
        return list(self.addresses)


class QueueTransport:
    def __init__(self, responses: list[object]) -> None:
        self.responses = list(responses)
        self.requests: list[dict[str, object]] = []

    def request(self, url, addresses, method, headers, policy):
        self.requests.append(
            {
                "url": url,
                "addresses": list(addresses),
                "method": method,
                "headers": dict(headers),
                "policy": policy,
            }
        )
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


def response(
    body: bytes,
    *,
    status: int = 200,
    headers: list[tuple[str, str]] | None = None,
) -> object:
    return broker_module.TransportResponse(
        status=status,
        reason="OK" if status == 200 else "Response",
        headers=headers or [("Content-Type", "text/plain; charset=utf-8")],
        body=body,
        tls={
            "Verified": True,
            "Protocol": "TLSv1.3",
            "CipherBits": 256,
            "LeafSha256": "a" * 64,
        },
        timings_ms={"ConnectAndHeaders": 1, "Total": 2},
        connected_address="93.184.216.34",
    )


def fixture_url(*parts: str) -> str:
    return "".join(parts)


def valid_dossier(instance, *, source_extra: str = "") -> str:
    capability_lines = "\n".join(
        line
        for _, line in broker_module.expected_capability_record_lines(
            instance.policy,
            instance.cookie_mode,
            instance.successful_responses,
        )
    )
    return f"""{broker_module.RESEARCH_DOSSIER_DELIMITER}
REPOSITORY RESEARCH DOSSIER
RESEARCH CAPABILITY RECORD
{capability_lines}
Confidence: High. Evidence basis: approval-bound broker records.

RESEARCH SOURCE LANDSCAPE
1. https://github.com/octocat/Hello-World checked 2026-10-11; current
   project-controlled repository evidence.{source_extra}
   Confidence: High. Evidence basis: successful public response.

COMMUNITY HEALTH EVIDENCE
1. Public repository metadata supplied aggregate activity counts.
   Confidence: Medium. Evidence basis: bounded public metadata.

CLAIM VERIFICATION EVIDENCE
None identified: No material external claim was found in the reviewed snapshot.

PRIOR ART AND LINEAGE EVIDENCE
1. No closer prior art was identified in this bounded fixture.
   Code and architecture lineage were not requested.
   Confidence: Low. Evidence basis: fixture-limited public research.

INACCESSIBLE RESOURCE REGISTER
None identified.

TOP USER RETRIEVAL PRIORITIES
None.

RESEARCH LIMITATIONS
The fixture covers only the deterministic broker contract.

RESEARCH TRANSPORT OBSERVATIONS
No material transport anomaly was observed.
{broker_module.RESEARCH_DOSSIER_DELIMITER}
"""


def valid_claim_entry(number: int = 1) -> str:
    return f"""{number}. Claim: maturity; README.md:1; production ready
   Sources checked: https://example.org/one
   Check date: 2026-10-11
   Ownership: independent
   Status: Not corroborated; no supporting record was located
   Confidence: Medium; one independent source was checked"""


def with_claim_section(candidate: str, claim_section: str) -> str:
    return candidate.replace(
        "None identified: No material external claim was found in the reviewed snapshot.",
        claim_section,
    )


def proof_summary(candidate: str) -> dict[str, object]:
    canonical, violations = (
        broker_module.canonicalize_research_dossier_candidate(candidate)
    )
    if violations or canonical is None:
        raise AssertionError(violations)
    return {
        "ResearchSubmission": {
            "ProtocolVersion": 1,
            "Status": "accepted",
            "AttemptLimit": 3,
            "AttemptsUsed": 1,
            "Canonicalization": "utf8-lf-single-terminal-newline-v1",
            "DigestAlgorithm": "sha256",
            "CandidateSha256": __import__("hashlib").sha256(canonical).hexdigest(),
            "CandidateBytes": len(canonical),
        }
    }


def embedded_research_validator_source() -> str:
    lines = RUNNER.read_text(encoding="utf-8").splitlines()
    in_function = False
    in_python = False
    extracted: list[str] = []
    for line in lines:
        if line == "validate_research_bundle() {":
            in_function = True
            continue
        if in_function and not in_python and "<<" in line and "PY" in line:
            in_python = True
            continue
        if in_python and line == "PY":
            break
        if in_python:
            extracted.append(line)
    if not extracted:
        raise AssertionError("embedded research validator was not found")
    return "\n".join(extracted) + "\n"


class BrokerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.policy = broker_module.load_effective_policy(
            POLICY_PATH,
            2,
            broker_module.WEB_PROVIDER_ID,
        )
        self.none_policy = broker_module.load_effective_policy(
            POLICY_PATH,
            2,
            broker_module.WEB_PROVIDER_NONE,
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def make_broker(
        self,
        responses: list[object],
        *,
        cookie_mode: str = "off",
        policy=None,
        inspect_capabilities: bool = True,
        accepted_candidate_path: pathlib.Path | None = None,
    ):
        transport = QueueTransport(responses)
        instance = broker_module.ResearchBroker(
            policy or self.policy,
            self.root / f"network-{len(list(self.root.iterdir()))}",
            "https://github.com/octocat/Hello-World",
            cookie_mode,
            resolver=StaticResolver(["93.184.216.34"]),
            transport=transport,
            sleep=lambda seconds: None,
            accepted_candidate_path=accepted_candidate_path,
        )
        if inspect_capabilities:
            instance.capabilities()
        return instance, transport

    def make_submission_broker(
        self,
        *,
        accepted_candidate_path: pathlib.Path | None = None,
    ):
        instance, transport = self.make_broker(
            [response(b"retrieved")],
            accepted_candidate_path=accepted_candidate_path,
        )
        if not instance.fetch("https://example.org/research")["ok"]:
            raise AssertionError("submission fixture retrieval failed")
        if not instance.network_summary()["ok"]:
            raise AssertionError("submission fixture observation failed")
        return instance, transport

    def run_embedded_validator(
        self,
        instance,
        candidate: str,
        *,
        summary: dict[str, object] | None = None,
        events: list[dict[str, object]] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        case_root = self.root / f"validator-{len(list(self.root.iterdir()))}"
        case_root.mkdir()
        dossier_path = case_root / "research.txt"
        summary_path = case_root / "summary.json"
        events_path = case_root / "events.jsonl"
        validator_path = case_root / "validate-research-bundle.py"
        dossier_path.write_text(candidate, encoding="utf-8", newline="")
        summary_path.write_text(
            json.dumps(
                summary if summary is not None else instance.summary(),
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        if events is None:
            events_path.write_bytes(instance.events_path.read_bytes())
        else:
            events_path.write_text(
                "".join(
                    json.dumps(event, separators=(",", ":")) + "\n"
                    for event in events
                ),
                encoding="utf-8",
                newline="",
            )
        validator_path.write_text(
            embedded_research_validator_source(),
            encoding="utf-8",
            newline="",
        )
        return subprocess.run(
            [
                sys.executable,
                str(validator_path),
                str(dossier_path),
                str(summary_path),
                str(events_path),
                str(instance.private_root),
                instance.policy.digest,
                instance.cookie_mode,
                broker_module.BROKER_VERSION,
                broker_module.WEB_PROVIDER_ID,
                "true",
                str(broker_module.POLICY_SCHEMA_VERSION),
                instance.policy.policy_id,
                broker_module.DIRECT_PROVIDER_ID,
                broker_module.GITHUB_PROVIDER_ID,
                json.dumps(
                    instance.policy.resource_profile(),
                    separators=(",", ":"),
                ),
                str(EVENT_INTEGER_CONTRACT_PATH),
            ],
            check=False,
            text=True,
            capture_output=True,
            env={
                **os.environ,
                "PYTHONDONTWRITEBYTECODE": "1",
            },
        )

    def make_integer_parity_broker(self):
        responses = [
            response(b"retrieved"),
            response(b"unavailable", status=503),
            response(
                b"{",
                headers=[("Content-Type", "application/json")],
            ),
            response(
                b"<root>",
                headers=[("Content-Type", "application/xml")],
            ),
            response(
                b"\x00binary",
                headers=[("Content-Type", "application/octet-stream")],
            ),
            broker_module.BrokerError(
                "headers_too_large",
                "HTTP response headers exceed the approved limit",
                details={"headerBytes": self.policy.max_header_bytes + 1},
            ),
            broker_module.BrokerError(
                "body_too_large",
                "HTTP response body exceeds the approved wire limit",
                details={"limitBytes": self.policy.max_wire_bytes},
            ),
            broker_module.BrokerError(
                "tls_verification_failed",
                "TLS certificate or hostname verification failed",
                details={
                    "verifyCode": 18,
                    "verifyMessage": "self-signed certificate",
                    "diagnosticHandshake": {
                        "Outcome": "certificate-recorded",
                        "Certificate": {
                            "CipherBits": 128,
                            "LeafSha256": "b" * 64,
                        },
                    },
                },
            ),
            response(
                b"",
                status=302,
                headers=[("Location", "https://example.net/final")],
            ),
            response(b"redirected"),
            response(
                b"<html><body>unexpected provider page</body></html>",
                headers=[("Content-Type", "text/html")],
            ),
        ]
        instance, _ = self.make_broker(
            responses,
            cookie_mode="ephemeral",
            inspect_capabilities=False,
        )
        blocked = instance.fetch("https://example.org/before-capabilities")
        self.assertFalse(blocked["ok"])
        self.assertEqual(
            blocked["error"]["code"],
            "capabilities_required_before_retrieval",
        )
        instance.capabilities()
        self.assertTrue(instance.fetch("https://example.org/success")["ok"])
        self.assertTrue(instance.network_summary()["ok"])
        self.assertEqual(
            instance.fetch("https://example.org/status")["error"]["code"],
            "http_status",
        )
        self.assertEqual(
            instance.fetch("https://example.org/malformed.json")["error"]["code"],
            "malformed_json",
        )
        self.assertEqual(
            instance.fetch("https://example.org/malformed.xml")["error"]["code"],
            "malformed_xml",
        )
        self.assertEqual(
            instance.fetch("https://example.org/file.bin")["error"]["code"],
            "unsupported_format",
        )
        self.assertEqual(
            instance.fetch("https://example.org/headers")["error"]["code"],
            "headers_too_large",
        )
        self.assertEqual(
            instance.fetch("https://example.org/body")["error"]["code"],
            "body_too_large",
        )
        self.assertEqual(
            instance.fetch("https://example.org/tls")["error"]["code"],
            "tls_verification_failed",
        )
        self.assertEqual(
            instance.fetch("https://example.org:444/")["error"]["code"],
            "tls_port_forbidden",
        )
        self.assertTrue(instance.fetch("https://example.org/redirect")["ok"])
        self.assertEqual(
            instance.search_web("fixture provider result", 10)["error"]["code"],
            "provider_malformed_response",
        )
        instance.request_count = instance.policy.request_budget
        self.assertEqual(
            instance.fetch("https://example.org/budget")["error"]["code"],
            "request_budget_exhausted",
        )
        self.assertTrue(instance.network_summary()["ok"])

        candidate = valid_dossier(instance)
        excessive_claims = "\n".join(
            valid_claim_entry(index)
            for index in range(
                1,
                broker_module.RESEARCH_DOSSIER_MAX_CLAIM_ENTRIES + 2,
            )
        )
        rejected = instance.network_summary(
            with_claim_section(candidate, excessive_claims)
        )
        self.assertFalse(rejected["submissionValidation"]["accepted"])
        self.assertEqual(
            rejected["submissionValidation"]["claimEntryCount"],
            broker_module.RESEARCH_DOSSIER_MAX_CLAIM_ENTRIES + 1,
        )
        accepted = instance.network_summary(candidate)
        self.assertTrue(accepted["submissionValidation"]["accepted"])
        replayed = instance.network_summary(candidate)
        self.assertTrue(replayed["submissionValidation"]["accepted"])
        self.assertTrue(replayed["submissionValidation"]["replayed"])
        blocked = instance.fetch("https://example.org/after-acceptance")
        self.assertFalse(blocked["ok"])
        self.assertEqual(
            blocked["error"]["code"],
            "research_submission_already_accepted",
        )
        instance.close()
        return instance, candidate

    def test_policy_description_and_hard_limits(self) -> None:
        self.assertEqual(self.policy.request_budget, 500)
        self.assertEqual(self.policy.allowed_tls_ports, (443,))
        self.assertEqual(len(self.policy.digest), 64)
        raw = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
        raw["transport"]["maxWireBytes"] = 10 * 1024 * 1024 + 1
        unsafe = self.root / "unsafe.json"
        unsafe.write_text(json.dumps(raw), encoding="utf-8")
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.load_effective_policy(
                unsafe,
                2,
                broker_module.WEB_PROVIDER_ID,
            )
        self.assertEqual(context.exception.code, "unsafe_policy")
        self.assertEqual(
            self.policy.web_search_provider,
            broker_module.WEB_PROVIDER_ID,
        )
        self.assertNotEqual(self.policy.digest, self.none_policy.digest)

    def test_policy_schema_requires_an_exact_json_integer(self) -> None:
        mutations = (
            ("true", True),
            ("false", False),
            ("numeric-string", "1"),
            ("integral-float", 1.0),
            ("non-integral-float", 1.5),
            ("negative", -1),
            ("oversized", 10**30),
        )
        for label, mutation in mutations:
            with self.subTest(mutation=label):
                raw = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
                raw["schemaVersion"] = mutation
                malformed = self.root / f"schema-{label}.json"
                malformed.write_text(json.dumps(raw), encoding="utf-8")
                with self.assertRaises(broker_module.BrokerError) as context:
                    broker_module.load_effective_policy(
                        malformed,
                        2,
                        broker_module.WEB_PROVIDER_ID,
                    )
                self.assertEqual(
                    context.exception.code,
                    "unsupported_policy_schema",
                )
                self.assertEqual(
                    context.exception.details,
                    {
                        "expected": broker_module.POLICY_SCHEMA_VERSION,
                        "actualType": type(mutation).__name__,
                    },
                )
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.load_effective_policy(
                POLICY_PATH,
                2,
                "unregistered-provider",
            )
        self.assertEqual(context.exception.code, "provider_disabled")

    def test_url_floor_and_sanitized_query(self) -> None:
        valid = broker_module.validate_public_https_url(
            "https://example.org/path?token=secret&topic=public#fragment",
            self.policy,
        )
        self.assertEqual(valid.url, "https://example.org/path?token=secret&topic=public")
        self.assertEqual(
            valid.sanitized_url,
            "https://example.org/path?token=%5Bredacted%5D&topic=public",
        )
        for value in (
            "http://example.org/",
            fixture_url("https://user:pass", "@example.org/"),
            fixture_url("https://127", ".0.0.1/"),
            fixture_url("https://local", "host/"),
            fixture_url("https://service", ".internal/"),
            "https://example.org:444/",
            "https://example.org/%0d%0aInjected",
            "https://example.org/%5cadmin",
            "https://example.org/\\admin",
            "https://example.org/%zz",
        ):
            with self.subTest(value=value):
                with self.assertRaises(broker_module.BrokerError):
                    broker_module.validate_public_https_url(value, self.policy)

    def test_public_resolver_rejects_any_non_global_answer(self) -> None:
        records = [
            (2, 1, 6, "", ("93.184.216.34", 443)),
            (2, 1, 6, "", ("127.0.0.1", 443)),
        ]
        with mock.patch.object(
            broker_module.socket,
            "getaddrinfo",
            return_value=records,
        ):
            with self.assertRaises(broker_module.BrokerError) as context:
                broker_module.PublicResolver().resolve("example.org", 443, 1)
        self.assertEqual(context.exception.code, "non_public_dns")

    def test_html_normalization_strips_active_content(self) -> None:
        normalized = broker_module.normalize_supported_body(
            (
                b"<html><script>steal()</script><body>Hello "
                b"<a href='https://example.org/doc'>documentation</a></body></html>"
            ),
            "text/html",
            "https://example.org/",
            self.policy,
        )
        assert normalized
        self.assertEqual(normalized["Format"], "html")
        self.assertIn("Hello", normalized["Text"])
        self.assertNotIn("steal", normalized["Text"])
        self.assertEqual(normalized["Links"][0]["Url"], "https://example.org/doc")

    def test_cookie_off_retains_raw_only_in_private_ledger(self) -> None:
        raw_cookie = "session=private-cookie-value; Path=/; Secure; HttpOnly"
        instance, transport = self.make_broker(
            [
                response(
                    b"ok",
                    headers=[
                        ("Content-Type", "text/plain"),
                        ("Set-Cookie", raw_cookie),
                    ],
                ),
                response(b"again"),
            ]
        )
        first = instance.fetch("https://example.org/")
        second = instance.fetch("https://example.org/again")
        self.assertTrue(first["ok"])
        self.assertTrue(second["ok"])
        self.assertNotIn("Cookie", transport.requests[1]["headers"])
        private_cookie_text = instance.cookies_path.read_text(encoding="utf-8")
        self.assertIn("private-cookie-value", private_cookie_text)
        for public_path in (instance.events_path, instance.summary_path):
            self.assertNotIn(
                "private-cookie-value", public_path.read_text(encoding="utf-8")
            )
        self.assertEqual(stat.S_IMODE(instance.private_root.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(instance.cookies_path.stat().st_mode), 0o600)

    def test_ephemeral_cookie_replay_is_exact_host_and_secure(self) -> None:
        instance, transport = self.make_broker(
            [
                response(
                    b"ok",
                    headers=[
                        ("Content-Type", "text/plain"),
                        ("Set-Cookie", "exact=value-one; Domain=example.org; Path=/; Secure"),
                        ("Set-Cookie", "wide=value-two; Domain=.org; Path=/; Secure"),
                        ("Set-Cookie", "insecure=value-three; Path=/"),
                    ],
                ),
                response(b"same-host"),
                response(b"other-host"),
            ],
            cookie_mode="ephemeral",
        )
        self.assertTrue(instance.fetch("https://example.org/")["ok"])
        self.assertTrue(instance.fetch("https://example.org/path")["ok"])
        self.assertTrue(instance.fetch("https://other.example.net/")["ok"])
        self.assertEqual(
            transport.requests[1]["headers"].get("Cookie"),
            "exact=value-one",
        )
        self.assertNotIn("Cookie", transport.requests[2]["headers"])
        events = instance.events_path.read_text(encoding="utf-8")
        self.assertIn("domain_scope_broadened", events)
        self.assertIn("secure_required", events)
        self.assertNotIn("value-two", events)
        self.assertNotIn("value-three", events)

    def test_redirect_revalidates_and_records_chain(self) -> None:
        instance, transport = self.make_broker(
            [
                response(
                    b"",
                    status=302,
                    headers=[("Location", "https://example.net/final")],
                ),
                response(b"final"),
            ]
        )
        result = instance.fetch("https://example.org/start")
        self.assertTrue(result["ok"])
        self.assertEqual(len(result["redirects"]), 1)
        self.assertEqual(transport.requests[1]["url"].host, "example.net")
        self.assertEqual(instance.summary()["Requests"]["Redirects"], 1)

    def test_unsupported_body_is_private_content_addressed(self) -> None:
        body = b"\x00\x01\x02hostile"
        instance, _ = self.make_broker(
            [response(body, headers=[("Content-Type", "application/octet-stream")])]
        )
        result = instance.fetch("https://example.org/file.bin")
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"]["code"], "unsupported_format")
        digest = __import__("hashlib").sha256(body).hexdigest()
        stored = instance.body_root / f"{digest}.bin"
        self.assertEqual(stored.read_bytes(), body)
        self.assertEqual(stat.S_IMODE(stored.stat().st_mode), 0o600)
        self.assertNotIn(
            "hostile", instance.summary_path.read_text(encoding="utf-8")
        )

    def test_mime_mismatch_is_stored_privately(self) -> None:
        body = b"text-prefix\x00private-binary-evidence"
        instance, _ = self.make_broker(
            [response(body, headers=[("Content-Type", "text/plain")])]
        )
        result = instance.fetch("https://example.org/mismatch")
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"]["code"], "mime_mismatch")
        digest = __import__("hashlib").sha256(body).hexdigest()
        self.assertEqual((instance.body_root / f"{digest}.bin").read_bytes(), body)

    def test_xml_entities_are_not_normalized(self) -> None:
        body = b'<!DOCTYPE root [<!ENTITY x "unsafe">]><root>&x;</root>'
        instance, _ = self.make_broker(
            [response(body, headers=[("Content-Type", "application/xml")])]
        )
        result = instance.fetch("https://example.org/entity.xml")
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"]["code"], "unsafe_xml")
        digest = __import__("hashlib").sha256(body).hexdigest()
        self.assertEqual((instance.body_root / f"{digest}.bin").read_bytes(), body)

    def test_request_budget_fails_closed(self) -> None:
        limited = dataclasses.replace(self.policy, request_budget=1)
        transport = QueueTransport([response(b"first"), response(b"second")])
        instance = broker_module.ResearchBroker(
            limited,
            self.root / "budget-network",
            "https://github.com/octocat/Hello-World",
            "off",
            resolver=StaticResolver(["93.184.216.34"]),
            transport=transport,
            sleep=lambda seconds: None,
        )
        instance.capabilities()
        self.assertTrue(instance.fetch("https://example.org/first")["ok"])
        second = instance.fetch("https://example.org/second")
        self.assertFalse(second["ok"])
        self.assertEqual(second["error"]["code"], "request_budget_exhausted")
        self.assertEqual(len(transport.requests), 1)

    def test_github_provider_normalizes_without_authorization(self) -> None:
        payload = json.dumps(
            {
                "total_count": 1,
                "incomplete_results": False,
                "items": [
                    {
                        "html_url": "https://github.com/octocat/Hello-World",
                        "full_name": "octocat/Hello-World",
                        "description": "Fixture",
                        "updated_at": "2026-01-01T00:00:00Z",
                        "stargazers_count": 1,
                    }
                ],
            }
        ).encode()
        instance, transport = self.make_broker(
            [response(payload, headers=[("Content-Type", "application/json")])]
        )
        result = instance.search_github("octocat", "repositories", 10, 1)
        self.assertTrue(result["ok"])
        self.assertEqual(result["providerId"], broker_module.GITHUB_PROVIDER_ID)
        self.assertEqual(result["results"][0]["Title"], "octocat/Hello-World")
        self.assertNotIn("Authorization", transport.requests[0]["headers"])

    def test_web_search_normalizes_redirects_revalidates_and_deduplicates(
        self,
    ) -> None:
        primary = urllib.parse.quote(
            "https://example.org/docs?token=secret&topic=public",
            safe="",
        )
        secondary = urllib.parse.quote(
            "https://second.example.net/article",
            safe="",
        )
        invalid_http = urllib.parse.quote("http://unsafe.example.org/", safe="")
        invalid_private = urllib.parse.quote(
            fixture_url("https://127", ".0.0.1/"),
            safe="",
        )
        fixture = f"""
        <html><body><form>
          <a class="result__a" href="//duckduckgo.com/l/?uddg={primary}">
            Example documentation
          </a>
          <a class="result__url" href="//duckduckgo.com/l/?uddg={primary}">
            example.org/docs
          </a>
          <a class="result__snippet" href="//duckduckgo.com/l/?uddg={primary}">
            Public summary for the first result.
          </a>
          <a class="result__a" href="//duckduckgo.com/l/?uddg={primary}">
            Duplicate result
          </a>
          <a class="result__a" href="//duckduckgo.com/l/?uddg={invalid_http}">
            Plaintext result
          </a>
          <a class="result__a" href="//duckduckgo.com/l/?uddg={invalid_private}">
            Private result
          </a>
          <a class="result__a" href="//duckduckgo.com/l/?uddg={secondary}">
            Second result
          </a>
          <a class="result__snippet" href="//duckduckgo.com/l/?uddg={secondary}">
            Second public summary.
          </a>
        </form></body></html>
        """.encode()
        instance, transport = self.make_broker(
            [response(fixture, headers=[("Content-Type", "text/html; charset=utf-8")])]
        )
        result = instance.search_web("public research", 10)
        self.assertTrue(result["ok"])
        self.assertEqual(result["providerId"], broker_module.WEB_PROVIDER_ID)
        self.assertEqual(len(result["results"]), 2)
        self.assertEqual(
            result["results"][0],
            {
                "Url": (
                    "https://example.org/docs?"
                    "token=%5Bredacted%5D&topic=public"
                ),
                "Title": "Example documentation",
                "Summary": "Public summary for the first result.",
            },
        )
        self.assertEqual(
            result["results"][1]["Url"],
            "https://second.example.net/article",
        )
        self.assertEqual(len(transport.requests), 1)
        requested = transport.requests[0]
        self.assertEqual(requested["url"].host, "html.duckduckgo.com")
        self.assertEqual(requested["url"].target.split("?", 1)[0], "/html/")
        query = urllib.parse.parse_qs(
            requested["url"].target.split("?", 1)[1]
        )
        self.assertEqual(query, {"q": ["public research"]})
        self.assertEqual(requested["method"], "GET")
        self.assertNotIn("Authorization", requested["headers"])

    def test_web_search_provider_challenge_is_structured_without_fallback(
        self,
    ) -> None:
        instance, transport = self.make_broker(
            [
                response(
                    (
                        b"<html><body>Unfortunately, bots use DuckDuckGo too. "
                        b"DuckDuckGo Search Challenge.</body></html>"
                    ),
                    headers=[("Content-Type", "text/html")],
                )
            ]
        )
        result = instance.search_web("public research", 10)
        self.assertFalse(result["ok"])
        self.assertEqual(result["providerId"], broker_module.WEB_PROVIDER_ID)
        self.assertEqual(result["error"]["code"], "provider_challenge")
        self.assertEqual(result["results"], [])
        self.assertEqual(len(transport.requests), 1)

    def test_web_search_rejects_oversized_wrapper_query_per_candidate(
        self,
    ) -> None:
        oversized_query = urllib.parse.urlencode(
            [(f"field{index}", str(index)) for index in range(21)]
            + [("uddg", "https://ignored.example.net/")]
        )
        valid = urllib.parse.quote(
            "https://example.org/retained",
            safe="",
        )
        fixture = f"""
        <html><body>
          <a class="result__a"
             href="//duckduckgo.com/l/?{oversized_query}">
            Rejected oversized wrapper
          </a>
          <a class="result__a" href="//duckduckgo.com/l/?uddg={valid}">
            Retained result
          </a>
        </body></html>
        """.encode()
        instance, transport = self.make_broker(
            [response(fixture, headers=[("Content-Type", "text/html")])]
        )
        reply = broker_module.McpServer(instance).handle(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {
                    "name": "search_public_web",
                    "arguments": {"query": "fixture", "limit": 10},
                },
            }
        )
        assert reply is not None
        self.assertNotIn("error", reply)
        result = reply["result"]["structuredContent"]
        self.assertTrue(result["ok"])
        self.assertEqual(
            result["results"],
            [
                {
                    "Url": "https://example.org/retained",
                    "Title": "Retained result",
                    "Summary": "",
                }
            ],
        )
        self.assertEqual(len(transport.requests), 1)

    def test_web_search_rejects_redirect_outside_provider_hosts(self) -> None:
        attacker_fixture = b"""
        <html><body>
          <a class="result__a" href="https://example.org/attacker">
            Attacker-controlled result
          </a>
        </body></html>
        """
        instance, transport = self.make_broker(
            [
                response(
                    b"",
                    status=302,
                    headers=[("Location", "https://example.net/results")],
                ),
                response(
                    attacker_fixture,
                    headers=[("Content-Type", "text/html")],
                ),
            ]
        )
        result = instance.search_web("public research", 10)
        self.assertFalse(result["ok"])
        self.assertEqual(
            result["error"]["code"],
            "provider_host_forbidden",
        )
        self.assertEqual(result["providerId"], broker_module.WEB_PROVIDER_ID)
        self.assertEqual(result["results"], [])
        self.assertEqual(len(transport.requests), 1)
        self.assertEqual(transport.requests[0]["url"].host, "html.duckduckgo.com")
        self.assertEqual(len(transport.responses), 1)

    def test_web_search_rejected_anchor_cannot_claim_no_results(self) -> None:
        fixture = (
            b"<html><body><a class='result__snippet' "
            b"href='http://unsafe.example.org/'>"
            b"No results found.</a></body></html>"
        )
        instance, transport = self.make_broker(
            [response(fixture, headers=[("Content-Type", "text/html")])]
        )
        result = instance.search_web("malformed fixture", 10)
        self.assertFalse(result["ok"])
        self.assertEqual(
            result["error"]["code"],
            "provider_malformed_response",
        )
        self.assertEqual(result["results"], [])
        self.assertEqual(len(transport.requests), 1)

    def test_web_search_empty_and_malformed_results_are_distinct(self) -> None:
        invalid = urllib.parse.quote(
            fixture_url("https://127", ".0.0.1/private"),
            safe="",
        )
        instance, transport = self.make_broker(
            [
                response(
                    b"<html><body>No results found.</body></html>",
                    headers=[("Content-Type", "text/html")],
                ),
                response(
                    (
                        b"<html><body><a class='result__a' "
                        b"href='//duckduckgo.com/l/?uddg="
                        + invalid.encode()
                        + b"'>Invalid result</a></body></html>"
                    ),
                    headers=[("Content-Type", "text/html")],
                ),
            ]
        )
        empty = instance.search_web("no fixture matches", 10)
        self.assertTrue(empty["ok"])
        self.assertEqual(empty["results"], [])
        malformed = instance.search_web("invalid fixture", 10)
        self.assertFalse(malformed["ok"])
        self.assertEqual(
            malformed["error"]["code"],
            "provider_malformed_response",
        )
        self.assertEqual(malformed["results"], [])
        self.assertEqual(len(transport.requests), 2)

    def test_web_search_none_is_stably_disabled(self) -> None:
        instance, transport = self.make_broker([], policy=self.none_policy)
        result = instance.search_web("public research", 10)
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"]["code"], "provider_disabled")
        self.assertEqual(result["providerId"], broker_module.WEB_PROVIDER_NONE)
        self.assertEqual(transport.requests, [])

    def test_web_search_capabilities_reflect_selected_provider(self) -> None:
        instance, _ = self.make_broker([])
        capabilities = instance.capabilities()
        self.assertEqual(capabilities["brokerVersion"], "1.1")
        self.assertEqual(
            capabilities["providers"]["generalWebSearch"],
            {
                "id": broker_module.WEB_PROVIDER_ID,
                "enabled": True,
                "status": "ready",
                "authentication": "none",
            },
        )
        self.assertEqual(
            instance.summary()["GeneralWebSearch"],
            {
                "ProviderId": broker_module.WEB_PROVIDER_ID,
                "Available": True,
            },
        )
        self.assertEqual(
            capabilities["dossierValidation"],
            {
                "protocolVersion": 1,
                "tool": "research_network_summary",
                "attemptLimit": 3,
                "canonicalization": "utf8-lf-single-terminal-newline-v1",
                "digestAlgorithm": "sha256",
            },
        )

    def test_public_retrieval_requires_capability_inspection_first(self) -> None:
        instance, transport = self.make_broker(
            [response(b"retrieved")],
            inspect_capabilities=False,
        )
        rejected = instance.fetch("https://example.org/research")
        self.assertFalse(rejected["ok"])
        self.assertEqual(
            rejected["error"]["code"],
            "capabilities_required_before_retrieval",
        )
        self.assertEqual(transport.requests, [])

        instance.capabilities()
        self.assertTrue(instance.fetch("https://example.org/research")["ok"])
        self.assertTrue(instance.network_summary()["ok"])
        candidate = valid_dossier(instance)
        accepted = instance.network_summary(candidate)["submissionValidation"]
        self.assertTrue(accepted["accepted"])

        events = [
            json.loads(line)
            for line in instance.events_path.read_text(encoding="utf-8").splitlines()
        ]
        event_types = [event["Type"] for event in events]
        capability_index = event_types.index("capabilities_checked")
        retrieval_index = event_types.index("public_retrieval_succeeded")
        observation_index = event_types.index("network_summary_observed")
        accepted_index = event_types.index(
            "research_dossier_validation_accepted"
        )
        self.assertLess(capability_index, retrieval_index)
        self.assertLess(retrieval_index, observation_index)
        self.assertLess(observation_index, accepted_index)
        accepted_event = events[accepted_index]
        self.assertLess(
            accepted_event["CapabilityInspectionSequence"],
            accepted_event["LatestSuccessfulRetrievalSequence"],
        )
        self.assertLess(
            accepted_event["LatestSuccessfulRetrievalSequence"],
            accepted_event["LatestNetworkSummaryObservationSequence"],
        )
        self.assertLess(
            accepted_event["LatestNetworkSummaryObservationSequence"],
            accepted_event["CandidateRequestSequence"],
        )

    def test_every_public_retrieval_tool_rejects_before_capabilities(
        self,
    ) -> None:
        calls = (
            (
                "fetch_public_url",
                lambda instance: instance.fetch("https://example.org/research"),
            ),
            (
                "search_public_github",
                lambda instance: instance.search_github(
                    "octocat",
                    "repositories",
                    10,
                    1,
                ),
            ),
            (
                "search_public_web",
                lambda instance: instance.search_web("public research", 10),
            ),
        )
        for label, call in calls:
            with self.subTest(tool=label):
                instance, transport = self.make_broker(
                    [response(b"unused")],
                    inspect_capabilities=False,
                )
                result = call(instance)
                self.assertFalse(result["ok"])
                self.assertEqual(
                    result["error"]["code"],
                    "capabilities_required_before_retrieval",
                )
                self.assertEqual(transport.requests, [])

    def test_candidate_workflow_rejects_out_of_order_permutations(self) -> None:
        cases = (
            (
                "candidate before capabilities",
                False,
                False,
                False,
                {
                    "capabilities_not_checked",
                    "no_successful_public_response",
                    "network_summary_not_observed",
                },
            ),
            (
                "candidate after capabilities only",
                True,
                False,
                False,
                {
                    "no_successful_public_response",
                    "network_summary_not_observed",
                },
            ),
            (
                "candidate after premature observation",
                True,
                False,
                True,
                {
                    "no_successful_public_response",
                    "network_summary_observation_stale",
                },
            ),
        )
        for (
            label,
            inspect_capabilities,
            retrieve,
            observe,
            expected_codes,
        ) in cases:
            with self.subTest(case=label):
                responses = [response(b"retrieved")] if retrieve else []
                instance, _ = self.make_broker(
                    responses,
                    inspect_capabilities=inspect_capabilities,
                )
                if retrieve:
                    self.assertTrue(
                        instance.fetch("https://example.org/research")["ok"]
                    )
                if observe:
                    self.assertTrue(instance.network_summary()["ok"])
                validation = instance.network_summary(
                    valid_dossier(instance)
                )["submissionValidation"]
                self.assertFalse(validation["accepted"])
                self.assertEqual(validation["attempt"], 1)
                self.assertEqual(
                    {
                        violation["code"]
                        for violation in validation["violations"]
                    },
                    expected_codes,
                )

    def test_candidate_calls_do_not_replace_required_observation(self) -> None:
        instance, _ = self.make_broker([response(b"retrieved")])
        self.assertTrue(instance.fetch("https://example.org/research")["ok"])
        candidate = valid_dossier(instance)

        first = instance.network_summary(candidate)["submissionValidation"]
        second = instance.network_summary(candidate)["submissionValidation"]
        for attempt, validation in enumerate((first, second), start=1):
            self.assertFalse(validation["accepted"])
            self.assertEqual(validation["attempt"], attempt)
            self.assertIn(
                "network_summary_not_observed",
                validation["violationCodeCounts"],
            )
        self.assertIsNone(
            instance.latest_network_summary_observation_sequence
        )

        instance.network_summary()
        accepted = instance.network_summary(candidate)["submissionValidation"]
        self.assertTrue(accepted["accepted"])
        self.assertEqual(accepted["attempt"], 3)

    def test_retrieval_after_observation_makes_observation_stale(self) -> None:
        instance, _ = self.make_broker(
            [response(b"first"), response(b"second")]
        )
        self.assertTrue(instance.fetch("https://example.org/first")["ok"])
        instance.network_summary()
        first_observation = instance.latest_network_summary_observation_sequence
        self.assertTrue(instance.fetch("https://example.org/second")["ok"])
        self.assertLess(
            first_observation,
            instance.latest_successful_retrieval_sequence,
        )

        candidate = valid_dossier(instance)
        stale = instance.network_summary(candidate)["submissionValidation"]
        self.assertFalse(stale["accepted"])
        self.assertIn(
            "network_summary_observation_stale",
            stale["violationCodeCounts"],
        )

        instance.network_summary()
        accepted = instance.network_summary(candidate)["submissionValidation"]
        self.assertTrue(accepted["accepted"])
        self.assertEqual(accepted["attempt"], 2)

    def test_submission_validation_rejects_missing_tool_in_capability_section(
        self,
    ) -> None:
        instance, _ = self.make_submission_broker()
        candidate = valid_dossier(
            instance,
            source_extra=(
                "\n   The research_capabilities call succeeded before retrieval."
            ),
        )
        expected_tools = (
            "Exact tools: research_capabilities, fetch_public_url, "
            "search_public_github, search_public_web, research_network_summary"
        )
        candidate = candidate.replace(
            expected_tools,
            (
                "Exact tools: fetch_public_url, search_public_github, "
                "search_public_web, research_network_summary"
            ),
        )
        result = instance.network_summary(candidate)
        self.assertFalse(result["ok"])
        validation = result["submissionValidation"]
        self.assertFalse(validation["accepted"])
        self.assertEqual(validation["attempt"], 1)
        self.assertEqual(validation["attemptsRemaining"], 2)
        self.assertTrue(
            any(
                violation["path"]
                == "RESEARCH CAPABILITY RECORD/Exact tools"
                and "research_capabilities" in violation["message"]
                for violation in validation["violations"]
            )
        )
        self.assertEqual(
            instance.summary()["ResearchSubmission"]["Status"],
            "rejected",
        )

    def test_submission_validation_correction_acceptance_and_attempt_bound(
        self,
    ) -> None:
        instance, _ = self.make_submission_broker()
        candidate = valid_dossier(instance)
        rejected = instance.network_summary(
            candidate.replace(
                "Broker health: ready",
                "Broker health: unavailable",
            )
        )["submissionValidation"]
        self.assertFalse(rejected["accepted"])
        accepted = instance.network_summary(candidate)["submissionValidation"]
        self.assertTrue(accepted["accepted"])
        self.assertEqual(accepted["attempt"], 2)
        proof = accepted["proof"]
        canonical, violations = (
            broker_module.canonicalize_research_dossier_candidate(candidate)
        )
        self.assertEqual(violations, [])
        assert canonical is not None
        self.assertEqual(proof["CandidateBytes"], len(canonical))
        self.assertEqual(
            proof["CandidateSha256"],
            __import__("hashlib").sha256(canonical).hexdigest(),
        )
        changed = instance.network_summary(
            candidate.replace("No material transport", "One material transport")
        )["submissionValidation"]
        self.assertFalse(changed["accepted"])
        self.assertEqual(
            changed["violations"][0]["code"],
            "candidate_already_accepted",
        )

        exhausted, _ = self.make_submission_broker()
        invalid = valid_dossier(exhausted).replace(
            "Broker health: ready",
            "Broker health: unavailable",
        )
        for attempt in range(1, 4):
            result = exhausted.network_summary(invalid)["submissionValidation"]
            self.assertFalse(result["accepted"])
            self.assertEqual(result["attempt"], attempt)
        final = exhausted.network_summary(
            valid_dossier(exhausted)
        )["submissionValidation"]
        self.assertFalse(final["accepted"])
        self.assertEqual(
            final["violations"][0]["code"],
            "attempt_limit_exhausted",
        )

    def test_submission_canonicalization_is_stable_and_rejects_lossy_input(
        self,
    ) -> None:
        instance, _ = self.make_submission_broker()
        candidate_without_newline = valid_dossier(instance).removesuffix("\n")
        accepted = instance.network_summary(
            candidate_without_newline
        )["submissionValidation"]
        self.assertTrue(accepted["accepted"])
        canonical, violations = (
            broker_module.canonicalize_research_dossier_candidate(
                candidate_without_newline
            )
        )
        self.assertEqual(violations, [])
        assert canonical is not None
        self.assertTrue(canonical.endswith(b"\n"))
        self.assertFalse(canonical.endswith(b"\n\n"))
        self.assertEqual(
            accepted["proof"]["CandidateSha256"],
            __import__("hashlib").sha256(canonical).hexdigest(),
        )

        for invalid_suffix, expected_code in (
            ("\n", "trailing_content"),
            ("\r", "line_endings"),
        ):
            rejected, _ = self.make_submission_broker()
            invalid = valid_dossier(rejected) + invalid_suffix
            validation = rejected.network_summary(invalid)[
                "submissionValidation"
            ]
            self.assertFalse(validation["accepted"])
            self.assertTrue(
                any(
                    violation["code"] == expected_code
                    for violation in validation["violations"]
                )
            )

        for separator in (
            "\v",
            "\f",
            "\x1c",
            "\x1d",
            "\x1e",
            "\x85",
            "\u2028",
            "\u2029",
        ):
            with self.subTest(separator=f"U+{ord(separator):04X}"):
                rejected, _ = self.make_submission_broker()
                invalid = valid_dossier(rejected).replace(
                    "\nREPOSITORY RESEARCH DOSSIER",
                    separator + "REPOSITORY RESEARCH DOSSIER",
                    1,
                )
                validation = rejected.network_summary(invalid)[
                    "submissionValidation"
                ]
                self.assertFalse(validation["accepted"])
                self.assertIn(
                    "line_endings",
                    validation["violationCodeCounts"],
                )

    def test_claim_verification_accepts_strict_numbered_form(self) -> None:
        instance, _ = self.make_submission_broker()
        candidate = with_claim_section(
            valid_dossier(instance),
            valid_claim_entry(),
        )
        validation = instance.network_summary(candidate)[
            "submissionValidation"
        ]
        self.assertTrue(validation["accepted"])
        self.assertEqual(validation["claimEntryCount"], 1)

    def test_claim_none_form_is_justified_and_mutually_exclusive(self) -> None:
        cases = (
            (
                "missing basis",
                "None identified:",
                "claim_none_format",
            ),
            (
                "numbered entry plus none",
                (
                    "None identified: Snapshot review found no material claim.\n"
                    + valid_claim_entry()
                ),
                "claim_none_exclusive",
            ),
            (
                "trailing content after none",
                (
                    "None identified: Snapshot review found no material claim.\n"
                    "Additional unlabelled content."
                ),
                "claim_none_exclusive",
            ),
        )
        for label, claim_section, expected_code in cases:
            with self.subTest(case=label):
                instance, _ = self.make_submission_broker()
                validation = instance.network_summary(
                    with_claim_section(
                        valid_dossier(instance),
                        claim_section,
                    )
                )["submissionValidation"]
                self.assertFalse(validation["accepted"])
                self.assertIn(
                    expected_code,
                    validation["violationCodeCounts"],
                )

    def test_claim_grammar_rejects_uncontrolled_or_malformed_fields(
        self,
    ) -> None:
        valid = valid_claim_entry()
        cases = (
            (
                "missing label",
                valid.replace(
                    "   Sources checked: https://example.org/one\n",
                    "",
                ),
                "claim_missing_label",
            ),
            (
                "invalid claim path",
                valid.replace(
                    "maturity; README.md:1; production ready",
                    "maturity; README.md; production ready",
                ),
                "claim_value_format",
            ),
            (
                "sources without URL or reason",
                valid.replace(
                    "Sources checked: https://example.org/one",
                    "Sources checked: unavailable",
                ),
                "claim_sources",
            ),
            (
                "duplicate label",
                valid
                + "\n   Status: Corroborated; duplicate status is forbidden",
                "claim_duplicate_label",
            ),
            (
                "unknown label",
                valid + "\n   Reviewer note: uncontrolled field",
                "claim_unknown_label",
            ),
            (
                "trailing content",
                valid + "\ncontinuation without a label",
                "claim_trailing_content",
            ),
            (
                "invalid date width",
                valid.replace("2026-10-11", "2026-1-01"),
                "claim_check_date",
            ),
            (
                "invalid calendar date",
                valid.replace("2026-10-11", "2026-02-30"),
                "claim_check_date",
            ),
            (
                "uncontrolled ownership",
                valid.replace("Ownership: independent", "Ownership: affiliated"),
                "claim_ownership",
            ),
            (
                "uncontrolled status",
                valid.replace(
                    "Status: Not corroborated; no supporting record was located",
                    "Status: Unknown; no supporting record was located",
                ),
                "claim_status",
            ),
            (
                "corroborated project ownership",
                valid.replace(
                    "Ownership: independent",
                    "Ownership: project-controlled",
                ).replace(
                    "Status: Not corroborated; no supporting record was located",
                    "Status: Corroborated; project-only evidence is insufficient",
                ),
                "claim_status_ownership",
            ),
            (
                "status without reason",
                valid.replace(
                    "Status: Not corroborated; no supporting record was located",
                    "Status: Not corroborated;",
                ),
                "claim_status",
            ),
            (
                "compound confidence",
                valid.replace(
                    "Confidence: Medium; one independent source was checked",
                    "Confidence: High/Medium; one source was checked",
                ),
                "claim_confidence",
            ),
            (
                "confidence without evidence",
                valid.replace(
                    "Confidence: Medium; one independent source was checked",
                    "Confidence: Medium;",
                ),
                "claim_confidence",
            ),
            (
                "wrong label order",
                valid.replace(
                    (
                        "   Check date: 2026-10-11\n"
                        "   Ownership: independent"
                    ),
                    (
                        "   Ownership: independent\n"
                        "   Check date: 2026-10-11"
                    ),
                ),
                "claim_label_order",
            ),
            (
                "non-sequential numbering",
                valid.replace("1. Claim:", "2. Claim:", 1),
                "claim_numbering",
            ),
        )
        for label, claim_section, expected_code in cases:
            with self.subTest(case=label):
                instance, _ = self.make_submission_broker()
                validation = instance.network_summary(
                    with_claim_section(
                        valid_dossier(instance),
                        claim_section,
                    )
                )["submissionValidation"]
                self.assertFalse(validation["accepted"])
                self.assertIn(
                    expected_code,
                    validation["violationCodeCounts"],
                )

    def test_claim_entry_limit_is_enforced_at_boundary(self) -> None:
        allowed, _ = self.make_submission_broker()
        maximum_claims = "\n".join(
            valid_claim_entry(index)
            for index in range(
                1,
                broker_module.RESEARCH_DOSSIER_MAX_CLAIM_ENTRIES + 1,
            )
        )
        allowed_candidate = with_claim_section(
            valid_dossier(allowed),
            maximum_claims,
        )
        accepted = allowed.network_summary(allowed_candidate)[
            "submissionValidation"
        ]
        self.assertTrue(accepted["accepted"])
        self.assertEqual(
            accepted["claimEntryCount"],
            broker_module.RESEARCH_DOSSIER_MAX_CLAIM_ENTRIES,
        )
        allowed.close()
        completed = self.run_embedded_validator(
            allowed,
            allowed_candidate,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)

        rejected, _ = self.make_submission_broker()
        excessive_claims = (
            maximum_claims
            + "\n"
            + valid_claim_entry(
                broker_module.RESEARCH_DOSSIER_MAX_CLAIM_ENTRIES + 1
            )
        )
        validation = rejected.network_summary(
            with_claim_section(
                valid_dossier(rejected),
                excessive_claims,
            )
        )["submissionValidation"]
        self.assertFalse(validation["accepted"])
        self.assertEqual(
            validation["claimEntryCount"],
            broker_module.RESEARCH_DOSSIER_MAX_CLAIM_ENTRIES + 1,
        )
        self.assertIn(
            "claim_entry_limit",
            validation["violationCodeCounts"],
        )

    def test_maximum_candidate_diagnostics_and_event_payload_are_bounded(
        self,
    ) -> None:
        instance, _ = self.make_submission_broker()
        base = with_claim_section(
            valid_dossier(instance),
            valid_claim_entry(),
        )
        malformed_line = "   Unexpected label: MALFORMED-CANDIDATE-SENTINEL\n"
        available = (
            broker_module.RESEARCH_DOSSIER_MAX_BYTES
            - len(base.encode("utf-8"))
            - 1
        )
        repeated = malformed_line * (available // len(malformed_line))
        candidate = with_claim_section(
            valid_dossier(instance),
            valid_claim_entry() + "\n" + repeated.rstrip("\n"),
        )
        self.assertLessEqual(
            len(candidate.encode("utf-8")),
            broker_module.RESEARCH_DOSSIER_MAX_BYTES,
        )
        self.assertGreater(
            len(candidate.encode("utf-8")),
            broker_module.RESEARCH_DOSSIER_MAX_BYTES - 4096,
        )

        result = instance.network_summary(candidate)
        validation = result["submissionValidation"]
        self.assertFalse(validation["accepted"])
        self.assertGreater(
            validation["violationCount"],
            broker_module.RESEARCH_DOSSIER_MAX_RETURNED_VIOLATIONS,
        )
        self.assertLessEqual(
            validation["violationCollectedCount"],
            broker_module.RESEARCH_DOSSIER_MAX_COLLECTED_VIOLATIONS,
        )
        self.assertLessEqual(
            validation["violationReturnedCount"],
            broker_module.RESEARCH_DOSSIER_MAX_RETURNED_VIOLATIONS,
        )
        self.assertEqual(
            validation["violationReturnedCount"],
            len(validation["violations"]),
        )
        self.assertEqual(
            validation["violationCount"],
            sum(validation["violationCodeCounts"].values()),
        )
        self.assertTrue(validation["violationsTruncated"])
        self.assertTrue(validation["violationCollectionTruncated"])
        self.assertIn(
            "claim_unknown_label",
            validation["violationCodeCounts"],
        )

        mcp_result = broker_module.McpServer(instance).tool_result(result)
        encoded_response = broker_module.canonical_json(mcp_result).encode(
            "utf-8"
        )
        self.assertLess(len(encoded_response), 64 * 1024)
        self.assertNotIn(
            "MALFORMED-CANDIDATE-SENTINEL",
            encoded_response.decode("utf-8"),
        )

        events = [
            json.loads(line)
            for line in instance.events_path.read_text(encoding="utf-8").splitlines()
        ]
        rejected_event = next(
            event
            for event in reversed(events)
            if event["Type"] == "research_dossier_validation_rejected"
        )
        self.assertNotIn("ViolationCodes", rejected_event)
        self.assertEqual(
            rejected_event["ViolationCount"],
            validation["violationCount"],
        )
        self.assertEqual(
            rejected_event["ViolationCodeCounts"],
            validation["violationCodeCounts"],
        )
        self.assertLessEqual(
            len(rejected_event["ViolationCodeCounts"]),
            broker_module.RESEARCH_DOSSIER_MAX_VIOLATION_CODE_COUNTS,
        )
        self.assertNotIn(
            "MALFORMED-CANDIDATE-SENTINEL",
            instance.events_path.read_text(encoding="utf-8"),
        )

    def test_submission_proof_binds_exact_final_reply(self) -> None:
        instance, _ = self.make_submission_broker()
        candidate = valid_dossier(
            instance,
            source_extra="\n   RAW-CANDIDATE-SENTINEL",
        )
        result = instance.network_summary(candidate)
        self.assertTrue(result["submissionValidation"]["accepted"])
        self.assertNotIn(
            "RAW-CANDIDATE-SENTINEL",
            instance.summary_path.read_text(encoding="utf-8"),
        )
        self.assertNotIn(
            "RAW-CANDIDATE-SENTINEL",
            instance.events_path.read_text(encoding="utf-8"),
        )
        reply_path = self.root / "reply.txt"
        summary_path = self.root / "submission-summary.json"
        reply_path.write_text(candidate, encoding="utf-8")
        summary_path.write_text(
            json.dumps(instance.summary()),
            encoding="utf-8",
        )
        self.assertEqual(
            broker_module.verify_research_submission_binding(
                reply_path,
                summary_path,
            ),
            broker_module.RESEARCH_SUBMISSION_REPLY_VERIFIED,
        )

        missing = instance.summary()
        missing.pop("ResearchSubmission")
        summary_path.write_text(json.dumps(missing), encoding="utf-8")
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.verify_research_submission_binding(
                reply_path,
                summary_path,
            )
        self.assertEqual(context.exception.code, "submission_proof_missing")

        mismatched = instance.summary()
        mismatched["ResearchSubmission"]["CandidateSha256"] = "0" * 64
        summary_path.write_text(json.dumps(mismatched), encoding="utf-8")
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.verify_research_submission_binding(
                reply_path,
                summary_path,
            )
        self.assertEqual(context.exception.code, "submission_proof_mismatch")

        leaked = instance.summary()
        leaked["ResearchSubmission"]["Candidate"] = candidate
        summary_path.write_text(json.dumps(leaked), encoding="utf-8")
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.verify_research_submission_binding(
                reply_path,
                summary_path,
            )
        self.assertEqual(context.exception.code, "submission_proof_invalid")

        mutations = (
            ("true", True),
            ("false", False),
            ("numeric-string", "1"),
            ("integral-float", 1.0),
            ("non-integral-float", 1.5),
            ("negative", -1),
            ("oversized", 10**30),
        )
        for key in (
            "ProtocolVersion",
            "AttemptLimit",
            "AttemptsUsed",
            "CandidateBytes",
        ):
            for label, mutation in mutations:
                with self.subTest(proof_field=key, mutation=label):
                    malformed = instance.summary()
                    malformed["ResearchSubmission"][key] = mutation
                    summary_path.write_text(
                        json.dumps(malformed),
                        encoding="utf-8",
                    )
                    with self.assertRaises(
                        broker_module.BrokerError
                    ) as context:
                        broker_module.verify_research_submission_binding(
                            reply_path,
                            summary_path,
                        )
                    self.assertEqual(
                        context.exception.code,
                        "submission_proof_invalid",
                    )
                    self.assertEqual(
                        context.exception.message,
                        "The accepted research submission proof is malformed",
                    )
                    self.assertEqual(context.exception.details, {})

    def test_accepted_candidate_is_persisted_and_binds_without_reply_reproduction(
        self,
    ) -> None:
        candidate_path = self.root / "runtime" / "accepted-dossier.txt"
        candidate_path.parent.mkdir(mode=0o700)
        instance, _ = self.make_submission_broker(
            accepted_candidate_path=candidate_path,
        )
        self.assertFalse(candidate_path.exists())
        rejected = instance.network_summary(
            valid_dossier(instance).replace(
                "RESEARCH SOURCE LANDSCAPE\n", "RESEARCH SOURCE LANDSCAPE\n\n"
            ).replace("TOP USER RETRIEVAL PRIORITIES\n", "TOP USER PRIORITIES\n")
        )
        self.assertFalse(rejected["ok"])
        self.assertFalse(candidate_path.exists())

        candidate = valid_dossier(
            instance,
            source_extra="\n   PERSISTED-CANDIDATE-SENTINEL",
        )
        accepted = instance.network_summary(candidate)
        self.assertTrue(accepted["ok"])
        canonical, _ = broker_module.canonicalize_research_dossier_candidate(
            candidate
        )
        self.assertEqual(candidate_path.read_bytes(), canonical)
        self.assertEqual(stat.S_IMODE(candidate_path.stat().st_mode), 0o600)
        self.assertFalse(
            list(candidate_path.parent.glob(".accepted-dossier.txt.*.tmp"))
        )
        summary_path = self.root / "persisted-summary.json"
        summary_path.write_text(json.dumps(instance.summary()), encoding="utf-8")

        exact_reply = self.root / "exact-reply.txt"
        exact_reply.write_text(candidate, encoding="utf-8")
        self.assertEqual(
            broker_module.verify_research_submission_binding(
                exact_reply, summary_path, candidate_path
            ),
            broker_module.RESEARCH_SUBMISSION_REPLY_VERIFIED,
        )

        # A Markdown-rendered or paraphrased final reply no longer discards the
        # validated research: the persisted accepted candidate is canonical.
        rendered_reply = self.root / "rendered-reply.txt"
        rendered_reply.write_text(
            " 1. " + candidate.replace("\n", "\n\x1b]8;;\x07"),
            encoding="utf-8",
        )
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(
                broker_module.verify_research_submission_binding(
                    rendered_reply, summary_path, candidate_path
                ),
                broker_module.RESEARCH_SUBMISSION_ACCEPTED_CANDIDATE,
            )
        self.assertIn("submission_reply_differs", stderr.getvalue())
        self.assertNotIn("PERSISTED-CANDIDATE-SENTINEL", stderr.getvalue())
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.verify_research_submission_binding(
                rendered_reply, summary_path
            )
        self.assertEqual(context.exception.code, "submission_reply_invalid")

        # A persisted candidate that no longer matches the proof is corruption
        # and fails closed even when the reply would have matched.
        candidate_path.write_bytes(canonical.replace(b"PERSISTED", b"ALTERED"))
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.verify_research_submission_binding(
                exact_reply, summary_path, candidate_path
            )
        self.assertEqual(
            context.exception.code, "submission_candidate_mismatch"
        )
        candidate_path.unlink()
        self.assertEqual(
            broker_module.verify_research_submission_binding(
                exact_reply, summary_path, candidate_path
            ),
            broker_module.RESEARCH_SUBMISSION_REPLY_VERIFIED,
        )

    def test_embedded_runner_integer_contract_accepts_broker_artifacts(
        self,
    ) -> None:
        instance, _ = self.make_submission_broker()
        candidate = valid_dossier(instance)
        accepted = instance.network_summary(candidate)
        self.assertTrue(accepted["ok"])
        instance.close()
        completed = self.run_embedded_validator(instance, candidate)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stdout, "")
        self.assertEqual(completed.stderr, "")

    def test_event_integer_contract_covers_every_broker_event_producer(
        self,
    ) -> None:
        contract = json.loads(
            EVENT_INTEGER_CONTRACT_PATH.read_text(encoding="utf-8")
        )
        tree = ast.parse(BROKER_PATH.read_text(encoding="utf-8"))
        produced_event_types = {
            node.args[0].value
            for node in ast.walk(tree)
            if (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "record_event"
                and node.args
                and isinstance(node.args[0], ast.Constant)
                and isinstance(node.args[0].value, str)
            )
        }
        self.assertEqual(produced_event_types, set(contract["events"]))
        self.assertEqual(
            broker_module.RESEARCH_DOSSIER_MAX_OBSERVED_CLAIM_ENTRIES,
            broker_module.RESEARCH_DOSSIER_MAX_BYTES
            // len("1. Claim:\n".encode("utf-8")),
        )
        rejected_claim_spec = next(
            spec
            for spec in contract["events"][
                "research_dossier_validation_rejected"
            ]["fields"]
            if spec["path"] == ["ClaimEntryCount"]
        )
        accepted_claim_spec = next(
            spec
            for spec in contract["events"][
                "research_dossier_validation_accepted"
            ]["fields"]
            if spec["path"] == ["ClaimEntryCount"]
        )
        self.assertEqual(
            rejected_claim_spec["maximumRef"],
            "maxObservedClaimEntries",
        )
        self.assertEqual(
            accepted_claim_spec["maximumRef"],
            "maxAcceptedClaimEntries",
        )

        instance, _ = self.make_broker([])
        with self.assertRaisesRegex(
            RuntimeError,
            "integer contract is incomplete",
        ):
            instance.record_event(
                "provider_disabled",
                {
                    "ProviderId": broker_module.WEB_PROVIDER_NONE,
                    "Interface": "search_public_web",
                    "UndeclaredCount": 1,
                },
            )
        with self.assertRaisesRegex(
            RuntimeError,
            "integer contract is invalid",
        ):
            instance.record_event(
                "provider_failed",
                {
                    "ProviderId": broker_module.WEB_PROVIDER_ID,
                    "Code": "provider_malformed_response",
                    "CandidateEntries": True,
                    "RejectedEntries": 0,
                },
            )
        runner = RUNNER.read_text(encoding="utf-8")
        self.assertIn(
            'RESEARCH_EVENT_INTEGER_CONTRACT="${SKILL_ROOT}/'
            'research-event-integers.json"',
            runner,
        )
        self.assertIn(
            "validate_event_integer_fields(event, event_count)",
            runner,
        )

    def test_reject_101_claims_then_accept_passes_downstream_validation(
        self,
    ) -> None:
        instance, candidate = self.make_integer_parity_broker()
        events = [
            json.loads(line)
            for line in instance.events_path.read_text(
                encoding="utf-8"
            ).splitlines()
        ]
        rejected = next(
            event
            for event in events
            if event["Type"] == "research_dossier_validation_rejected"
        )
        accepted = next(
            event
            for event in events
            if event["Type"] == "research_dossier_validation_accepted"
        )
        self.assertEqual(rejected["ClaimEntryCount"], 101)
        self.assertEqual(accepted["Attempt"], 2)
        self.assertLessEqual(
            accepted["ClaimEntryCount"],
            broker_module.RESEARCH_DOSSIER_MAX_CLAIM_ENTRIES,
        )
        completed = self.run_embedded_validator(instance, candidate)
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_downstream_event_integer_schema_mutation_matrix(self) -> None:
        instance, candidate = self.make_integer_parity_broker()
        base_events = [
            json.loads(line)
            for line in instance.events_path.read_text(
                encoding="utf-8"
            ).splitlines()
        ]
        contract = json.loads(
            EVENT_INTEGER_CONTRACT_PATH.read_text(encoding="utf-8")
        )

        def path_matches(contract_path, actual_path):
            return len(contract_path) == len(actual_path) and all(
                expected == "*" or expected == actual
                for expected, actual in zip(contract_path, actual_path)
            )

        def integer_paths(value, path=()):
            if type(value) is int:
                yield path
            elif isinstance(value, dict):
                for key, item in value.items():
                    yield from integer_paths(item, path + (key,))
            elif isinstance(value, list):
                for index, item in enumerate(value):
                    yield from integer_paths(item, path + (index,))

        def set_path(value, path, replacement):
            target = value
            for component in path[:-1]:
                target = target[component]
            target[path[-1]] = replacement

        expected_specs = {
            ("common", tuple(spec["path"]))
            for spec in contract["common"]
        }
        expected_specs.update(
            (event_type, tuple(spec["path"]))
            for event_type, definition in contract["events"].items()
            for spec in definition["fields"]
        )
        samples = {}
        for event_index, event in enumerate(base_events):
            event_type = event["Type"]
            specs = contract["events"][event_type]["fields"]
            for actual_path in integer_paths(event):
                common_spec = next(
                    (
                        spec
                        for spec in contract["common"]
                        if path_matches(spec["path"], actual_path)
                    ),
                    None,
                )
                if common_spec is not None:
                    samples.setdefault(
                        ("common", tuple(common_spec["path"])),
                        (event_index, actual_path),
                    )
                    continue
                event_spec = next(
                    (
                        spec
                        for spec in specs
                        if path_matches(spec["path"], actual_path)
                    ),
                    None,
                )
                self.assertIsNotNone(
                    event_spec,
                    f"undeclared integer path: {event_type}/{actual_path}",
                )
                samples.setdefault(
                    (event_type, tuple(event_spec["path"])),
                    (event_index, actual_path),
                )
        self.assertEqual(set(samples), expected_specs)

        mutations = (
            ("boolean", True, "must use an exact JSON integer"),
            ("string", "1", "must use an exact JSON integer"),
            ("float", 1.0, "must use an exact JSON integer"),
            ("negative", -1, "is outside its allowed integer range"),
            ("oversized", 10**30, "is outside its allowed integer range"),
        )
        for spec_key, (event_index, actual_path) in samples.items():
            for mutation_label, mutation, expected in mutations:
                with self.subTest(
                    event=spec_key[0],
                    path=spec_key[1],
                    mutation=mutation_label,
                ):
                    events = copy.deepcopy(base_events)
                    set_path(events[event_index], actual_path, mutation)
                    completed = self.run_embedded_validator(
                        instance,
                        candidate,
                        events=events,
                    )
                    self.assertNotEqual(completed.returncode, 0)
                    self.assertIn(expected, completed.stderr)
                    self.assertNotIn(json.dumps(mutation), completed.stderr)

    def test_downstream_event_integer_relationship_mutations(self) -> None:
        instance, candidate = self.make_integer_parity_broker()
        base_events = [
            json.loads(line)
            for line in instance.events_path.read_text(
                encoding="utf-8"
            ).splitlines()
        ]

        def event(events, event_type, *, code=None, first=True):
            matches = [
                value
                for value in events
                if (
                    value.get("Type") == event_type
                    and (code is None or value.get("Code") == code)
                )
            ]
            return matches[0] if first else matches[-1]

        cases = []

        events = copy.deepcopy(base_events)
        retrieval = event(events, "public_retrieval_succeeded")
        retrieval["Status"] = 201
        cases.append(
            (
                "retrieval-status-binding",
                events,
                "research retrieval event binding is invalid",
            )
        )

        events = copy.deepcopy(base_events)
        redirect = event(events, "redirect_followed")
        redirect["Status"] = 301
        cases.append(
            (
                "redirect-status-binding",
                events,
                "research redirect event binding is invalid",
            )
        )

        events = copy.deepcopy(base_events)
        early_observation = event(
            events,
            "network_summary_observed",
        )
        early_observation["SuccessfulPublicResponses"] = 0
        early_observation["LatestSuccessfulRetrievalSequence"] = None
        cases.append(
            (
                "observation-retrieval-binding",
                events,
                "research observation event contract is invalid",
            )
        )

        events = copy.deepcopy(base_events)
        response_event = event(events, "http_response")
        response_event["TimingsMs"]["ConnectAndHeaders"] = (
            response_event["TimingsMs"]["Total"] + 1
        )
        cases.append(
            (
                "response-timing-order",
                events,
                "research HTTP response event timings are invalid",
            )
        )

        events = copy.deepcopy(base_events)
        provider_event = event(events, "provider_failed")
        provider_event["RejectedEntries"] = (
            provider_event["CandidateEntries"] + 1
        )
        cases.append(
            (
                "provider-counter-order",
                events,
                "research provider event counters are invalid",
            )
        )

        events = copy.deepcopy(base_events)
        rejected = event(
            events,
            "research_dossier_validation_rejected",
        )
        rejected["CapabilityInspectionSequence"] = 1
        cases.append(
            (
                "rejection-workflow-snapshot",
                events,
                (
                    "research validation rejection event sequence binding "
                    "is invalid"
                ),
            )
        )

        events = copy.deepcopy(base_events)
        rejected = event(
            events,
            "research_dossier_validation_rejected",
        )
        rejected["CandidateRequestSequence"] = (
            rejected["CapabilityInspectionSequence"]
        )
        cases.append(
            (
                "rejection-candidate-binding",
                events,
                (
                    "research validation rejection event sequence binding "
                    "is invalid"
                ),
            )
        )

        events = copy.deepcopy(base_events)
        rejected = event(
            events,
            "research_dossier_validation_rejected",
        )
        rejected["ClaimEntryCount"] = (
            broker_module.RESEARCH_DOSSIER_MAX_CLAIM_ENTRIES
        )
        cases.append(
            (
                "rejection-claim-limit-binding",
                events,
                "research validation rejection event is invalid",
            )
        )

        events = copy.deepcopy(base_events)
        rejected = event(
            events,
            "research_dossier_validation_rejected",
        )
        rejected["ViolationsTruncated"] = not rejected[
            "ViolationsTruncated"
        ]
        cases.append(
            (
                "rejection-truncation-binding",
                events,
                "research validation rejection event is invalid",
            )
        )

        events = copy.deepcopy(base_events)
        replayed = event(
            events,
            "research_dossier_validation_replayed",
        )
        accepted = event(
            events,
            "research_dossier_validation_accepted",
        )
        replayed["CandidateRequestSequence"] = accepted[
            "CandidateRequestSequence"
        ]
        cases.append(
            (
                "replay-candidate-binding",
                events,
                (
                    "research validation replay event sequence binding "
                    "is invalid"
                ),
            )
        )

        events = copy.deepcopy(base_events)
        replayed = event(
            events,
            "research_dossier_validation_replayed",
        )
        replayed["Attempt"] = 1
        cases.append(
            (
                "replay-attempt-binding",
                events,
                "research validation attempt sequence is invalid",
            )
        )

        for label, events, expected in cases:
            with self.subTest(relationship=label):
                completed = self.run_embedded_validator(
                    instance,
                    candidate,
                    events=events,
                )
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn(expected, completed.stderr)

    def test_downstream_event_integer_valid_boundaries(self) -> None:
        instance, candidate = self.make_integer_parity_broker()
        base_events = [
            json.loads(line)
            for line in instance.events_path.read_text(
                encoding="utf-8"
            ).splitlines()
        ]

        def event(event_type, *, code=None, events=None):
            selected_events = events if events is not None else base_events
            return next(
                value
                for value in selected_events
                if (
                    value.get("Type") == event_type
                    and (code is None or value.get("Code") == code)
                )
            )

        def latest_prior_request_event(events, source, event_type):
            return max(
                (
                    value
                    for value in events
                    if (
                        value.get("Type") == event_type
                        and value.get("RequestId")
                        == source.get("RequestId")
                        and value["Sequence"] < source["Sequence"]
                    )
                ),
                key=lambda value: value["Sequence"],
            )

        boundary_cases = []
        timing_maximum = (
            instance.policy.total_timeout_seconds * 1000
            + 1000
        )
        for connect, total in ((0, 0), (timing_maximum, timing_maximum)):
            events = copy.deepcopy(base_events)
            response_event = event("http_response", events=events)
            response_event["TimingsMs"] = {
                "ConnectAndHeaders": connect,
                "Total": total,
            }
            boundary_cases.append((f"timings-{connect}-{total}", events))
        for cipher_bits in (None, 1, 65535):
            events = copy.deepcopy(base_events)
            tls_event = event("tls_handshake", events=events)
            tls_event["Tls"]["CipherBits"] = cipher_bits
            boundary_cases.append((f"cipher-{cipher_bits}", events))
        for verify_code in (0, 2147483647):
            events = copy.deepcopy(base_events)
            failure = event(
                "request_failed",
                code="tls_verification_failed",
                events=events,
            )
            failure["Details"]["verifyCode"] = verify_code
            boundary_cases.append((f"verify-code-{verify_code}", events))
        for cipher_bits in (None, 1, 65535):
            events = copy.deepcopy(base_events)
            failure = event(
                "request_failed",
                code="tls_verification_failed",
                events=events,
            )
            failure["Details"]["diagnosticHandshake"]["Certificate"][
                "CipherBits"
            ] = cipher_bits
            boundary_cases.append(
                (f"diagnostic-cipher-{cipher_bits}", events)
            )
        for port in (1, 65535):
            events = copy.deepcopy(base_events)
            failure = event(
                "request_failed",
                code="tls_port_forbidden",
                events=events,
            )
            failure["Details"]["port"] = port
            boundary_cases.append((f"rejected-port-{port}", events))
        for header_bytes in (
            instance.policy.max_header_bytes + 1,
            10 * 1024 * 1024,
        ):
            events = copy.deepcopy(base_events)
            failure = event(
                "request_failed",
                code="headers_too_large",
                events=events,
            )
            failure["Details"]["headerBytes"] = header_bytes
            boundary_cases.append(
                (f"header-bytes-{header_bytes}", events)
            )
        for status in (100, 599):
            events = copy.deepcopy(base_events)
            failure = event("request_failed", code="http_status", events=events)
            response_event = latest_prior_request_event(
                events,
                failure,
                "http_response",
            )
            response_event["Status"] = status
            failure["Details"]["status"] = status
            boundary_cases.append((f"status-{status}", events))
        for position in ("minimum", "maximum"):
            events = copy.deepcopy(base_events)
            failure = event(
                "request_failed",
                code="malformed_json",
                events=events,
            )
            response_event = latest_prior_request_event(
                events,
                failure,
                "http_response",
            )
            value = (
                1
                if position == "minimum"
                else response_event["WireBytes"] + 1
            )
            failure["Details"]["line"] = value
            failure["Details"]["column"] = value
            boundary_cases.append(
                (f"json-position-{position}", events)
            )
        for position, values in (
            ("minimum", [1, 0]),
            ("maximum", None),
        ):
            events = copy.deepcopy(base_events)
            failure = event(
                "request_failed",
                code="malformed_xml",
                events=events,
            )
            if values is None:
                response_event = latest_prior_request_event(
                    events,
                    failure,
                    "http_response",
                )
                maximum = response_event["WireBytes"] + 1
                values = [maximum, maximum]
            failure["Details"]["position"] = values
            boundary_cases.append(
                (f"xml-position-{position}", events)
            )
        for byte_count in (0, instance.policy.max_wire_bytes):
            events = copy.deepcopy(base_events)
            failure = event(
                "request_failed",
                code="unsupported_format",
                events=events,
            )
            response_event = latest_prior_request_event(
                events,
                failure,
                "http_response",
            )
            stored_event = latest_prior_request_event(
                events,
                failure,
                "unsupported_body_stored",
            )
            response_event["WireBytes"] = byte_count
            stored_event["Bytes"] = byte_count
            failure["Details"]["bytes"] = byte_count
            boundary_cases.append(
                (f"unsupported-bytes-{byte_count}", events)
            )
        for candidate_entries, rejected_entries in ((0, 0), (60, 60)):
            events = copy.deepcopy(base_events)
            provider_event = event(
                "provider_failed",
                events=events,
            )
            provider_event["CandidateEntries"] = candidate_entries
            provider_event["RejectedEntries"] = rejected_entries
            boundary_cases.append(
                (
                    (
                        "provider-counts-"
                        f"{candidate_entries}-{rejected_entries}"
                    ),
                    events,
                )
            )
        events = copy.deepcopy(base_events)
        rejected = event(
            "research_dossier_validation_rejected",
            events=events,
        )
        rejected["ClaimEntryCount"] = (
            broker_module.RESEARCH_DOSSIER_MAX_OBSERVED_CLAIM_ENTRIES
        )
        boundary_cases.append(("rejected-claim-observation-maximum", events))

        for label, events in boundary_cases:
            with self.subTest(boundary=label):
                completed = self.run_embedded_validator(
                    instance,
                    candidate,
                    events=events,
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_capability_confidence_requires_evidence_with_shared_punctuation(
        self,
    ) -> None:
        for punctuation in (".", ";", ":", ","):
            with self.subTest(punctuation=punctuation):
                instance, _ = self.make_submission_broker()
                candidate = valid_dossier(instance).replace(
                    (
                        "Confidence: High. Evidence basis: "
                        "approval-bound broker records."
                    ),
                    f"Confidence: High{punctuation} approval-bound broker records.",
                    1,
                )
                validation = instance.network_summary(candidate)[
                    "submissionValidation"
                ]
                self.assertTrue(validation["accepted"])

        instance, _ = self.make_submission_broker()
        unsupported = valid_dossier(instance).replace(
            (
                "Confidence: High. Evidence basis: "
                "approval-bound broker records."
            ),
            "Confidence: High",
            1,
        )
        validation = instance.network_summary(unsupported)[
            "submissionValidation"
        ]
        self.assertFalse(validation["accepted"])
        self.assertIn(
            "capability_confidence",
            validation["violationCodeCounts"],
        )

    def test_tls_failure_is_structured_source_evidence(self) -> None:
        error = broker_module.BrokerError(
            "tls_verification_failed",
            "TLS certificate or hostname verification failed",
            details={
                "verifyCode": None,
                "verifyMessage": None,
                "diagnosticHandshake": {
                    "Outcome": "certificate-recorded",
                    "Certificate": {"LeafSha256": "b" * 64},
                }
            },
        )
        instance, _ = self.make_broker([error])
        result = instance.fetch("https://example.org/")
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"]["code"], "tls_verification_failed")
        self.assertEqual(
            instance.summary()["TlsAnomalies"]["tls_verification_failed"], 1
        )

    def test_mcp_stdio_contract_exposes_exact_tools(self) -> None:
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700)
        network = self.root / "mcp-network"
        process = subprocess.Popen(
            [
                sys.executable,
                str(BROKER_PATH),
                "--policy",
                str(POLICY_PATH),
                "--scope",
                "2",
                "--cookies",
                "off",
                "--web-search-provider",
                "none",
                "--network-root",
                str(network),
                "--repository-url",
                "https://github.com/octocat/Hello-World",
                "--runtime-root",
                str(runtime),
                "--expected-policy-digest",
                self.none_policy.digest,
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "PYTHONDONTWRITEBYTECODE": "1",
            },
        )
        assert process.stdin and process.stdout

        def exchange(identifier: int, method: str, params: dict | None = None):
            process.stdin.write(
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": identifier,
                        "method": method,
                        "params": params or {},
                    }
                )
                + "\n"
            )
            process.stdin.flush()
            return json.loads(process.stdout.readline())

        initialized = exchange(
            1,
            "initialize",
            {"protocolVersion": broker_module.MCP_PROTOCOL_VERSION},
        )
        self.assertEqual(
            initialized["result"]["serverInfo"]["name"], broker_module.SERVER_NAME
        )
        tools = exchange(2, "tools/list")["result"]["tools"]
        self.assertEqual(
            [tool["name"] for tool in tools], list(broker_module.TOOL_NAMES)
        )
        summary_tool = next(
            tool
            for tool in tools
            if tool["name"] == "research_network_summary"
        )
        self.assertEqual(
            summary_tool["inputSchema"],
            {
                "type": "object",
                "properties": {
                    "candidate": {
                        "type": "string",
                        "minLength": 1,
                        "maxLength": broker_module.RESEARCH_DOSSIER_MAX_BYTES,
                    }
                },
                "additionalProperties": False,
            },
        )
        capabilities = exchange(
            3,
            "tools/call",
            {"name": "research_capabilities", "arguments": {}},
        )["result"]["structuredContent"]
        self.assertEqual(capabilities["health"], "ready")
        validation_result = exchange(
            4,
            "tools/call",
            {
                "name": "research_network_summary",
                "arguments": {"candidate": "not a dossier"},
            },
        )["result"]
        self.assertFalse(validation_result["isError"])
        validation = validation_result["structuredContent"][
            "submissionValidation"
        ]
        self.assertFalse(validation["accepted"])
        self.assertEqual(validation["attempt"], 1)
        self.assertTrue(validation["violations"])
        disabled = exchange(
            5,
            "tools/call",
            {
                "name": "search_public_web",
                "arguments": {"query": "fixture"},
            },
        )["result"]["structuredContent"]
        self.assertEqual(disabled["error"]["code"], "provider_disabled")
        process.stdin.close()
        self.assertEqual(process.wait(timeout=10), 0)
        stderr = process.stderr.read() if process.stderr else ""
        self.assertEqual(stderr, "")
        if process.stdout:
            process.stdout.close()
        if process.stderr:
            process.stderr.close()
        exit_state = json.loads((runtime / "broker-exit.json").read_text())
        self.assertTrue(exit_state["CleanExit"])
        self.assertFalse((runtime / "broker.pid").exists())

    def test_sigterm_records_clean_lifecycle_exit(self) -> None:
        runtime = self.root / "signal-runtime"
        runtime.mkdir(mode=0o700)
        network = self.root / "signal-network"
        process = subprocess.Popen(
            [
                sys.executable,
                str(BROKER_PATH),
                "--policy",
                str(POLICY_PATH),
                "--scope",
                "2",
                "--cookies",
                "off",
                "--web-search-provider",
                "none",
                "--network-root",
                str(network),
                "--repository-url",
                "https://github.com/octocat/Hello-World",
                "--runtime-root",
                str(runtime),
                "--expected-policy-digest",
                self.none_policy.digest,
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "PYTHONDONTWRITEBYTECODE": "1",
            },
        )
        assert process.stdin and process.stdout
        process.stdin.write(
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": broker_module.MCP_PROTOCOL_VERSION
                    },
                }
            )
            + "\n"
        )
        process.stdin.flush()
        self.assertEqual(
            json.loads(process.stdout.readline())["result"]["serverInfo"]["name"],
            broker_module.SERVER_NAME,
        )
        process.send_signal(signal.SIGTERM)
        self.assertEqual(process.wait(timeout=10), 0)
        stderr = process.stderr.read() if process.stderr else ""
        self.assertEqual(stderr, "")
        process.stdin.close()
        process.stdout.close()
        if process.stderr:
            process.stderr.close()
        exit_state = json.loads((runtime / "broker-exit.json").read_text())
        self.assertTrue(exit_state["CleanExit"])
        self.assertFalse((runtime / "broker.pid").exists())


class SnapshotBrokerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.snapshot = self.root / "snapshot"
        self.source = self.snapshot / "src"
        self.approved = self.root / "approved"
        self.runtime = self.root / "runtime"
        self.snapshot.mkdir(mode=0o700)
        self.source.mkdir(mode=0o700)
        self.approved.mkdir(mode=0o700)
        self.runtime.mkdir(mode=0o700)
        (self.snapshot / ".hidden").write_text("hidden\n", encoding="utf-8")
        (self.snapshot / "README.md").write_text(
            "Alpha\nbeta needle\nGamma needle\n",
            encoding="utf-8",
        )
        (self.source / "app.py").write_text(
            "print('needle')\nNeedle = 2\n",
            encoding="utf-8",
        )
        (self.source / "space name.txt").write_text(
            "ordinary text\n",
            encoding="utf-8",
        )
        (self.snapshot / "data.bin").write_bytes(b"text before\n\x00binary\n")
        (self.snapshot / "invalid.bin").write_bytes(b"\xffinvalid\n")
        self.dossier = self.approved / "research.txt"
        self.summary = self.approved / "research-summary.txt"
        self.dossier.write_text("sanitized dossier\n", encoding="utf-8")
        self.summary.write_text("sanitized network summary\n", encoding="utf-8")
        for path in self.snapshot.rglob("*"):
            os.chmod(path, 0o500 if path.is_dir() else 0o400)
        os.chmod(self.snapshot, 0o500)
        os.chmod(self.dossier, 0o400)
        os.chmod(self.summary, 0o400)
        self.manifest = self.runtime / "snapshot-grants.json"

    def tearDown(self) -> None:
        for path in sorted(self.root.rglob("*"), key=lambda item: len(item.parts), reverse=True):
            try:
                if path.is_symlink():
                    continue
                os.chmod(path, 0o700 if path.is_dir() else 0o600)
            except FileNotFoundError:
                pass
        self.temporary.cleanup()

    @staticmethod
    def file_grant(grant_id: str, path: pathlib.Path) -> dict[str, object]:
        payload = path.read_bytes()
        return {
            "Id": grant_id,
            "Kind": "file",
            "Path": str(path.resolve()),
            "SizeBytes": len(payload),
            "Sha256": hashlib.sha256(payload).hexdigest(),
        }

    def write_manifest(
        self,
        *,
        phase: str = "review",
        include_files: bool = False,
        file_paths: tuple[pathlib.Path, pathlib.Path] | None = None,
        policy_digest: str | None = None,
    ) -> pathlib.Path:
        grants: list[dict[str, object]] = [
            {
                "Id": broker_module.SNAPSHOT_TREE_GRANT_ID,
                "Kind": "tree",
                "Path": str(self.snapshot.resolve()),
            }
        ]
        if include_files:
            dossier, summary = file_paths or (self.dossier, self.summary)
            grants.extend(
                [
                    self.file_grant("research-dossier", dossier),
                    self.file_grant("research-network-summary", summary),
                ]
            )
        value = {
            "SchemaVersion": broker_module.SNAPSHOT_GRANT_SCHEMA_VERSION,
            "PolicyDigest": policy_digest or broker_module.snapshot_policy_digest(),
            "Phase": phase,
            "Grants": grants,
        }
        self.manifest.write_text(
            json.dumps(value, ensure_ascii=True, indent=2) + "\n",
            encoding="utf-8",
        )
        os.chmod(self.manifest, 0o600)
        return self.manifest

    def load_broker(
        self,
        *,
        phase: str = "review",
        include_files: bool = False,
    ):
        manifest = self.write_manifest(phase=phase, include_files=include_files)
        grant_set = broker_module.load_snapshot_grants(
            manifest,
            self.runtime,
            broker_module.snapshot_policy_digest(),
        )
        instance = broker_module.SnapshotBroker(grant_set)
        self.addCleanup(instance.close)
        return instance

    def test_snapshot_policy_and_tool_schemas_are_exact(self) -> None:
        description = broker_module.snapshot_policy_description()
        expected_digest = hashlib.sha256(
            broker_module.canonical_json(description).encode("utf-8")
        ).hexdigest()
        self.assertEqual(broker_module.snapshot_policy_digest(), expected_digest)
        self.assertEqual(description["Network"], "disabled")
        self.assertEqual(description["Resources"], "none")
        self.assertEqual(description["Prompts"], "none")
        self.assertEqual(
            description["GrantProfiles"],
            {
                "research": ["snapshot"],
                "review-snapshot-only": ["snapshot"],
                "review-with-research": [
                    "snapshot",
                    "research-dossier",
                    "research-network-summary",
                ],
                "report-repair": [],
            },
        )
        definitions = broker_module.snapshot_tool_definitions()
        self.assertEqual(
            [definition["name"] for definition in definitions],
            list(broker_module.SNAPSHOT_TOOL_NAMES),
        )
        for definition in definitions:
            self.assertFalse(definition["inputSchema"]["additionalProperties"])
            self.assertNotIn("url", json.dumps(definition).lower())

        described = subprocess.run(
            [sys.executable, str(BROKER_PATH), "--describe-snapshot-policy"],
            check=True,
            capture_output=True,
            text=True,
        )
        value = json.loads(described.stdout)
        self.assertEqual(value["PolicyDigest"], expected_digest)
        self.assertEqual(described.stderr, "")
        nul = subprocess.run(
            [
                sys.executable,
                str(BROKER_PATH),
                "--describe-snapshot-policy",
                "--describe-format",
                "nul",
            ],
            check=True,
            capture_output=True,
        )
        fields = nul.stdout.split(b"\0")
        self.assertEqual(fields[-1], b"")
        self.assertEqual(len(fields[:-1]), 16)
        self.assertEqual(fields[4].decode("ascii"), expected_digest)

    def test_snapshot_grant_profiles_and_manifest_validation(self) -> None:
        manifest = self.write_manifest(include_files=True)
        grant_set = broker_module.load_snapshot_grants(
            manifest,
            self.runtime,
            broker_module.snapshot_policy_digest(),
        )
        self.assertEqual(grant_set.phase, "review")
        self.assertEqual(
            sorted(grant_set.grants),
            ["research-dossier", "research-network-summary", "snapshot"],
        )
        grant_set.close()

        self.write_manifest(phase="research", include_files=True)
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.load_snapshot_grants(
                self.manifest,
                self.runtime,
                broker_module.snapshot_policy_digest(),
            )
        self.assertEqual(context.exception.code, "invalid_snapshot_grant_manifest")

        value = json.loads(self.manifest.read_text(encoding="utf-8"))
        value["Phase"] = "review"
        value["Grants"].pop()
        self.manifest.write_text(json.dumps(value), encoding="utf-8")
        os.chmod(self.manifest, 0o600)
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.load_snapshot_grants(
                self.manifest,
                self.runtime,
                broker_module.snapshot_policy_digest(),
            )
        self.assertEqual(context.exception.code, "invalid_snapshot_grant_manifest")

        self.write_manifest()
        os.chmod(self.manifest, 0o644)
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.load_snapshot_grants(
                self.manifest,
                self.runtime,
                broker_module.snapshot_policy_digest(),
            )
        self.assertEqual(context.exception.code, "invalid_snapshot_grant_manifest")
        os.chmod(self.manifest, 0o600)

        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.load_snapshot_grants(
                self.manifest,
                self.runtime,
                "0" * 64,
            )
        self.assertEqual(context.exception.code, "snapshot_policy_digest_mismatch")

        os.chmod(self.snapshot, 0o700)
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.load_snapshot_grants(
                self.manifest,
                self.runtime,
                broker_module.snapshot_policy_digest(),
            )
        self.assertEqual(context.exception.code, "writable_snapshot_grant")
        os.chmod(self.snapshot, 0o500)

        self.write_manifest(
            include_files=True,
            file_paths=(self.snapshot / "README.md", self.snapshot / ".hidden"),
        )
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.load_snapshot_grants(
                self.manifest,
                self.runtime,
                broker_module.snapshot_policy_digest(),
            )
        self.assertEqual(context.exception.code, "overlapping_snapshot_grant")

    def test_snapshot_list_read_and_search_are_bounded_and_paginated(self) -> None:
        instance = self.load_broker(include_files=True)
        capabilities = instance.capabilities()
        self.assertEqual(capabilities["Phase"], "review")
        self.assertEqual(
            [grant["Id"] for grant in capabilities["Grants"]],
            ["research-dossier", "research-network-summary", "snapshot"],
        )

        first_page = instance.list_paths("snapshot", "", None, False, 0, 2)
        self.assertEqual(
            [entry["Path"] for entry in first_page["Entries"]],
            [".hidden", "README.md"],
        )
        self.assertEqual(first_page["NextOffset"], 2)
        second_page = instance.list_paths(
            "snapshot", "", None, False, first_page["NextOffset"], 10
        )
        self.assertIn("data.bin", [entry["Path"] for entry in second_page["Entries"]])
        recursive = instance.list_paths("snapshot", "", "*.py", False, 0, 10)
        self.assertEqual(
            [entry["Path"] for entry in recursive["Entries"]],
            ["src/app.py"],
        )

        read = instance.read_text("snapshot", "README.md", 2, 1, 1024)
        self.assertEqual(read["Text"], "beta needle\n")
        self.assertEqual(read["NextLine"], 3)
        dossier = instance.read_text("research-dossier", None, 1, 10, 1024)
        self.assertEqual(dossier["Text"], "sanitized dossier\n")
        self.assertTrue(dossier["Complete"])
        repeated_dossier = instance.read_text(
            "research-dossier", None, 1, 10, 1024
        )
        self.assertEqual(repeated_dossier["Text"], dossier["Text"])
        with self.assertRaises(broker_module.BrokerError) as context:
            instance.read_text("snapshot", "README.md", 2, 1, 2)
        self.assertEqual(context.exception.code, "snapshot_read_window_too_small")

        first_matches = instance.search_text(
            "snapshot", "needle", "", None, True, 0, 2
        )
        self.assertEqual(
            [(match["Path"], match["Line"]) for match in first_matches["Matches"]],
            [("README.md", 2), ("README.md", 3)],
        )
        self.assertEqual(first_matches["NextOffset"], 2)
        self.assertEqual(first_matches["SkippedFileCount"], 2)
        next_matches = instance.search_text(
            "snapshot", "needle", "", None, True, 2, 2
        )
        self.assertEqual(
            [(match["Path"], match["Line"]) for match in next_matches["Matches"]],
            [("src/app.py", 1)],
        )
        insensitive = instance.search_text(
            "snapshot", "needle", "src", "*.py", False, 0, 10
        )
        self.assertEqual(len(insensitive["Matches"]), 2)
        for value in (first_page, read, first_matches):
            self.assertLessEqual(
                broker_module.snapshot_tool_result_size(value),
                broker_module.SNAPSHOT_RESOURCE_POLICY["MaxResponseBytes"],
            )

    def test_snapshot_rejects_unsafe_entries_paths_mutation_and_budget(self) -> None:
        instance = self.load_broker(include_files=True)
        for path in ("../README.md", "/etc/passwd", ".git/config", "src//app.py"):
            with self.subTest(path=path):
                with self.assertRaises(broker_module.BrokerError):
                    instance.read_text("snapshot", path, 1, 10, 1024)
        with self.assertRaises(broker_module.BrokerError):
            instance.list_paths("snapshot", "\ud800", None, True, 0, 10)
        with self.assertRaises(broker_module.BrokerError):
            instance.search_text("snapshot", "\ud800", "", None, True, 0, 10)
        with self.assertRaises(broker_module.BrokerError):
            instance.read_text("research-dossier", "README.md", 1, 10, 1024)

        os.chmod(self.dossier, 0o600)
        self.dossier.write_text("changed after grant\n", encoding="utf-8")
        os.chmod(self.dossier, 0o400)
        with self.assertRaises(broker_module.BrokerError) as context:
            instance.read_text("research-dossier", None, 1, 10, 1024)
        self.assertEqual(context.exception.code, "snapshot_grant_changed")

        os.chmod(self.source, 0o700)
        with self.assertRaises(broker_module.BrokerError) as context:
            instance.read_text("snapshot", "src/app.py", 1, 10, 1024)
        self.assertEqual(context.exception.code, "writable_snapshot_grant")
        with self.assertRaises(broker_module.BrokerError) as context:
            instance.list_paths("snapshot", "", "*", True, 0, 100)
        self.assertEqual(context.exception.code, "writable_snapshot_grant")
        os.chmod(self.source, 0o500)

        os.chmod(self.snapshot, 0o700)
        (self.snapshot / "escape").symlink_to(self.root / "approved")
        os.chmod(self.snapshot, 0o500)
        with self.assertRaises(broker_module.BrokerError) as context:
            instance.list_paths("snapshot", "", "*", True, 0, 100)
        self.assertEqual(context.exception.code, "snapshot_symlink_detected")

        instance.tool_calls = broker_module.SNAPSHOT_RESOURCE_POLICY["MaxToolCalls"]
        with self.assertRaises(broker_module.BrokerError) as context:
            instance.capabilities()
        self.assertEqual(context.exception.code, "snapshot_call_budget_exhausted")

    def test_snapshot_manifest_rejects_json_type_confusion_and_duplicate_keys(self) -> None:
        for field, invalid in (
            ("SchemaVersion", True),
            ("SchemaVersion", 1.0),
            ("Phase", []),
            ("Phase", {}),
        ):
            with self.subTest(field=field, invalid=invalid):
                self.write_manifest()
                value = json.loads(self.manifest.read_text(encoding="utf-8"))
                value[field] = invalid
                self.manifest.write_text(json.dumps(value), encoding="utf-8")
                with self.assertRaises(broker_module.BrokerError):
                    broker_module.load_snapshot_grants(
                        self.manifest, self.runtime, broker_module.snapshot_policy_digest()
                    )
        for invalid in (None, [], {}, True, 5):
            with self.subTest(grant_id=invalid):
                self.write_manifest()
                value = json.loads(self.manifest.read_text(encoding="utf-8"))
                value["Grants"][0]["Id"] = invalid
                self.manifest.write_text(json.dumps(value), encoding="utf-8")
                with self.assertRaises(broker_module.BrokerError):
                    broker_module.load_snapshot_grants(
                        self.manifest, self.runtime, broker_module.snapshot_policy_digest()
                    )
        self.write_manifest()
        payload = self.manifest.read_text(encoding="utf-8")
        self.manifest.write_text(
            payload.replace('"SchemaVersion": 1', '"SchemaVersion": 1, "SchemaVersion": 1'),
            encoding="utf-8",
        )
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.load_snapshot_grants(
                self.manifest, self.runtime, broker_module.snapshot_policy_digest()
            )
        self.assertEqual(context.exception.code, "invalid_snapshot_json")

    def test_snapshot_rejects_hardlinks_and_special_files_without_blocking(self) -> None:
        instance = self.load_broker()
        os.chmod(self.snapshot, 0o700)
        os.link(self.snapshot / "README.md", self.approved / "outside-hardlink.txt")
        fifo = self.snapshot / "pipe"
        os.mkfifo(fifo, mode=0o400)
        os.chmod(self.snapshot, 0o500)
        with self.assertRaises(broker_module.BrokerError) as context:
            instance.read_text("snapshot", "README.md", 1, 10, 1024)
        self.assertEqual(context.exception.code, "snapshot_hardlink_detected")
        # O_NONBLOCK ensures a regular-file check cannot wait for a FIFO writer.
        with self.assertRaises(broker_module.BrokerError) as context:
            instance.read_text("snapshot", "pipe", 1, 10, 1024)
        self.assertEqual(context.exception.code, "invalid_snapshot_path")

    def test_snapshot_mcp_rejects_malformed_and_oversized_framing(self) -> None:
        self.write_manifest()
        launcher = [
            str(SNAPSHOT_BROKER_LAUNCHER), "--runtime-root", str(self.runtime.resolve()),
            "--grant-manifest", str(self.manifest.resolve()),
            "--expected-policy-digest", broker_module.snapshot_policy_digest(),
        ]
        maximum = broker_module.SNAPSHOT_RESOURCE_POLICY["MaxMcpRequestBytes"]
        for payload in (
            b"x" * (maximum + 1) + b"\n",
            f"Content-Length: {maximum + 1}\n\n".encode("ascii"),
            b"Content-Length: -1\n\n",
            b"Content-Length: 4\nContent-Length: 4\n\nnull",
            b'{"jsonrpc":"2.0","id":1,"id":2,"method":"ping"}\n',
            b'{"jsonrpc":"2.0","id":NaN,"method":"ping"}\n',
        ):
            with self.subTest(payload_prefix=payload[:40]):
                (self.runtime / "snapshot-broker-process.txt").unlink(missing_ok=True)
                (self.runtime / "snapshot-broker-exit.json").unlink(missing_ok=True)
                completed = subprocess.run(
                    launcher, input=payload, capture_output=True, timeout=10
                )
                self.assertEqual(completed.returncode, 2)
                self.assertEqual(completed.stdout, b"")
                self.assertIn(b"invalid_mcp_message", completed.stderr)
                self.assertFalse((self.runtime / "snapshot-broker.pid").exists())
                exit_state = json.loads(
                    (self.runtime / "snapshot-broker-exit.json").read_text(encoding="utf-8")
                )
                self.assertFalse(exit_state["CleanExit"])

    def test_snapshot_mcp_validates_types_before_dispatch(self) -> None:
        instance = self.load_broker(include_files=True)
        server = broker_module.SnapshotMcpServer(instance)
        for params in ([], None, False, "invalid"):
            result = server.handle(
                {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": params}
            )
            self.assertEqual(result["error"]["code"], -32600)
        for arguments in ([], None, False, "invalid"):
            result = server.handle(
                {
                    "jsonrpc": "2.0", "id": 1, "method": "tools/call",
                    "params": {"name": "snapshot_capabilities", "arguments": arguments},
                }
            )
            self.assertTrue(result["result"]["isError"])
        for path in ([], {}):
            with self.assertRaises(broker_module.BrokerError):
                instance.read_text("research-dossier", path, 1, 10, 1024)

    def prepare_trusted_bash_transport(self, *, include_files: bool = False, phase: str = "review"):
        workspace = self.root / "workspace"
        output = self.root / "output"
        harness_home = self.root / "harness-home"
        session = workspace / "fixture-session"
        workspace.mkdir(mode=0o700)
        output.mkdir(mode=0o700)
        harness_home.mkdir(mode=0o700)
        session.mkdir(mode=0o700)
        os.chmod(self.snapshot, 0o700)
        self.snapshot.rename(session / "source")
        self.snapshot = session / "source"
        os.chmod(self.snapshot, 0o500)
        self.source = self.snapshot / "src"
        evidence = session / "research-evidence"
        self.approved.rename(evidence)
        self.approved = evidence
        self.dossier = evidence / "research.txt"
        self.summary = evidence / "network-summary.json"
        (evidence / "research-summary.txt").rename(self.summary)
        self.runtime.rename(self.root / "rhyolite-snapshot-read.fixture")
        self.runtime = self.root / "rhyolite-snapshot-read.fixture"
        self.manifest = self.runtime / "snapshot-grants.json"
        arguments = [
            str(self.runtime), phase, str(self.snapshot), broker_module.snapshot_policy_digest(),
            str(workspace), str(output), str(harness_home),
        ]
        if include_files:
            arguments += [str(self.dossier), str(self.summary)]
        return arguments

    def run_snapshot_helper(self, operation: str, *arguments: str):
        script = '''
set -euo pipefail
source "$1"
operation="$2"
shift 2
if [[ "${operation}" == prepare ]]; then
    declare -a broker_arguments=()
    snapshot_transport_prepare broker_arguments "$@"
    printf '%s\\0' "${broker_arguments[@]}"
elif [[ "${operation}" == wait-idle ]]; then
    snapshot_transport_wait_idle "$@"
else
    snapshot_transport_cleanup "$@"
fi
'''
        return subprocess.run(
            ["bash", "-c", script, "snapshot-test", str(SNAPSHOT_TRANSPORT_HELPER), operation, *arguments],
            capture_output=True, timeout=15,
        )

    def snapshot_lifecycle(self) -> tuple[int, str, str]:
        """Run one launcher lifecycle: initialize, then end the client input."""
        process = subprocess.Popen(
            [
                str(SNAPSHOT_BROKER_LAUNCHER),
                "--runtime-root", str(self.runtime.resolve()),
                "--grant-manifest", str(self.manifest.resolve()),
                "--expected-policy-digest", broker_module.snapshot_policy_digest(),
            ],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        request = json.dumps({
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": broker_module.MCP_PROTOCOL_VERSION},
        }) + "\n"
        stdout, stderr = process.communicate(request, timeout=15)
        return process.returncode, stdout, stderr

    def test_snapshot_restart_in_same_runtime_requires_previous_clean_exit(self) -> None:
        # A resumed worker session restarts the broker with the same approved
        # arguments, so a second lifecycle may follow only a clean first one.
        self.write_manifest()
        exit_record = self.runtime / "snapshot-broker-exit.json"
        identity = self.runtime / "snapshot-broker-process.txt"
        identities = []
        for _ in range(2):
            status, stdout, stderr = self.snapshot_lifecycle()
            self.assertEqual((status, stderr), (0, ""))
            self.assertEqual(
                json.loads(stdout.splitlines()[0])["result"]["serverInfo"]["name"],
                broker_module.SNAPSHOT_SERVER_NAME,
            )
            self.assertTrue(json.loads(exit_record.read_text(encoding="utf-8"))["CleanExit"])
            self.assertFalse((self.runtime / "snapshot-broker.pid").exists())
            identities.append(identity.read_text(encoding="ascii"))
        self.assertNotEqual(identities[0], identities[1])
        for previous in ("unclean", "unrecorded"):
            if previous == "unclean":
                value = json.loads(exit_record.read_text(encoding="utf-8"))
                value["CleanExit"] = False
                exit_record.write_text(json.dumps(value), encoding="utf-8")
                os.chmod(exit_record, 0o600)
            else:
                exit_record.unlink()
            status, stdout, _ = self.snapshot_lifecycle()
            self.assertNotEqual(status, 0, previous)
            self.assertNotIn("serverInfo", stdout)
            # The refused lifecycle records its own unclean exit.
            self.assertFalse(json.loads(exit_record.read_text(encoding="utf-8"))["CleanExit"])
            self.assertEqual(identity.read_text(encoding="ascii"), identities[1])

    def test_snapshot_bash_wait_idle_requires_finished_clean_lifecycle(self) -> None:
        self.write_manifest()
        root = str(self.runtime.resolve())
        digest = broker_module.snapshot_policy_digest()
        self.assertEqual(self.run_snapshot_helper("wait-idle", root, digest, "review", "1").returncode, 0)
        status, _, stderr = self.snapshot_lifecycle()
        self.assertEqual((status, stderr), (0, ""))
        idle = self.run_snapshot_helper("wait-idle", root, digest, "review", "1")
        self.assertEqual(idle.returncode, 0, idle.stderr.decode())
        self.assertNotEqual(self.run_snapshot_helper("wait-idle", root, digest, "research", "1").returncode, 0)
        pid_file = self.runtime / "snapshot-broker.pid"
        pid_file.write_text("1\n", encoding="ascii")
        os.chmod(pid_file, 0o600)
        started = time.monotonic()
        self.assertNotEqual(self.run_snapshot_helper("wait-idle", root, digest, "review", "1").returncode, 0)
        self.assertGreaterEqual(time.monotonic() - started, 1.0)
        pid_file.unlink()
        exit_record = self.runtime / "snapshot-broker-exit.json"
        value = json.loads(exit_record.read_text(encoding="utf-8"))
        value["CleanExit"] = False
        exit_record.write_text(json.dumps(value), encoding="utf-8")
        os.chmod(exit_record, 0o600)
        self.assertNotEqual(self.run_snapshot_helper("wait-idle", root, digest, "review", "1").returncode, 0)

    def test_snapshot_bash_grants_only_runner_source_and_sanitized_file_pair(self) -> None:
        arguments = self.prepare_trusted_bash_transport(include_files=True)
        completed = self.run_snapshot_helper("prepare", *arguments)
        self.assertEqual(completed.returncode, 0, completed.stderr.decode())
        launcher_arguments = [item.decode() for item in completed.stdout.split(b"\0")[:-1]]
        self.assertEqual(launcher_arguments, [
            "--runtime-root", str(self.runtime), "--grant-manifest", str(self.manifest),
            "--expected-policy-digest", broker_module.snapshot_policy_digest(),
        ])
        grants = broker_module.load_snapshot_grants(
            self.manifest, self.runtime, broker_module.snapshot_policy_digest()
        )
        self.assertEqual(set(grants.grants), {"snapshot", "research-dossier", "research-network-summary"})
        grants.close()
        self.assertEqual(stat.S_IMODE(self.manifest.stat().st_mode), 0o600)
        cleanup = self.run_snapshot_helper("cleanup", str(self.runtime), broker_module.snapshot_policy_digest(), "review")
        self.assertEqual(cleanup.returncode, 0, cleanup.stderr.decode())
        self.assertFalse(self.runtime.exists())
        self.assertEqual(self.run_snapshot_helper("cleanup", str(self.runtime), broker_module.snapshot_policy_digest(), "review").returncode, 0)

    def test_snapshot_bash_rejects_arbitrary_and_private_grants(self) -> None:
        arguments = self.prepare_trusted_bash_transport(include_files=True)
        for index, bad_value in (
            (1, "report-repair"),
            (1, "research"),
            (2, str(self.root / "output")),
            (2, str(self.root / "harness-home")),
            (2, str(self.root)),
            (7, str(self.root / "output" / "private-evidence.txt")),
            (8, ""),
        ):
            with self.subTest(index=index, value=bad_value):
                altered = list(arguments)
                altered[index] = bad_value
                completed = self.run_snapshot_helper("prepare", *altered)
                self.assertNotEqual(completed.returncode, 0)
                self.assertFalse(self.manifest.exists())
        os.chmod(self.source, 0o700)
        self.assertNotEqual(self.run_snapshot_helper("prepare", *arguments).returncode, 0)
        os.chmod(self.source, 0o500)
        inventory = self.runtime / ".tree-inventory"
        inventory.unlink(missing_ok=True)
        os.chmod(self.snapshot, 0o700)
        (self.snapshot / ".git").mkdir(mode=0o500)
        os.chmod(self.snapshot, 0o500)
        self.assertNotEqual(self.run_snapshot_helper("prepare", *arguments).returncode, 0)

    def test_snapshot_bash_cleanup_verifies_identity_and_graceful_exit(self) -> None:
        arguments = self.prepare_trusted_bash_transport()
        completed = self.run_snapshot_helper("prepare", *arguments)
        self.assertEqual(completed.returncode, 0, completed.stderr.decode())
        launcher_arguments = [item.decode() for item in completed.stdout.split(b"\0")[:-1]]
        process = subprocess.Popen(
            [str(SNAPSHOT_BROKER_LAUNCHER), *launcher_arguments],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            assert process.stdin and process.stdout
            process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "ping"}) + "\n")
            process.stdin.flush()
            self.assertEqual(json.loads(process.stdout.readline())["result"], {})
            identity = self.runtime / "snapshot-broker-process.txt"
            expected = identity.read_text(encoding="ascii")
            fields = expected.splitlines()
            fields[1] = "0"
            identity.write_text("\n".join(fields) + "\n", encoding="ascii")
            failed = self.run_snapshot_helper("cleanup", str(self.runtime), broker_module.snapshot_policy_digest(), "review")
            self.assertNotEqual(failed.returncode, 0)
            self.assertIsNone(process.poll())
            identity.write_text(expected, encoding="ascii")
            cleanup = self.run_snapshot_helper("cleanup", str(self.runtime), broker_module.snapshot_policy_digest(), "review")
            self.assertEqual(cleanup.returncode, 0, cleanup.stderr.decode())
            self.assertEqual(process.wait(timeout=5), 0)
            self.assertFalse(self.runtime.exists())
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream:
                    stream.close()

    def test_snapshot_mcp_launcher_exposes_only_offline_tools_and_minimal_env(self) -> None:
        self.write_manifest()
        process = subprocess.Popen(
            [
                str(SNAPSHOT_BROKER_LAUNCHER),
                "--runtime-root",
                str(self.runtime.resolve()),
                "--grant-manifest",
                str(self.manifest.resolve()),
                "--expected-policy-digest",
                broker_module.snapshot_policy_digest(),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                **os.environ,
                "RHYOLITE_FAKE_CREDENTIAL": "must-not-survive",
                "HTTPS_PROXY": "http://127.0.0.1:9",
                "OPENAI_API_KEY": "fixture-only",
            },
        )
        assert process.stdin and process.stdout

        def exchange(identifier: int, method: str, params: dict | None = None):
            process.stdin.write(
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": identifier,
                        "method": method,
                        "params": params or {},
                    }
                )
                + "\n"
            )
            process.stdin.flush()
            return json.loads(process.stdout.readline())

        initialized = exchange(
            1,
            "initialize",
            {"protocolVersion": broker_module.MCP_PROTOCOL_VERSION},
        )
        self.assertEqual(
            initialized["result"]["serverInfo"],
            {
                "name": broker_module.SNAPSHOT_SERVER_NAME,
                "version": broker_module.SNAPSHOT_BROKER_VERSION,
            },
        )
        tools = exchange(2, "tools/list")["result"]["tools"]
        self.assertEqual(
            [tool["name"] for tool in tools],
            list(broker_module.SNAPSHOT_TOOL_NAMES),
        )
        self.assertEqual(exchange(3, "resources/list")["result"], {"resources": []})
        self.assertEqual(
            exchange(4, "resources/templates/list")["result"],
            {"resourceTemplates": []},
        )
        self.assertEqual(exchange(5, "prompts/list")["result"], {"prompts": []})
        capabilities = exchange(
            6,
            "tools/call",
            {"name": "snapshot_capabilities", "arguments": {}},
        )["result"]["structuredContent"]
        self.assertEqual(capabilities["Network"], "disabled")
        rejected = exchange(
            7,
            "tools/call",
            {"name": "research_capabilities", "arguments": {}},
        )["result"]
        self.assertTrue(rejected["isError"])
        self.assertEqual(
            rejected["structuredContent"]["error"]["code"],
            "unknown_tool",
        )
        unknown_argument = exchange(
            8,
            "tools/call",
            {
                "name": "list_snapshot_paths",
                "arguments": {"grant": "snapshot", "url": "https://example.org"},
            },
        )["result"]
        self.assertTrue(unknown_argument["isError"])
        for identifier, path in enumerate(
            (self.snapshot / "README.md", self.dossier),
            start=9,
        ):
            rejected_resource = exchange(
                identifier,
                "resources/read",
                {"uri": path.as_uri()},
            )
            self.assertEqual(rejected_resource["error"]["code"], -32601)
            self.assertNotIn(str(path), json.dumps(rejected_resource))

        environ = pathlib.Path(f"/proc/{process.pid}/environ").read_bytes().split(b"\0")
        environment_names = {
            entry.split(b"=", 1)[0].decode("ascii")
            for entry in environ
            if entry
        }
        self.assertEqual(
            environment_names,
            {
                "HOME",
                "LANG",
                "LC_ALL",
                "PATH",
                "PYTHONDONTWRITEBYTECODE",
                "PYTHONHASHSEED",
                "PYTHONNOUSERSITE",
                "PYTHONSAFEPATH",
                "TMPDIR",
                "XDG_CACHE_HOME",
                "XDG_CONFIG_HOME",
                "XDG_STATE_HOME",
            },
        )
        process.stdin.close()
        self.assertEqual(process.wait(timeout=10), 0)
        stderr = process.stderr.read() if process.stderr else ""
        self.assertEqual(stderr, "")
        process.stdout.close()
        if process.stderr:
            process.stderr.close()
        exit_state = json.loads(
            (self.runtime / "snapshot-broker-exit.json").read_text(encoding="utf-8")
        )
        self.assertTrue(exit_state["CleanExit"])
        self.assertEqual(exit_state["Phase"], "review")
        self.assertFalse((self.runtime / "snapshot-broker.pid").exists())
        self.assertFalse(any(path.name == "events.jsonl" for path in self.root.rglob("*")))

        rejected_launcher = subprocess.run(
            [str(SNAPSHOT_BROKER_LAUNCHER), "--cookies", "ephemeral"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(rejected_launcher.returncode, 2)
        self.assertIn("unknown argument", rejected_launcher.stderr)

    def test_snapshot_supervisor_survives_client_group_shutdown(self) -> None:
        supervised_runtime = self.root / "rhyolite-snapshot-read.supervised"
        self.runtime.rename(supervised_runtime)
        self.runtime = supervised_runtime
        self.manifest = self.runtime / "snapshot-grants.json"
        self.write_manifest()
        stat_line = pathlib.Path(f"/proc/{os.getpid()}/stat").read_text(encoding="ascii")
        owner_start_time = stat_line.rsplit(") ", 1)[1].split()[19]
        process = subprocess.Popen(
            [
                str(SNAPSHOT_BROKER_LAUNCHER),
                "--runtime-root",
                str(self.runtime.resolve()),
                "--grant-manifest",
                str(self.manifest.resolve()),
                "--expected-policy-digest",
                broker_module.snapshot_policy_digest(),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
            env={
                **os.environ,
                "RHYOLITE_BROKER_OWNER_PID": str(os.getpid()),
                "RHYOLITE_BROKER_OWNER_START_TIME": owner_start_time,
            },
        )
        try:
            assert process.stdin and process.stdout
            process.stdin.write(
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "initialize",
                        "params": {"protocolVersion": broker_module.MCP_PROTOCOL_VERSION},
                    }
                )
                + "\n"
            )
            process.stdin.flush()
            self.assertEqual(
                json.loads(process.stdout.readline())["result"]["serverInfo"]["name"],
                broker_module.SNAPSHOT_SERVER_NAME,
            )
            broker_pid = int(
                (self.runtime / "snapshot-broker.pid").read_text(encoding="ascii")
            )
            self.assertNotEqual(broker_pid, process.pid)
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
            process.stdin.close()
            deadline = time.monotonic() + 10
            exit_path = self.runtime / "snapshot-broker-exit.json"
            while time.monotonic() < deadline and not exit_path.exists():
                time.sleep(0.05)
            self.assertTrue(exit_path.exists())
            self.assertTrue(
                json.loads(exit_path.read_text(encoding="utf-8"))["CleanExit"]
            )
            with self.assertRaises(ProcessLookupError):
                os.kill(broker_pid, 0)
            cleanup = self.run_snapshot_helper(
                "cleanup",
                str(self.runtime),
                broker_module.snapshot_policy_digest(),
                "review",
            )
            self.assertEqual(cleanup.returncode, 0, cleanup.stderr.decode())
            self.assertFalse(self.runtime.exists())
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream and not stream.closed:
                    stream.close()

    def test_snapshot_bash_cleanup_rejects_another_broker_path(self) -> None:
        arguments = self.prepare_trusted_bash_transport()
        prepared = self.run_snapshot_helper("prepare", *arguments)
        self.assertEqual(prepared.returncode, 0, prepared.stderr.decode())
        other_directory = self.root / "other-broker"
        other_directory.mkdir(mode=0o700)
        other_broker = other_directory / BROKER_PATH.name
        other_broker.write_bytes(BROKER_PATH.read_bytes())
        process = subprocess.Popen(
            [
                "/usr/bin/python3", str(other_broker), "--snapshot-mode",
                "--runtime-root", str(self.runtime),
                "--snapshot-grant-manifest", str(self.manifest),
                "--expected-snapshot-policy-digest", broker_module.snapshot_policy_digest(),
            ],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True,
            env={"PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"},
        )
        try:
            assert process.stdin and process.stdout
            process.stdin.write(
                json.dumps({"jsonrpc": "2.0", "id": 1, "method": "ping"}) + "\n"
            )
            process.stdin.flush()
            self.assertEqual(json.loads(process.stdout.readline())["result"], {})
            rejected = self.run_snapshot_helper(
                "cleanup", str(self.runtime), broker_module.snapshot_policy_digest(), "review"
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("unverified broker process", rejected.stderr.decode())
            self.assertIsNone(process.poll())
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream:
                    stream.close()
        cleanup = self.run_snapshot_helper(
            "cleanup", str(self.runtime), broker_module.snapshot_policy_digest(), "review"
        )
        self.assertEqual(cleanup.returncode, 0, cleanup.stderr.decode())
        self.assertFalse(self.runtime.exists())

    def test_snapshot_sigterm_records_clean_lifecycle_exit(self) -> None:
        self.write_manifest(phase="research")
        process = subprocess.Popen(
            [
                str(SNAPSHOT_BROKER_LAUNCHER),
                "--runtime-root",
                str(self.runtime.resolve()),
                "--grant-manifest",
                str(self.manifest.resolve()),
                "--expected-policy-digest",
                broker_module.snapshot_policy_digest(),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert process.stdin and process.stdout
        process.stdin.write(
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {"protocolVersion": broker_module.MCP_PROTOCOL_VERSION},
                }
            )
            + "\n"
        )
        process.stdin.flush()
        self.assertEqual(
            json.loads(process.stdout.readline())["result"]["serverInfo"]["name"],
            broker_module.SNAPSHOT_SERVER_NAME,
        )
        process.send_signal(signal.SIGTERM)
        self.assertEqual(process.wait(timeout=10), 0)
        self.assertEqual(process.stderr.read() if process.stderr else "", "")
        process.stdin.close()
        process.stdout.close()
        if process.stderr:
            process.stderr.close()
        exit_state = json.loads(
            (self.runtime / "snapshot-broker-exit.json").read_text(encoding="utf-8")
        )
        self.assertTrue(exit_state["CleanExit"])
        self.assertEqual(exit_state["Phase"], "research")


class ResearchSelfValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        # Assemble the email fixture at runtime so the public-release
        # content audit does not flag this source.
        self.fixture_email = "@".join(("researcher", "example.org"))
        self.candidate = (
            f"{broker_module.RESEARCH_DOSSIER_DELIMITER}\n"
            "REPOSITORY RESEARCH DOSSIER\n"
            "RESEARCH CAPABILITY RECORD\n"
            f" Contact: {self.fixture_email}\n"
            " TOKEN: fixture-secret-value\n"
            f"{broker_module.RESEARCH_DOSSIER_DELIMITER}\n"
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_bash(self, script: str, *arguments: pathlib.Path | str) -> str:
        completed = subprocess.run(
            ["bash", "-c", script, "test", *(str(value) for value in arguments)],
            check=True,
            text=True,
            capture_output=True,
            env={
                **os.environ,
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            },
        )
        self.assertEqual(completed.stderr, "")
        return completed.stdout

    def test_raw_reply_binding_precedes_privacy_sanitization(self) -> None:
        raw = self.root / "raw-reply.txt"
        summary = self.root / "summary.json"
        sanitized = self.root / "sanitized-reply.txt"
        raw.write_text(self.candidate, encoding="utf-8")
        value = proof_summary(self.candidate)
        summary.write_text(json.dumps(value), encoding="utf-8")

        broker_module.verify_research_submission_binding(raw, summary)
        self.run_bash(
            'source "$1"; sanitize_review_text < "$2" > "$3"',
            OUTPUT_HELPER,
            raw,
            sanitized,
        )
        sanitized_text = sanitized.read_text(encoding="utf-8")
        self.assertIn("[email omitted]", sanitized_text)
        self.assertIn("TOKEN: [credential omitted]", sanitized_text)
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.verify_research_submission_binding(
                sanitized,
                summary,
            )
        self.assertEqual(context.exception.code, "submission_proof_mismatch")
        self.assertNotIn(self.fixture_email, summary.read_text())
        self.assertNotIn("fixture-secret-value", summary.read_text())

    def test_binding_cli_rejects_missing_and_mismatched_proof(self) -> None:
        reply = self.root / "reply.txt"
        summary = self.root / "summary.json"
        reply.write_text(self.candidate, encoding="utf-8")
        summary.write_text(json.dumps(proof_summary(self.candidate)))
        command = [
            sys.executable,
            str(BROKER_PATH),
            "--verify-submission-reply",
            str(reply),
            "--submission-summary",
            str(summary),
        ]
        accepted = subprocess.run(command, text=True, capture_output=True)
        self.assertEqual(accepted.returncode, 0)
        self.assertEqual(accepted.stdout, "reply-verified\n")
        self.assertEqual(accepted.stderr, "")

        summary.write_text("{}")
        missing = subprocess.run(command, text=True, capture_output=True)
        self.assertEqual(missing.returncode, 2)
        self.assertEqual(missing.stdout, "")
        self.assertIn("submission_proof_missing", missing.stderr)

        summary.write_text(json.dumps(proof_summary(self.candidate)))
        reply.write_text(self.candidate.replace("Contact:", "Contacts:"))
        mismatched = subprocess.run(command, text=True, capture_output=True)
        self.assertEqual(mismatched.returncode, 2)
        self.assertEqual(mismatched.stdout, "")
        self.assertIn("submission_proof_mismatch", mismatched.stderr)

        # With the broker's persisted accepted candidate the runner keeps the
        # validated dossier and records that the reply differed.
        persisted = self.root / "accepted-dossier.txt"
        canonical, _ = broker_module.canonicalize_research_dossier_candidate(
            self.candidate
        )
        persisted.write_bytes(canonical)
        with_candidate = [*command, "--accepted-candidate", str(persisted)]
        differed = subprocess.run(with_candidate, text=True, capture_output=True)
        self.assertEqual(
            differed.returncode,
            broker_module.RESEARCH_SUBMISSION_ACCEPTED_CANDIDATE_STATUS,
        )
        self.assertEqual(differed.stdout, "accepted-candidate\n")
        self.assertIn("submission_reply_differs", differed.stderr)
        self.assertNotIn("fixture-secret-value", differed.stderr)

        reply.write_text(self.candidate, encoding="utf-8")
        both = subprocess.run(with_candidate, text=True, capture_output=True)
        self.assertEqual(both.returncode, 0)
        self.assertEqual(both.stdout, "reply-verified\n")
        self.assertEqual(both.stderr, "")

        persisted.write_bytes(canonical + b"tampered\n")
        tampered = subprocess.run(with_candidate, text=True, capture_output=True)
        self.assertEqual(tampered.returncode, 2)
        self.assertEqual(tampered.stdout, "")
        self.assertIn("submission_candidate_mismatch", tampered.stderr)

        candidate_only = subprocess.run(
            [
                sys.executable,
                str(BROKER_PATH),
                "--accepted-candidate",
                str(persisted),
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(candidate_only.returncode, 2)
        self.assertIn("invalid_configuration", candidate_only.stderr)

    def normalize(
        self,
        adapter: pathlib.Path,
        phase: str,
        raw: pathlib.Path,
        model: str,
        effort: str,
        label: str,
    ) -> tuple[subprocess.CompletedProcess[str], pathlib.Path, pathlib.Path]:
        normalized = self.root / f"{label}-normalized.txt"
        reply = self.root / f"{label}-reply.txt"
        completed = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; source "$2"; '
                'harness_normalize_worker_output "$3" "$4" "$5" "$6" "$7" "$8" '
                '|| { status=$?; printf \'%s\' "${RHYOLITE_HARNESS_ERROR_DETAIL}" >&2; exit "${status}"; }',
                "test",
                str(HARNESS_COMMON),
                str(adapter),
                phase,
                str(raw),
                model,
                effort,
                str(normalized),
                str(reply),
            ],
            text=True,
            capture_output=True,
            env={**os.environ, "PATH": os.environ.get("PATH", "/usr/bin:/bin")},
        )
        return completed, normalized, reply

    def test_harnesses_normalize_exact_reply_not_rendered_output(self) -> None:
        raw = self.root / "raw.txt"
        raw.write_text(self.candidate, encoding="utf-8")
        for phase in ("review", "research", "report-repair"):
            with self.subTest(harness="claude", phase=phase):
                completed, normalized, reply = self.normalize(
                    CLAUDE_ADAPTER, phase, raw, "claude-opus-5.5", "max",
                    f"claude-{phase}",
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(reply.read_bytes(), raw.read_bytes())
                self.assertEqual(normalized.read_bytes(), raw.read_bytes())
                self.assertEqual(stat.S_IMODE(reply.stat().st_mode), 0o600)

        def event(kind: str, **data: object) -> str:
            return json.dumps({"type": kind, "data": data, "id": "x"})

        narration = "Collecting evidence before validation."
        structured = self.root / "copilot.jsonl"
        structured.write_text(
            "\n".join(
                [
                    event("session.tools_updated", tools=[]),
                    event("user.message", content="prompt"),
                    event("model.call_start", turnId="0", model="gpt-5.6-sol"),
                    event(
                        "assistant.message",
                        model="gpt-5.6-sol",
                        content=narration,
                        toolRequests=[{"name": "fetch_public_url"}],
                    ),
                    event(
                        "tool.execution_start",
                        toolName="fetch_public_url",
                        model="gpt-5.6-sol",
                    ),
                    event(
                        "assistant.message",
                        model="gpt-5.6-sol",
                        content=self.candidate.rstrip("\n"),
                        toolRequests=[],
                    ),
                    event("model.call_final_result", model="gpt-5.6-sol"),
                    event(
                        "session.usage_checkpoint",
                        promptCacheBreakState=[
                            {
                                "conversation": "main",
                                "models": {
                                    "gpt-5.6-sol": {
                                        "model": "gpt-5.6-sol",
                                        "reasoning_effort": "max",
                                    }
                                },
                            }
                        ],
                        accountingSnapshot={
                            "modelMetrics": {"gpt-5.6-sol": {}},
                            "agentMetrics": {"main": {"modelMetrics": {"gpt-5.6-sol": {}}}},
                        },
                    ),
                    json.dumps({"type": "result", "exitCode": 0}),
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        for phase in ("review", "research", "report-repair"):
            with self.subTest(harness="copilot", phase=phase):
                completed, normalized, reply = self.normalize(
                    COPILOT_ADAPTER, phase, structured, "gpt-5.6-sol", "max",
                    f"copilot-{phase}",
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(reply.read_bytes(), raw.read_bytes())
                self.assertEqual(stat.S_IMODE(reply.stat().st_mode), 0o600)
                text = normalized.read_text(encoding="utf-8")
                self.assertTrue(text.startswith(narration + "\n\n"))
                self.assertTrue(text.endswith(self.candidate))
                self.assertNotIn('"type"', text)
                self.assertEqual(
                    broker_module.verify_research_submission_binding(
                        reply,
                        self.write_proof_summary("copilot-structured"),
                    ),
                    broker_module.RESEARCH_SUBMISSION_REPLY_VERIFIED,
                )

        # Terminal-rendered Markdown (wrapped lines, re-indented lists, OSC 8
        # hyperlinks) is never treated as the assistant reply.
        rendered = self.root / "copilot-rendered.txt"
        rendered.write_text(
            " 1. wrapped line\n\x1b]8;id=1;https://example.org\x07link\x1b]8;;\x07\n",
            encoding="utf-8",
        )
        completed, normalized, reply = self.normalize(
            COPILOT_ADAPTER, "research", rendered, "gpt-5.6-sol", "max",
            "copilot-rendered",
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(reply.read_bytes(), b"")
        self.assertIn("wrapped line", normalized.read_text(encoding="utf-8"))

        for label, model, effort, fragment in (
            ("substituted", "gpt-5.5", "max", "substituted output"),
            ("effort", "gpt-5.6-sol", "high", "downgraded or substituted effort"),
        ):
            with self.subTest(copilot_rejection=label):
                completed, normalized, reply = self.normalize(
                    COPILOT_ADAPTER, "review", structured, model, effort,
                    f"copilot-{label}",
                )
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn(fragment, completed.stderr)
                self.assertFalse(normalized.exists())
                self.assertFalse(reply.exists())

        for label, arguments in (
            ("phase", ("bogus", str(structured), "gpt-5.6-sol", "max")),
            ("model", ("review", str(structured), "../x", "max")),
            ("effort", ("review", str(structured), "gpt-5.6-sol", "MAX!")),
        ):
            with self.subTest(copilot_argument=label):
                completed = subprocess.run(
                    [
                        "bash",
                        "-c",
                        'source "$1"; source "$2"; '
                        'harness_normalize_worker_output "$3" "$4" "$5" "$6" "$7" "$8"',
                        "test",
                        str(HARNESS_COMMON),
                        str(COPILOT_ADAPTER),
                        *arguments,
                        str(self.root / f"bad-{label}-normalized"),
                        str(self.root / f"bad-{label}-reply"),
                    ],
                    text=True,
                    capture_output=True,
                )
                self.assertNotEqual(completed.returncode, 0)

    def write_proof_summary(self, label: str) -> pathlib.Path:
        summary = self.root / f"{label}-summary.json"
        summary.write_text(json.dumps(proof_summary(self.candidate)))
        return summary

    def test_existing_tool_grant_accepts_optional_candidate_schema(self) -> None:
        definitions = broker_module.tool_definitions()
        self.assertEqual(
            [definition["name"] for definition in definitions],
            list(broker_module.TOOL_NAMES),
        )
        summary_tool = next(
            definition
            for definition in definitions
            if definition["name"] == "research_network_summary"
        )
        self.assertNotIn("required", summary_tool["inputSchema"])
        self.assertNotIn("oneOf", summary_tool["inputSchema"])
        self.assertNotIn("anyOf", summary_tool["inputSchema"])
        self.assertEqual(
            summary_tool["inputSchema"]["properties"]["candidate"]["type"],
            "string",
        )
        self.assertFalse(
            summary_tool["inputSchema"]["additionalProperties"],
        )

        tools_json = json.dumps(list(broker_module.TOOL_NAMES))
        expected_names = list(broker_module.TOOL_NAMES)
        for label, adapter in (
            ("copilot", COPILOT_ADAPTER),
            ("claude", CLAUDE_ADAPTER),
        ):
            with self.subTest(harness=label):
                config = self.root / f"{label}-mcp.json"
                self.run_bash(
                    (
                        'source "$1"; '
                        'arguments=(--scope 2); '
                        'harness_write_research_mcp_config '
                        '"$2" "$3" arguments "$4"'
                    ),
                    adapter,
                    config,
                    BROKER_LAUNCHER,
                    tools_json,
                )
                value = json.loads(config.read_text(encoding="utf-8"))
                server = value["mcpServers"]["rhyolite-research"]
                self.assertEqual(server["command"], str(BROKER_LAUNCHER))
                if label == "copilot":
                    self.assertEqual(server["tools"], expected_names)
                else:
                    allowed = self.run_bash(
                        'source "$1"; claude_research_allowed_tools "$2"',
                        adapter,
                        ",".join(expected_names),
                    )
                    self.assertEqual(
                        allowed,
                        ",".join(
                            f"mcp__rhyolite-research__{name}"
                            for name in expected_names
                        ),
                    )

    def test_owned_producer_instructions_keep_workflow_and_grammar_parity(
        self,
    ) -> None:
        exact_sequence = (
            "Call `research_capabilities` first. The broker call sequence is "
            "exact: (1) call `research_capabilities` and verify it; (2) only "
            "then use public retrieval tools and obtain at least one "
            "successful public response; (3) after the latest successful "
            "retrieval, call `research_network_summary` without `candidate`; "
            "and (4) only after that observation submit the complete dossier "
            "with `candidate`. A candidate-bearing call never counts as the "
            "required observation. Any later public retrieval makes the prior "
            "observation stale, so call the no-candidate summary again before "
            "validation. Corrections may reuse the fresh observation only "
            "while no further retrieval occurs, and all candidate submissions "
            "share the same three-attempt session limit."
        )
        for path in (
            RESEARCH_PROMPT,
            COPILOT_RESEARCH_AGENT,
            CLAUDE_RESEARCH_AGENT,
            RESEARCH_SOURCE_SKILL,
        ):
            with self.subTest(path=path.relative_to(ROOT)):
                normalized = " ".join(
                    path.read_text(encoding="utf-8").split()
                )
                self.assertIn(exact_sequence, normalized)
                self.assertIn(
                    "None identified: <non-empty basis>",
                    normalized,
                )
                self.assertIn("1 through 100 sequential", normalized)
                self.assertIn("project-controlled", normalized)
                self.assertIn("Not corroborated", normalized)
                self.assertIn("Not checkable", normalized)
                self.assertIn("U+000A LF", normalized)
                self.assertIn("U+0085", normalized)
                self.assertIn("U+2028", normalized)
                self.assertIn("U+2029", normalized)

    def test_runner_binds_accepted_candidate_before_sanitization_and_main_review(
        self,
    ) -> None:
        runner = RUNNER.read_text(encoding="utf-8")
        normalize = runner.index(
            "if ! rhyolite_harness_invoke harness_normalize_worker_output \\\n"
            "                research"
        )
        verify = runner.index("--verify-submission-reply", normalize)
        candidate = runner.index("--accepted-candidate", verify)
        sanitize = runner.index(
            '< "${research_dossier_source}"',
            candidate,
        )
        dossier = runner.index(
            '"${research_final_reply_sanitized}"',
            sanitize,
        )
        main_review = runner.index(
            "harness_worker_argv",
            dossier,
        )
        self.assertLess(normalize, verify)
        self.assertLess(verify, candidate)
        self.assertLess(candidate, sanitize)
        self.assertLess(sanitize, dossier)
        self.assertLess(dossier, main_review)
        self.assertNotIn("harness_extract_research_reply", runner)
        self.assertIn(
            'local research_final_reply_raw="${research_runtime_root}/final-reply.raw"',
            runner,
        )
        self.assertIn(
            'local research_accepted_candidate="${research_runtime_root}/accepted-dossier.txt"',
            runner,
        )
        self.assertIn("0:reply-verified)", runner)
        self.assertIn("3:accepted-candidate)", runner)
        self.assertIn(
            'RESEARCH_BROKER_RUNTIME_TO_CLEAN="${research_runtime_root}"',
            runner,
        )
        self.assertIn(
            'cleanup_research_runtime \\\n'
            '                    "${RESEARCH_BROKER_RUNTIME_TO_CLEAN}"',
            runner,
        )
        self.assertIn(
            "capability_lines = lines[positions[0] + 1 : positions[1]]",
            runner,
        )
        self.assertIn(
            '"research_dossier_validation_accepted" not in event_types',
            runner,
        )
        broker = BROKER_PATH.read_text(encoding="utf-8")
        self.assertIn(
            'accepted_candidate_path=runtime_root / "accepted-dossier.txt"',
            broker,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
