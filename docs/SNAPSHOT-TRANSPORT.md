# Constrained snapshot-read transport

The October 20, 2026 project decision authorizes an offline stdio MCP mode
in the existing Python standard-library broker for the Codex workstream.
This transport foundation does not register Codex or establish production
harness support. Copilot and Claude Code continue to use their native
snapshot readers.

## Ownership and approval

Harness Contract v11 adds two required functions:

| Function | Exact interface |
| --- | --- |
| `harness_snapshot_transport` | No arguments; return exactly `native` or `local-stdio-mcp-snapshot-read-v1`. Unknown values fail before approval or execution. |
| `harness_configure_snapshot_transport` | Phase, approved worker argv array name, isolated harness home, new config path, fixed broker launcher, broker argument array name, and exact tool list as JSON. Populate only the worker's MCP configuration/argv; return status without printing data. |

The second function runs only for the offline transport, after the runner
has constructed the ordinary worker argv and isolated home. Research
already has its separately approved research MCP configuration; the adapter
must retain exactly that server and add only the snapshot server. Review
gets only the snapshot server. Repair gets neither function invocation nor
server. Continuations retain the same approved grants and configuration.
Native adapters explicitly reject offline configuration.

Bash owns canonical paths, grant creation, phase separation, process
lifecycle, timeout, cleanup, errors, and artifact finalization. The adapter
only translates this fixed interface into its verified CLI format. No
adapter may select another executable, server, endpoint, directory grant,
resource, prompt, or tool. A CLI's automatically exposed MCP resource
helpers must be proven unable to grant wider authority.

The plan's `SnapshotTransport` object is present only for offline MCP.
It contains `ContractVersion` (11), `Policy`, and `PolicyDigest`. `Policy`
includes the exact tools and input schemas, fixed limits, phase grant
profiles, network/environment constraints, and path rules. `PolicyDigest`
is SHA-256 of canonical ASCII JSON with sorted keys and compact separators,
excluding the digest itself. The whole object is approval-hash material and
appears in the saved plan, repository and research state, manifest, and run
state. Runtime paths and file contents are never approval identity.
Plan schema 5, state schema 6, and preference schema 3 retain their meanings;
the new transport member is an additive, harness-specific extension.
Native plans and states omit it. Retry policy separately discloses increasing
delays in `WorkerRecoveryPolicy.RetryBackoff` for every harness.
The advanced `RHYOLITE_WORKER_RETRY_DELAY_SECONDS` override accepts only a
whole number from 0 through 300 without leading zeros; invalid values fail
before planning or execution. A changed delay changes approval material, so
plan generation and execution must use the same setting. Leaving it unset
uses the 30-second default.

## Grants

The runner writes one current-user mode-0600 `snapshot-grants.json` in a
fresh current-user mode-0700 `rhyolite-snapshot-read.*` runtime directory.
Its exact keys are `SchemaVersion` (integer 1), `PolicyDigest`, `Phase`
(`review` or `research`), and `Grants`. Duplicate JSON keys, unknown fields,
boolean or floating-point versions, invalid identifiers, and mixed phases
are rejected.

One tree grant is required: `Id=snapshot`, `Kind=tree`, and the canonical
`Path` of one runner-created `<run workspace>/<repository>-session/source`
directory. Bash validates the complete tree before launch: current-user
ownership, no write bits, canonical separation from output/harness/broker
homes, no `.git` components, symbolic links, hard links, special files,
control characters, backslashes, or paths outside the approved depth/size
limits. Reads open each component relative to held directory descriptors
with `O_NOFOLLOW`; ordinary-file checks use nonblocking opens so a FIFO
cannot stall validation.

Independent security scans and their consolidation read relabelled scan
reports that no snapshot grant covers. A plan that combines this transport
with more than one security scan therefore fails before planning, and the
harness keeps the integrated security pass, which is identical in every
scope.

Research receives the tree alone. A review after successful research may
also receive the complete pair `research-dossier` and
`research-network-summary`. Each is an individual file grant with exact
`Id`, `Kind=file`, canonical `Path`, integer `SizeBytes`, and `Sha256`.
The only eligible files are the runner's validated, sanitized
`research-evidence/research.txt` and `research-evidence/network-summary.json`
copies adjacent to that session's source. The broker rechecks size, digest,
ownership, and read-only mode on access. No output directory, private
research body, cookie, authentication file, or arbitrary absolute path is
granted. Repair has no grants.

