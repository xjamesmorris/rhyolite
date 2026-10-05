#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const MANUAL_PLAQUE_COPY_LINES = [
    'Rhyolite is an open-source software analysis platform.',
    'repo-review is its initial and default module; use /rhyolite:start to begin.',
    'Use /rhyolite:help for commands or /rhyolite:status for current progress.',
];
const LAUNCHER_PLAQUE_COPY_LINES = [
    'Rhyolite is an open-source software analysis platform.',
    'repo-review is its initial and default module; automatic guided setup is starting.',
    'Wait for the first setup prompt; use /rhyolite:status for current progress.',
];
const PLAQUE_GRADIENT = [
    '118;234;255',
    '90;220;255',
    '66;203;255',
    '54;182;255',
    '68;148;248',
    '88;122;230',
];
const TRUSTED_START_MARKER = 'RHYOLITE_START_COMMAND_V1';
const DEFAULT_MAX_COLUMNS = 90;
const TRUSTED_START_COMMANDS = [
    '/rhyolite:start',
    '/rhyolite:repo-review',
    '/repo-review',
];
const scriptPath = fileURLToPath(import.meta.url);

class CliError extends Error {
    constructor(message, exitCode = 2) {
        super(message);
        this.name = 'CliError';
        this.exitCode = exitCode;
    }
}

function usage() {
    return [
        'Usage:',
        '  node tests/validate-tui-runtime.mjs \\',
        '    --plugin-manifest <path> \\',
        '    --banner <path> \\',
        '    --progress-json <path> \\',
        '    --launcher-progress-output <path> \\',
        '    --plaque-json <path> \\',
        '    --plaque-no-color-json <path> \\',
        '    --start-command <path> \\',
        '    --repo-review-command <path> \\',
        '    [--plaque-mode <manual|launcher>] \\',
        '    [--extension <path>] \\',
        '    [--max-columns <n>]',
        '',
        '  node tests/validate-tui-runtime.mjs --self-check',
        '',
        'Validates Rhyolite terminal/runtime UI artifacts without network or',
        'write side effects. --self-check creates and cleans transient fixtures',
        `under ${os.homedir()} to exercise the validator itself.`,
    ].join('\n');
}

function normalizeNewlines(value) {
    return value.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

function stripTrailingNewlines(value) {
    return value.replace(/\n+$/, '');
}

function stripBom(value) {
    return value.startsWith('\uFEFF') ? value.slice(1) : value;
}

function normalizeWhitespace(value) {
    return normalizeNewlines(value).replace(/\s+/g, ' ').trim();
}

function stripAnsi(value) {
    return value
        .replace(/\u001B\][^\u0007]*(?:\u0007|\u001B\\)/gu, '')
        .replace(/\u001B\[[0-?]*[ -/]*[@-~]/gu, '');
}

function isAllowedBannerLine(value) {
    return /^[\x20-\x7E\u2580\u2584\u2588]*$/u.test(value);
}

function isFullwidthCodePoint(codePoint) {
    return codePoint >= 0x1100 && (
        codePoint <= 0x115F ||
        codePoint === 0x2329 ||
        codePoint === 0x232A ||
        (codePoint >= 0x2E80 && codePoint <= 0x3247 && codePoint !== 0x303F) ||
        (codePoint >= 0x3250 && codePoint <= 0x4DBF) ||
        (codePoint >= 0x4E00 && codePoint <= 0xA4C6) ||
        (codePoint >= 0xA960 && codePoint <= 0xA97C) ||
        (codePoint >= 0xAC00 && codePoint <= 0xD7A3) ||
        (codePoint >= 0xF900 && codePoint <= 0xFAFF) ||
        (codePoint >= 0xFE10 && codePoint <= 0xFE19) ||
        (codePoint >= 0xFE30 && codePoint <= 0xFE6B) ||
        (codePoint >= 0xFF01 && codePoint <= 0xFF60) ||
        (codePoint >= 0xFFE0 && codePoint <= 0xFFE6) ||
        (codePoint >= 0x1F300 && codePoint <= 0x1FAFF) ||
        (codePoint >= 0x20000 && codePoint <= 0x3FFFD)
    );
}

function codePointWidth(character) {
    const codePoint = character.codePointAt(0);
    if (codePoint === undefined) {
        return 0;
    }

    if (
        codePoint === 0 ||
        codePoint === 0x200D ||
        (codePoint >= 0x00 && codePoint < 0x20) ||
        (codePoint >= 0x7F && codePoint < 0xA0) ||
        (codePoint >= 0xFE00 && codePoint <= 0xFE0F) ||
        (codePoint >= 0xE0100 && codePoint <= 0xE01EF)
    ) {
        return 0;
    }

    if (/\p{Mark}/u.test(character)) {
        return 0;
    }

    return isFullwidthCodePoint(codePoint) ? 2 : 1;
}

function stringWidth(value) {
    let width = 0;
    for (const character of value) {
        width += codePointWidth(character);
    }
    return width;
}

function readUtf8File(filePath, label) {
    try {
        return stripBom(normalizeNewlines(fs.readFileSync(filePath, 'utf8')));
    }
    catch (error) {
        throw new CliError(`Could not read ${label} at ${filePath}: ${error.message}`);
    }
}

function parseJsonFile(filePath, label, findings) {
    try {
        return JSON.parse(readUtf8File(filePath, label));
    }
    catch (error) {
        findings.push(`${label} is not valid JSON: ${filePath} (${error.message})`);
        return null;
    }
}

function parseSingleLineJsonArtifact(filePath, label, findings) {
    const raw = readUtf8File(filePath, label);
    const trimmed = stripTrailingNewlines(raw);
    const lines = trimmed.length === 0 ? [] : trimmed.split('\n');
    if (lines.length !== 1) {
        findings.push(`${label} must contain exactly one JSON line: ${filePath}`);
        return null;
    }

    try {
        return JSON.parse(lines[0]);
    }
    catch (error) {
        findings.push(`${label} is not valid JSON: ${filePath} (${error.message})`);
        return null;
    }
}

function expectExactKeys(payload, label, findings) {
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
        findings.push(`${label} must be a JSON object with only "type" and "message".`);
        return;
    }

    const keys = Object.keys(payload).sort().join(',');
    if (keys !== 'message,type') {
        findings.push(`${label} must contain exactly "type" and "message" keys.`);
    }
}

