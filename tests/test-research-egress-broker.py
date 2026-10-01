#!/usr/bin/env python3

from __future__ import annotations

import dataclasses
import importlib.util
import json
import os
import pathlib
import signal
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
BROKER_PATH = (
    ROOT
    / "plugins/rhyolite/skills/readonly-repository-review/scripts"
    / "research-egress-broker.py"
)
POLICY_PATH = (
    ROOT
    / "plugins/rhyolite/skills/readonly-repository-review"
    / "research-policy.json"
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
            "LeafSha256": "a" * 64,
        },
        timings_ms={"ConnectAndHeaders": 1, "Total": 2},
        connected_address="93.184.216.34",
    )


class BrokerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.policy = broker_module.load_effective_policy(POLICY_PATH, 2, "none")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def make_broker(
        self,
        responses: list[object],
        *,
        cookie_mode: str = "off",
    ):
        transport = QueueTransport(responses)
        instance = broker_module.ResearchBroker(
            self.policy,
            self.root / f"network-{len(list(self.root.iterdir()))}",
            "https://github.com/octocat/Hello-World",
            cookie_mode,
            resolver=StaticResolver(["93.184.216.34"]),
            transport=transport,
            sleep=lambda seconds: None,
        )
        return instance, transport

    def test_policy_description_and_hard_limits(self) -> None:
        self.assertEqual(self.policy.request_budget, 500)
        self.assertEqual(self.policy.allowed_tls_ports, (443,))
        self.assertEqual(len(self.policy.digest), 64)
        raw = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
        raw["transport"]["maxWireBytes"] = 10 * 1024 * 1024 + 1
        unsafe = self.root / "unsafe.json"
        unsafe.write_text(json.dumps(raw), encoding="utf-8")
        with self.assertRaises(broker_module.BrokerError) as context:
            broker_module.load_effective_policy(unsafe, 2, "none")
        self.assertEqual(context.exception.code, "unsafe_policy")

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
            "https://user:pass@example.org/",
            "https://127.0.0.1/",
            "https://localhost/",
            "https://service.internal/",
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

    def test_web_search_interface_is_stably_disabled(self) -> None:
        instance, _ = self.make_broker([])
        result = instance.search_web("public research", 10)
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"]["code"], "provider_disabled")
        self.assertEqual(result["providerId"], "none")

    def test_tls_failure_is_structured_source_evidence(self) -> None:
        error = broker_module.BrokerError(
            "tls_verification_failed",
            "TLS certificate or hostname verification failed",
            details={
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
                self.policy.digest,
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
        capabilities = exchange(
            3,
            "tools/call",
            {"name": "research_capabilities", "arguments": {}},
        )["result"]["structuredContent"]
        self.assertEqual(capabilities["health"], "ready")
        disabled = exchange(
            4,
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
                self.policy.digest,
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