The review request names those trusted paths, which an offline-transport
worker cannot open. Its research transport instructions therefore tell that
worker to read the pair with `read_snapshot_text` using grant
`research-dossier` or `research-network-summary` and no path. The shared
worker instructions forbid every MCP tool other than the harness-supplied
read-only snapshot tools; native-transport requests keep the path
instructions.

## Model-visible tools

Every tool rejects unknown arguments. Paths are relative UTF-8 strings;
empty path selects the tree root only where stated. Individual file grants
accept no path. Integer fields reject booleans and floating-point values.

| Tool | Arguments and defaults | Result |
| --- | --- | --- |
| `snapshot_capabilities` | Empty object. | Fixed policy/digest, phase, grant identifiers, sizes/digests, and readiness; no absolute grant paths. |
| `list_snapshot_paths` | Required `grant=snapshot`; `path=""`, optional `glob`, `includeDirectories=true`, `offset=0`, `limit=200`. | Deterministic path/type/size entries, `NextOffset`, and explicit truncation. A glob triggers recursive traversal and uses case-sensitive `fnmatch` semantics over relative paths. |
| `read_snapshot_text` | Required `grant`; required nonempty `path` for the tree; `startLine=1`, `maxLines=200`, `maxBytes=65536`. | Complete UTF-8 lines, line range, original file/returned byte counts, `NextLine`, and completeness. Binary or invalid UTF-8 input fails explicitly. |
| `search_snapshot_text` | Required `grant=snapshot` and literal `query`; `path=""`, optional `glob`, `caseSensitive=false`, `offset=0`, `limit=50`. | Deterministic path/line/column matches, bounded line excerpts, explicit excerpt/result truncation, skipped binary/invalid/oversized file counts, and scanned bytes. |

There are no network, write, execution, resource, resource-template, or
prompt tools. Resource/template/prompt listings are empty and reads of an
MCP resource are rejected. Snapshot mode rejects research-policy/provider,
cookie, network, and submission-validation options.

## Fixed limits

The broker's `--describe-snapshot-policy` JSON is authoritative and includes
all limits and schemas. Current limits include:

| Resource | Limit |
| --- | --- |
| Tool calls | 2,048 per phase |
| MCP request / headers / tool response | 64 KiB / 4 KiB / 512 KiB |
| Relative path / depth | 4,096 UTF-8 bytes / 64 components |
| Glob / literal query | 1,024 UTF-8 bytes each |
| Pagination offset / start line | 1,000,000 / 10,000,000 |
| Read bytes per call / per phase | 256 KiB / 64 MiB |
| Read lines per call / text line | 2,000 / 256 KiB |
| Enumerated entries per call / per phase | 100,000 / 1,000,000 |
| Search matches / occurrences per call | 200 returned / 1,000,000 inspected |
| Scanned bytes per call / per phase | 256 MiB / 1 GiB |
| Search excerpt / listed skipped paths | 16 KiB / 100 |
| Individual additional file | 2 MiB |

Malformed or oversized MCP framing ends the phase with an unclean exit;
it is never parsed again from an unread suffix. Tool limit failures return
bounded error objects without local paths or untrusted exception text.

## Lifecycle and isolation

The fixed Bash launcher starts `/usr/bin/python3` under `env -i`, a private
working directory, and fixed PATH/locale/Python isolation settings. It
imports no provider credential, proxy, user configuration, cookie, or
research state. Snapshot mode constructs no research broker, policy, network
log, cookie jar, or research artifact, including for scope 1. It does not
provide target network access; the harness's separate model-provider access
remains governed by its own approved boundary.

The broker writes owner-only PID/process records and a lifecycle exit
record in its transient runtime. Bash signals a remaining process only
after checking the exact PID, kernel start time, owner, snapshot-mode argv,
grant manifest, and policy digest. A graceful exit is required; an unknown
process, missing/unclean exit record, or removal failure blocks report
promotion. Codex starts each stdio broker through the bundled Bash supervisor
in a separate process group because Codex terminates its own MCP process group
two seconds after `SIGTERM`. The supervisor preserves the MCP stdio channels,
monitors the trusted runner's PID and kernel start time, and exits with the
broker; this lets normal Codex shutdown reach a clean broker exit without
allowing a detached process to survive loss of its runner owner. Copilot and
Claude Code retain the direct launcher path. Cleanup removes transient grants
and configuration, preserves the read-only snapshot/evidence, and is
idempotent. The runner holds each broker runtime under the same inherited
`flock` lock as its runtime homes, so after a hard kill a later runner start
removes a `rhyolite-snapshot-read.*` runtime only when its lock is free and
its whole tree is unchanged for 60 minutes.