function validateProgressPayload(progressPayload, pluginVersion, findings) {
    expectExactKeys(progressPayload, 'Progress payload', findings);
    if (!progressPayload || typeof progressPayload !== 'object' || Array.isArray(progressPayload)) {
        return;
    }

    if (progressPayload.type !== 'progress') {
        findings.push('Progress payload type must be "progress".');
    }
    if (typeof progressPayload.message !== 'string' || progressPayload.message.length === 0) {
        findings.push('Progress payload message must be a non-empty string.');
        return;
    }
    if (progressPayload.message.includes('\n')) {
        findings.push('Progress payload message must stay single-line.');
    }
    if (/\u001B\[/u.test(progressPayload.message)) {
        findings.push('Progress payload message must not contain ANSI escape sequences.');
    }
    if (!progressPayload.message.includes(TRUSTED_START_COMMANDS[0])) {
        findings.push('Progress payload message must explicitly point to /rhyolite:start.');
    }
    if (!progressPayload.message.includes(`v${pluginVersion} Beta`)) {
        findings.push('Progress payload message must carry the plugin.json version and Beta display label.');
    }
    if (/\bskill\s*\(\s*start\s*\)/iu.test(progressPayload.message)) {
        findings.push('Progress payload message must not mention skill(start).');
    }
}

function validateBanner(bannerText, maxColumns, findings) {
    const banner = stripTrailingNewlines(bannerText);
    const lines = banner.split('\n');
    const disallowedDenseGlyphPattern = /[\u2500-\u257F\u2591-\u2593\u2800-\u28FF]/u;

    if (lines.length < 6) {
        findings.push('Banner must contain at least six logo lines.');
    }
    if (banner.includes('\t')) {
        findings.push('Banner must not contain tab characters.');
    }
    if (disallowedDenseGlyphPattern.test(banner)) {
        findings.push('Banner must use solid block glyphs, not box, shade, or braille characters.');
    }
    if (!banner.includes('\u2588')) {
        findings.push('Banner must use solid full-block glyphs for the logo.');
    }
    if (!banner.includes('\u2580') || !banner.includes('\u2584')) {
        findings.push('Banner must use upper and lower half-block contours for smoother edges.');
    }

    for (const [index, line] of lines.entries()) {
        if (!isAllowedBannerLine(line)) {
            findings.push(
                `Banner line ${index + 1} must use printable ASCII and/or full/half-block glyphs only.`,
            );
        }
        const width = stringWidth(line);
        if (width > maxColumns) {
            findings.push(
                `Banner line ${index + 1} is ${width} columns wide; keep it within ${maxColumns} columns.`,
            );
        }
        if (line.length > 0) {
            const nonSpace = line.replace(/ /g, '').length;
            const blockGlyphs = [...line].filter(
                (character) => '\u2580\u2584\u2588'.includes(character),
            ).length;
            if (
                nonSpace < 12 ||
                blockGlyphs < 12 ||
                nonSpace / Math.max(width, 1) < 0.35
            ) {
                findings.push(
                    `Banner line ${index + 1} is too sparse for a solid logo treatment.`,
                );
            }
        }
    }
}

function getBannerDisplayWidth(bannerText) {
    return stripTrailingNewlines(bannerText)
        .split('\n')
        .reduce((maxWidth, line) => Math.max(maxWidth, stringWidth(line)), 0);
}

function buildExpectedVersionLine(bannerText, pluginVersion) {
    const versionText = `v${pluginVersion} Beta`;
    const bannerWidth = getBannerDisplayWidth(bannerText);
    const padding = Math.max(0, bannerWidth - stringWidth(versionText));
    return `${' '.repeat(padding)}${versionText}`;
}

function buildExpectedPlainPlaque(bannerText, pluginVersion, copyLines) {
    const banner = stripTrailingNewlines(bannerText);
    return [
        ...banner.split('\n'),
        buildExpectedVersionLine(bannerText, pluginVersion),
        '',
        ...copyLines,
    ].join('\n');
}

function validatePlaquePayload(
    payload,
    label,
    expectedPlainPlaque,
    maxColumns,
    findings,
    { bannerLineCount, requireColor },
) {
    expectExactKeys(payload, label, findings);
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
        return;
    }
    if (payload.type !== 'progress') {
        findings.push(`${label} type must be "progress".`);
    }
    if (typeof payload.message !== 'string' || payload.message.length === 0) {
        findings.push(`${label} message must be a non-empty string.`);
        return;
    }

    const normalizedMessage = normalizeNewlines(payload.message);
    const strippedMessage = stripAnsi(normalizedMessage);
    const expectedLines = expectedPlainPlaque.split('\n');
    const actualLines = strippedMessage.split('\n');
    const versionLineIndex = bannerLineCount;
    const blankLineIndex = versionLineIndex + 1;
    const expectedVersionLine = expectedLines[versionLineIndex] ?? '';
    const expectedVersionText = expectedVersionLine.trimStart();
    const bannerWidth = getBannerDisplayWidth(expectedLines.slice(0, bannerLineCount).join('\n'));

    if (strippedMessage !== expectedPlainPlaque) {
        findings.push(`${label} message must exactly match the readable plaque copy after ANSI is removed.`);
    }
    if (actualLines[versionLineIndex] !== expectedVersionLine) {
        findings.push(`${label} must place the version line immediately below the wordmark.`);
    }
    if (!/^v\d+\.\d+\.\d+ Beta$/.test(expectedVersionText)) {
        findings.push(`${label} expected version line must contain only v<version> Beta text.`);
    }
    if (actualLines[versionLineIndex]?.trimStart() !== expectedVersionText) {
        findings.push(`${label} version line must contain only the plugin version and Beta display label.`);
    }
    if (stringWidth(actualLines[versionLineIndex] ?? '') !== bannerWidth) {
        findings.push(`${label} version line must right-align to the banner display width.`);
    }
    if ((actualLines[blankLineIndex] ?? null) !== '') {
        findings.push(`${label} must keep one blank line between the version line and onboarding copy.`);
    }

    if (requireColor) {
        const colorPattern = /\u001B\[38;2;(\d+);(\d+);(\d+)m/gu;
        const gradientStops = [];
        const coloredLines = normalizedMessage.split('\n');
        if (coloredLines.length !== expectedLines.length) {
            findings.push(`${label} line count changed after coloring; keep one colored line per plain line.`);
        }
        if (!/\u001B\[/u.test(normalizedMessage)) {
            findings.push(`${label} must contain ANSI color sequences.`);
        }
        const unsupportedAnsi = normalizedMessage
            .replace(colorPattern, '')
            .replace(/\u001B\[0m/gu, '');
        if (unsupportedAnsi.includes('\u001B')) {
            findings.push(`${label} contains unsupported ANSI sequences.`);
        }

        for (const [index, line] of coloredLines.entries()) {
            const expectedLine = expectedLines[index] ?? '';
            const startMatches = [...line.matchAll(colorPattern)];
            const resetMatches = line.match(/\u001B\[0m/gu) ?? [];
            const isBannerLine = index < bannerLineCount;
            const isVersionLine = index === versionLineIndex;

            if (!isBannerLine && !isVersionLine) {
                if (startMatches.length !== 0 || resetMatches.length !== 0) {
                    findings.push(
                        `${label} non-banner line ${index + 1} must use the terminal default color.`,
                    );
                }
                if (line !== expectedLine) {
                    findings.push(`${label} line ${index + 1} changed readable text without ANSI.`);
                }
                continue;
            }
            if (startMatches.length !== 1) {
                findings.push(
                    `${label} line ${index + 1} must start with exactly one TrueColor foreground sequence.`,
                );
                continue;
            }
            if (!line.startsWith(startMatches[0][0])) {
                findings.push(`${label} line ${index + 1} must begin with its TrueColor sequence.`);
            }
            if (resetMatches.length !== 1) {
                findings.push(`${label} line ${index + 1} must contain exactly one ANSI reset.`);
            }
            if (!line.endsWith('\u001B[0m')) {
                findings.push(`${label} line ${index + 1} must end with an ANSI reset.`);
            }
            if (stripAnsi(line) !== expectedLine) {
                findings.push(`${label} line ${index + 1} changed readable text while coloring.`);
            }

            const [, redText, greenText, blueText] = startMatches[0];
            const red = Number(redText);
            const green = Number(greenText);
            const blue = Number(blueText);
            gradientStops.push(`${red};${green};${blue}`);
            if (!(blue > red && blue > green)) {
                findings.push(
                    `${label} line ${index + 1} left the blue-dominant gradient family (${red};${green};${blue}).`,
                );
            }
            if (isVersionLine && `${red};${green};${blue}` !== PLAQUE_GRADIENT[PLAQUE_GRADIENT.length - 1]) {
                findings.push(`${label} version line must use the final subordinate gradient stop.`);
            }
            const resetIndex = line.indexOf('\u001B[0m');
            const textIndex = expectedLine.length === 0 ? 0 : line.lastIndexOf(expectedLine);
            if (resetIndex !== -1 && textIndex !== -1 && resetIndex < textIndex + expectedLine.length) {
                findings.push(`${label} line ${index + 1} must reset after the colored segment, not before it.`);
            }
        }

        if (
            gradientStops.length !== bannerLineCount + 1 ||
            gradientStops.length < 5 ||
            new Set(gradientStops.slice(0, bannerLineCount)).size < 4
        ) {
            findings.push(`${label} must use multiple blue-dominant TrueColor stops across the plaque.`);
        }
    }
    else if (normalizedMessage.includes('\u001B')) {
        findings.push(`${label} must contain no ANSI when color is disabled.`);
    }

    for (const [index, line] of actualLines.entries()) {
        const width = stringWidth(line);
        if (width > maxColumns) {
            findings.push(
                `${label} line ${index + 1} is ${width} columns wide; keep runtime output within ${maxColumns} columns.`,
            );
        }
    }
}

function validateCommandFiles(startText, repoReviewText, findings) {
    const startNormalized = normalizeWhitespace(startText);
    const repoReviewNormalized = normalizeWhitespace(repoReviewText);

    if (!startText.includes(`<!-- ${TRUSTED_START_MARKER} -->`)) {
        findings.push('start.md must keep the trusted RHYOLITE_START_COMMAND_V1 marker.');
    }
    if (!repoReviewText.includes(`<!-- ${TRUSTED_START_MARKER} -->`)) {
        findings.push('repo-review.md must keep the trusted RHYOLITE_START_COMMAND_V1 marker.');
    }

    if (!startNormalized.includes('This is an already-loaded Rhyolite prompt command.')) {
        findings.push('start.md must identify itself as an already-loaded prompt command.');
    }
    if (!startNormalized.includes('Do not invoke the skill tool.')) {
        findings.push('start.md must explicitly forbid skill-tool invocation.');
    }
    if (!startNormalized.includes('Do not invoke `skill(start)` or `skill(repo-review)`.')) {
        findings.push('start.md must explicitly forbid skill(start) and skill(repo-review).');
    }
    if (!startNormalized.includes('Do not look up or call any skill named `start` or `repo-review`.')) {
        findings.push('start.md must explicitly guard against skill(start)/skill(repo-review) confusion.');
    }
    if (
        !startNormalized.includes(
            'Enter Rhyolite\'s guided `repo-review` setup directly in the current `rhyolite:repo-review` session now.',
        )
    ) {
        findings.push('start.md must explicitly enter the current rhyolite:repo-review session directly.');
    }
    if (!repoReviewNormalized.includes('This is an already-loaded Rhyolite prompt command alias.')) {
        findings.push('repo-review.md must identify itself as an already-loaded prompt command alias.');
    }
    if (!repoReviewNormalized.includes('Do not invoke the skill tool.')) {
        findings.push('repo-review.md must explicitly forbid skill-tool invocation.');
    }
    if (!repoReviewNormalized.includes('Do not invoke `skill(start)` or `skill(repo-review)`.')) {
        findings.push('repo-review.md must explicitly forbid skill(start) and skill(repo-review).');
    }
    if (!repoReviewNormalized.includes('Do not look up or call any skill named `start` or `repo-review`.')) {
        findings.push('repo-review.md must explicitly guard against skill(start)/skill(repo-review) confusion.');
    }
    if (
        !repoReviewNormalized.includes(
            'Enter the same guided `repo-review` setup directly in the current `rhyolite:repo-review` session now, with the same behavior as `/rhyolite:start`.',
        )
    ) {
        findings.push('repo-review.md must explicitly alias back to /rhyolite:start in the current session.');
    }

    for (const [label, value] of [
        ['start.md', startNormalized],
        ['repo-review.md', repoReviewNormalized],
    ]) {
        if (!value.includes("Treat the following command arguments as the user's initial review request.")) {
            findings.push(`${label} must preserve the user-argument handoff contract.`);
        }
        if (!value.includes('If they are empty, begin with source selection.')) {
            findings.push(`${label} must preserve the empty-arguments source-selection behavior.`);
        }
        if (!value.includes('Do not invoke the skill tool.')) {
            findings.push(`${label} must keep the explicit no-skill routing guard.`);
        }
    }
}

function validateExtension(extensionText, findings) {
    const requiredFragments = [
        'import { joinSession } from "@github/copilot-sdk/extension";',
        'const REPO_REVIEW_AGENT_ID = "rhyolite:repo-review";',
        'const RESUME_ARGUMENT = "--rhyolite-resume";',
        'session.rpc.commands.enqueue',
        'session.rpc.agent.select({ name: REPO_REVIEW_AGENT_ID });',
        'prompt: `RHYOLITE_START_COMMAND_V1\\n${prompt}`',
        'displayPrompt:',
        'session.rpc.agent.getCurrent()',
        'RHYOLITE ERROR',
        'Stage: extension RPC ${stage}',
        'sanitizeErrorDetail',
        'metadata.issuesUrl',
        'metadata.pullsUrl',
        'PUBLIC_PLACEHOLDER_PATTERN',
        'metadata.localSupportPath',
        'metadata.localContributingPath',
        'Rhyolite v${RHYOLITE_VERSION} Beta loaded',
    ];

    for (const fragment of requiredFragments) {
        if (!extensionText.includes(fragment)) {
            findings.push(`Extension handoff is missing required runtime guard: ${fragment}`);
        }
    }

    if (!extensionText.includes('/repo-review')) {
        findings.push('Extension handoff must keep the explicit /repo-review resume path.');
    }
    if (/https:\/\/github\.com\/<PUBLIC_[A-Z0-9_:-]+>\//u.test(extensionText)) {
        findings.push('Extension errors must not hard-code unresolved public repository URLs.');
    }
    if (/\bskill\s*\(\s*start\s*\)/iu.test(extensionText) || /\bskill\s+start\b/iu.test(extensionText)) {
        findings.push('Extension handoff must not route through skill(start) wording.');
    }
}

function parseArgs(rawArgs) {
    const options = {
        maxColumns: DEFAULT_MAX_COLUMNS,
        plaqueMode: 'manual',
    };

    for (let index = 0; index < rawArgs.length; index += 1) {
        const arg = rawArgs[index];
        switch (arg) {
        case '--help':
            options.help = true;
            break;
        case '--self-check':
            options.selfCheck = true;
            break;
        case '--plugin-manifest':
        case '--banner':
        case '--progress-json':
        case '--launcher-progress-output':
        case '--plaque-json':
        case '--plaque-no-color-json':
        case '--start-command':
        case '--repo-review-command':
        case '--extension':
        case '--max-columns': {
            const value = rawArgs[index + 1];
            if (!value || value.startsWith('--')) {
                throw new CliError(`Missing value after ${arg}`);
            }
            index += 1;
            if (arg === '--max-columns') {
                const parsed = Number.parseInt(value, 10);
                if (!Number.isInteger(parsed) || parsed < 40 || parsed > 200) {
                    throw new CliError('--max-columns must be an integer between 40 and 200');
                }
                options.maxColumns = parsed;
            }
            else {
                options[arg.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value;
            }
            break;
        }
        case '--plaque-mode': {
            const value = rawArgs[index + 1];
            if (!value || value.startsWith('--')) {
                throw new CliError(`Missing value after ${arg}`);
            }
            if (!['manual', 'launcher'].includes(value)) {
                throw new CliError('--plaque-mode must be manual or launcher');
            }
            options.plaqueMode = value;
            index += 1;
            break;
        }
        default:
            throw new CliError(`Unknown argument: ${arg}`);
        }
    }

    return options;
}

function validateArtifacts(options) {
    const required = [
        'pluginManifest',
        'banner',
        'progressJson',
        'launcherProgressOutput',
        'plaqueJson',
        'plaqueNoColorJson',
        'startCommand',
        'repoReviewCommand',
    ];
    for (const key of required) {
        if (!options[key]) {
            throw new CliError(`Missing required argument --${key.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)}`);
        }
    }

    const findings = [];
    const pluginManifest = parseJsonFile(options.pluginManifest, 'plugin manifest', findings);
    const bannerText = readUtf8File(options.banner, 'banner');
    const progressPayload = parseSingleLineJsonArtifact(options.progressJson, 'Progress payload', findings);
    const launcherProgressPayload = parseSingleLineJsonArtifact(
        options.launcherProgressOutput,
        'Launcher-started progress output',
        findings,
    );
    const plaquePayload = parseSingleLineJsonArtifact(options.plaqueJson, 'Colored plaque payload', findings);
    const plaqueNoColorPayload = parseSingleLineJsonArtifact(
        options.plaqueNoColorJson,
        'No-color plaque payload',
        findings,
    );
    const startCommandText = readUtf8File(options.startCommand, 'start command');
    const repoReviewCommandText = readUtf8File(options.repoReviewCommand, 'repo-review command');
    const extensionText = options.extension
        ? readUtf8File(options.extension, 'extension handoff')
        : null;

    const pluginVersion = pluginManifest?.version;
    if (typeof pluginVersion !== 'string' || pluginVersion.length === 0) {
        findings.push('Plugin manifest must contain a non-empty string version.');
    }

    validateBanner(bannerText, options.maxColumns, findings);
    if (typeof pluginVersion === 'string' && pluginVersion.length > 0) {
        validateProgressPayload(progressPayload, pluginVersion, findings);
    }

    const plaqueCopyLines = options.plaqueMode === 'launcher'
        ? LAUNCHER_PLAQUE_COPY_LINES
        : MANUAL_PLAQUE_COPY_LINES;
    const bannerLineCount = stripTrailingNewlines(bannerText).split('\n').length;
    const expectedPlainPlaque = typeof pluginVersion === 'string' && pluginVersion.length > 0
        ? buildExpectedPlainPlaque(bannerText, pluginVersion, plaqueCopyLines)
        : buildExpectedPlainPlaque(bannerText, '<missing-version>', plaqueCopyLines);
    const expectedLauncherPlaque = typeof pluginVersion === 'string' && pluginVersion.length > 0
        ? buildExpectedPlainPlaque(bannerText, pluginVersion, LAUNCHER_PLAQUE_COPY_LINES)
        : buildExpectedPlainPlaque(bannerText, '<missing-version>', LAUNCHER_PLAQUE_COPY_LINES);
    validatePlaquePayload(
        launcherProgressPayload,
        'Launcher-started progress output',
        expectedLauncherPlaque,
        options.maxColumns,
        findings,
        { bannerLineCount, requireColor: true },
    );
    validatePlaquePayload(
        plaquePayload,
        'Colored plaque payload',
        expectedPlainPlaque,
        options.maxColumns,
        findings,
        { bannerLineCount, requireColor: true },
    );
    validatePlaquePayload(
        plaqueNoColorPayload,
        'No-color plaque payload',
        expectedPlainPlaque,
        options.maxColumns,
        findings,
        { bannerLineCount, requireColor: false },
    );

    validateCommandFiles(startCommandText, repoReviewCommandText, findings);
    if (extensionText !== null) {
        validateExtension(extensionText, findings);
    }

    if (findings.length > 0) {
        for (const finding of findings) {
            console.error(`- ${finding}`);
        }
        return 1;
    }

    console.log('TUI_RUNTIME_VALIDATION: PASS');
    return 0;
}

function writeFixture(filePath, content) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, content, 'utf8');
}

function colorizePlaqueLines(plainPlaque, bannerLineCount) {
    const colors = PLAQUE_GRADIENT;
    const versionLineIndex = bannerLineCount;

    return plainPlaque
        .split('\n')
        .map((line, index) => (
            index < bannerLineCount
                ? `\u001B[38;2;${colors[index % colors.length]}m${line}\u001B[0m`
                : index === versionLineIndex
                    ? `\u001B[38;2;${colors[colors.length - 1]}m${line}\u001B[0m`
                    : line
        ))
        .join('\n');
}

function runSelfCheck() {
    const scratchRoot = fs.mkdtempSync(path.join(os.homedir(), '.rhyolite-ui-validator-selfcheck-'));
    try {
        const version = '9.9.9';
        const banner = [
            '▄█████▄  ██    ██ ██    ██  ▄████▄  ██       ▀██████▀ ████████ ████████',
            '██   ██  ██    ██  ██  ██  ██    ██ ██          ██       ██    ██',
            '██▄▄▄█▀  ██▄▄▄▄██   ████   ██    ██ ██          ██       ██    ██▄▄▄▄▄',
            '██▀██    ██▀▀▀▀██    ██    ██    ██ ██          ██       ██    ██▀▀▀▀▀',
            '██  ▀█▄  ██    ██    ██    ██    ██ ██          ██       ██    ██',
            '██    ██ ██    ██    ██     ▀████▀  ████████ ▄██████▄    ██    ████████',
        ].join('\n');
        const plainPlaque = buildExpectedPlainPlaque(
            banner,
            version,
            MANUAL_PLAQUE_COPY_LINES,
        );
        const plainLauncherPlaque = buildExpectedPlainPlaque(
            banner,
            version,
            LAUNCHER_PLAQUE_COPY_LINES,
        );
        const progress = JSON.stringify({
            type: 'progress',
            message: `Rhyolite v${version} Beta loaded — type /rhyolite:start to start.`,
        });
        const coloredPlaque = JSON.stringify({
            type: 'progress',
            message: colorizePlaqueLines(plainPlaque, banner.split('\n').length),
        });
        const noColorPlaque = JSON.stringify({
            type: 'progress',
            message: plainPlaque,
        });
        const coloredLauncherPlaque = JSON.stringify({
            type: 'progress',
            message: colorizePlaqueLines(
                plainLauncherPlaque,
                banner.split('\n').length,
            ),
        });
        const noColorLauncherPlaque = JSON.stringify({
            type: 'progress',
            message: plainLauncherPlaque,
        });
        const startCommand = [
            '---',
            'name: start',
            '---',
            '',
            '<!-- RHYOLITE_START_COMMAND_V1 -->',
            '',
            'This is an already-loaded Rhyolite prompt command.',
            'Do not invoke the skill tool.',
            'Do not invoke `skill(start)` or `skill(repo-review)`.',
            'Do not look up or call any skill named `start` or `repo-review`.',
            'Enter Rhyolite\'s guided `repo-review` setup directly in the current',
            '`rhyolite:repo-review` session now.',
            '',
            "Treat the following command arguments as the user's initial review request.",
            'If they are empty, begin with source selection.',
        ].join('\n');
        const repoReviewCommand = [
            '---',
            'name: repo-review',
            '---',
            '',
            '<!-- RHYOLITE_START_COMMAND_V1 -->',
            '',
            'This is an already-loaded Rhyolite prompt command alias.',
            'Do not invoke the skill tool.',
            'Do not invoke `skill(start)` or `skill(repo-review)`.',
            'Do not look up or call any skill named `start` or `repo-review`.',
            'Enter the same guided `repo-review` setup directly in the current',
            '`rhyolite:repo-review` session now, with the same behavior as',
            '`/rhyolite:start`.',
            '',
            "Treat the following command arguments as the user's initial review request.",
            'If they are empty, begin with source selection.',
        ].join('\n');
        const extension = [
            'import { joinSession } from "@github/copilot-sdk/extension";',
            'const REPO_REVIEW_AGENT_ID = "rhyolite:repo-review";',
            'const RESUME_ARGUMENT = "--rhyolite-resume";',
            'const PUBLIC_PLACEHOLDER_PATTERN = /<PUBLIC_[A-Z0-9_:-]+>/u;',
            'function sanitizeErrorDetail(value) {}',
            'metadata.issuesUrl;',
            'metadata.pullsUrl;',
            'metadata.localSupportPath;',
            'metadata.localContributingPath;',
            'const loadNotice = `Rhyolite v${RHYOLITE_VERSION} Beta loaded`;',
            'const errorHeader = "RHYOLITE ERROR";',
            'const errorStage = `Stage: extension RPC ${stage}`;',
            'await joinSession({ commands: [] });',
            'session.rpc.agent.getCurrent()',
            'session.rpc.commands.enqueue({ command: "/repo-review --rhyolite-resume" });',
            'session.rpc.agent.select({ name: REPO_REVIEW_AGENT_ID });',
            'prompt: `RHYOLITE_START_COMMAND_V1\\n${prompt}`',
            'displayPrompt: "/repo-review"',
        ].join('\n');

        const fixturePaths = {
            pluginManifest: path.join(scratchRoot, 'fixtures', 'plugin.json'),
            banner: path.join(scratchRoot, 'fixtures', 'banner.txt'),
            progress: path.join(scratchRoot, 'fixtures', 'progress.jsonl'),
            launcherProgress: path.join(scratchRoot, 'fixtures', 'launcher-progress.txt'),
            plaque: path.join(scratchRoot, 'fixtures', 'plaque.jsonl'),
            plaqueNoColor: path.join(scratchRoot, 'fixtures', 'plaque-no-color.jsonl'),
            launcherPlaque: path.join(scratchRoot, 'fixtures', 'launcher-plaque.jsonl'),
            launcherPlaqueNoColor: path.join(
                scratchRoot,
                'fixtures',
                'launcher-plaque-no-color.jsonl',
            ),
            startCommand: path.join(scratchRoot, 'fixtures', 'start.md'),
            repoReviewCommand: path.join(scratchRoot, 'fixtures', 'repo-review.md'),
            extension: path.join(scratchRoot, 'fixtures', 'extension.mjs'),
        };

        writeFixture(
            fixturePaths.pluginManifest,
            `${JSON.stringify({ name: 'rhyolite', version }, null, 2)}\n`,
        );
        writeFixture(fixturePaths.banner, `${banner}\n`);
        writeFixture(fixturePaths.progress, `${progress}\n`);
        writeFixture(fixturePaths.launcherProgress, `${coloredLauncherPlaque}\n`);
        writeFixture(fixturePaths.plaque, `${coloredPlaque}\n`);
        writeFixture(fixturePaths.plaqueNoColor, `${noColorPlaque}\n`);
        writeFixture(fixturePaths.launcherPlaque, `${coloredLauncherPlaque}\n`);
        writeFixture(
            fixturePaths.launcherPlaqueNoColor,
            `${noColorLauncherPlaque}\n`,
        );
        writeFixture(fixturePaths.startCommand, `${startCommand}\n`);
        writeFixture(fixturePaths.repoReviewCommand, `${repoReviewCommand}\n`);
        writeFixture(fixturePaths.extension, `${extension}\n`);

        execFileSync(
            process.execPath,
            [
                scriptPath,
                '--plugin-manifest',
                fixturePaths.pluginManifest,
                '--banner',
                fixturePaths.banner,
                '--progress-json',
                fixturePaths.progress,
                '--launcher-progress-output',
                fixturePaths.launcherProgress,
                '--plaque-json',
                fixturePaths.plaque,
                '--plaque-no-color-json',
                fixturePaths.plaqueNoColor,
                '--start-command',
                fixturePaths.startCommand,
                '--repo-review-command',
                fixturePaths.repoReviewCommand,
                '--extension',
                fixturePaths.extension,
            ],
            { stdio: 'pipe' },
        );

        execFileSync(
            process.execPath,
            [
                scriptPath,
                '--plugin-manifest',
                fixturePaths.pluginManifest,
                '--banner',
                fixturePaths.banner,
                '--progress-json',
                fixturePaths.progress,
                '--launcher-progress-output',
                fixturePaths.launcherProgress,
                '--plaque-json',
                fixturePaths.launcherPlaque,
                '--plaque-no-color-json',
                fixturePaths.launcherPlaqueNoColor,
                '--start-command',
                fixturePaths.startCommand,
                '--repo-review-command',
                fixturePaths.repoReviewCommand,
                '--extension',
                fixturePaths.extension,
                '--plaque-mode',
                'launcher',
            ],
            { stdio: 'pipe' },
        );

        const confusedCommandPath = path.join(scratchRoot, 'fixtures', 'repo-review-confused.md');
        writeFixture(
            confusedCommandPath,
            repoReviewCommand.replace(
                'Do not look up or call any skill named `start` or `repo-review`.\n',
                '',
            ),
        );

        let failedAsExpected = false;
        try {
            execFileSync(
                process.execPath,
                [
                    scriptPath,
                    '--plugin-manifest',
                    fixturePaths.pluginManifest,
                    '--banner',
                    fixturePaths.banner,
                    '--progress-json',
                    fixturePaths.progress,
                    '--launcher-progress-output',
                    fixturePaths.launcherProgress,
                    '--plaque-json',
                    fixturePaths.plaque,
                    '--plaque-no-color-json',
                    fixturePaths.plaqueNoColor,
                    '--start-command',
                    fixturePaths.startCommand,
                    '--repo-review-command',
                    confusedCommandPath,
                ],
                { stdio: 'pipe' },
            );
        }
        catch (error) {
            const stderr = String(error.stderr ?? '');
            failedAsExpected = stderr.includes('skill(start)/skill(repo-review) confusion');
        }

        if (!failedAsExpected) {
            throw new CliError('Self-check did not prove the explicit skill-confusion guard.', 1);
        }

        console.log('TUI runtime validator self-check: PASS');
        return 0;
    }
    finally {
        fs.rmSync(scratchRoot, { recursive: true, force: true });
    }
}

function main() {
    const rawArgs = process.argv.slice(2);
    const options = parseArgs(rawArgs);
    if (options.help) {
        console.log(usage());
        return;
    }
    if (options.selfCheck) {
        if (rawArgs.length !== 1) {
            throw new CliError('--self-check cannot be combined with validation arguments');
        }
        process.exitCode = runSelfCheck();
        return;
    }

    process.exitCode = validateArtifacts(options);
}

try {
    main();
}
catch (error) {
    if (error instanceof CliError) {
        console.error(error.message);
        console.error('');
        console.error(usage());
        process.exit(error.exitCode);
    }

    const message = error instanceof Error ? error.message : String(error);
    console.error(`Unhandled validate-tui-runtime failure: ${message}`);
    process.exit(1);
}
