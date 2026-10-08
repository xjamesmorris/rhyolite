import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_REVIEW_AGENT_ID = "rhyolite:repo-review";
const RESUME_ARGUMENT = "--rhyolite-resume";
const RHYOLITE_VERSION = "0.8.1";
const PUBLIC_PLACEHOLDER_PATTERN = /<PUBLIC_[A-Z0-9_:-]+>/u;
const EXTENSION_DIRECTORY = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = join(EXTENSION_DIRECTORY, "..", "..");

const metadata = JSON.parse(
  readFileSync(
    join(PLUGIN_ROOT, "branding", "welcome-metadata.json"),
    "utf8",
  ),
);

const repositoryUrls = [
  metadata.homeUrl,
  metadata.docsUrl,
  metadata.supportUrl,
  metadata.issuesUrl,
  metadata.pullsUrl,
];
const repositoryUrlsPublished = repositoryUrls.every(
  (value) =>
    typeof value === "string" &&
    value.length > 0 &&
    !PUBLIC_PLACEHOLDER_PATTERN.test(value),
);

function sanitizeErrorDetail(value) {
  return String(value)
    .replace(
      /\u001B\][^\u0007\u001B]*(?:\u0007|\u001B\\)|\u001B\[[0-?]*[ -/]*[@-~]|\u001B[@-_]/gu,
      "",
    )
    .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/gu, "")
    .replace(
      /(https?:\/\/)[^/@\s]+:[^/@\s]+@/giu,
      "$1[credentials omitted]@",
    )
    .replace(
      /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/giu,
      "[email omitted]",
    )
    .replace(
      /((?:proxy-)?authorization\s*:\s*(?:bearer|basic)?\s*)\S+/giu,
      "$1[credential omitted]",
    )
    .replace(
      /((?:access[_-]?token|api[_-]?key|password|secret|token)\s*[:=]\s*)\S+/giu,
      "$1[credential omitted]",
    )
    .replace(
      /\b(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{20,}\b/gu,
      "[credential omitted]",
    )
    .trim();
}

function safeExceptionDetails(error) {
  if (error instanceof Error) {
    return sanitizeErrorDetail(error.stack || `${error.name}: ${error.message}`);
  }
  return sanitizeErrorDetail(error);
}

function remediationForStage(stage) {
  if (stage === "commands.enqueue") {
    return "Retry /repo-review, or use /rhyolite:start if command queuing remains unavailable.";
  }
  if (stage === "agent.select") {
    return "Select /agent rhyolite:repo-review, then type start.";
  }
  if (stage === "session.send") {
    return "The agent is selected; type start to begin guided setup.";
  }
  return "Retry once; if the handoff still fails, use /rhyolite:start.";
}

async function logRhyoliteError(stage, error) {
  const details = safeExceptionDetails(error) || "No safe exception detail was returned.";
  const support = repositoryUrlsPublished
    ? metadata.issuesUrl
    : `${metadata.localSupportPath} and local documentation`;
  const contribute = repositoryUrlsPublished
    ? metadata.pullsUrl
    : metadata.localContributingPath;
  await session.log(
    [
      "RHYOLITE ERROR",
      "Summary: The /repo-review guided-start handoff did not complete.",
      `Stage: extension RPC ${stage}`,
      "Source: NOT APPLICABLE",
      `Details: ${details.replace(/\r?\n/gu, " | ")}`,
      "Consequence: Guided repository-review setup did not start.",
      `Remediation: ${remediationForStage(stage)}`,
      "Artifacts: NONE",
      `Support: ${support}`,
      `Contribute: ${contribute}`,
    ].join("\n"),
    { level: "error" },
  );
}

let session;
session = await joinSession({
  commands: [
    {
      name: "repo-review",
      description: "Start Rhyolite's initial and default repo-review module",
      handler: async ({ args }) => {
        let rpcStage = "argument decoding";
        try {
          const rawArguments = (args ?? "").trim();
          const resumeMatch = rawArguments.match(
            /^--rhyolite-resume(?: ([A-Za-z0-9_-]+))?$/,
          );
          const isResume = resumeMatch !== null;
          const initialRequest = isResume
            ? Buffer.from(resumeMatch[1] ?? "", "base64url").toString("utf8")
            : rawArguments;
          rpcStage = "agent.getCurrent";
          const currentAgent = await session.rpc.agent.getCurrent();

          if (currentAgent.agent?.id !== REPO_REVIEW_AGENT_ID) {
            if (isResume) {
              throw new Error("the Rhyolite agent selection did not persist");
            }

            const encodedRequest = Buffer.from(initialRequest, "utf8").toString(
              "base64url",
            );
            const resumeCommand = encodedRequest
              ? `/repo-review ${RESUME_ARGUMENT} ${encodedRequest}`
              : `/repo-review ${RESUME_ARGUMENT}`;
            rpcStage = "commands.enqueue";
            const queued = await session.rpc.commands.enqueue({
              command: resumeCommand,
            });
            if (!queued.queued) {
              throw new Error("the guided-start command could not be queued");
            }

            rpcStage = "agent.select";
            await session.rpc.agent.select({ name: REPO_REVIEW_AGENT_ID });
            return;
          }

          const prompt = initialRequest
            ? [
                "Begin Rhyolite's guided repository-review setup now.",
                "Treat the following text as the user's initial review request:",
                "",
                initialRequest,
              ].join("\n")
            : "Begin Rhyolite's guided repository-review setup now.";

          rpcStage = "session.send";
          await session.send({
            prompt: `RHYOLITE_START_COMMAND_V1\n${prompt}`,
            displayPrompt: initialRequest
              ? `/repo-review ${initialRequest}`
              : "/repo-review",
          });
        } catch (error) {
          await logRhyoliteError(rpcStage, error);
        }
      },
    },
  ],
});

try {
  const activeAgent = await session.rpc.agent.getCurrent();
  if (activeAgent.agent?.id !== REPO_REVIEW_AGENT_ID) {
    await session.log(
      `Rhyolite v${RHYOLITE_VERSION} Beta loaded — ` +
        "type /rhyolite:start to start.",
    );
  }
} catch (error) {
  await logRhyoliteError("load agent.getCurrent", error);
}
