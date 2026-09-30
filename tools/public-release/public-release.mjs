#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const sourceRepoRootHint = path.resolve(scriptDir, '..', '..');
const comparisonCaseInsensitive = process.platform === 'win32';
const contentHashContextRadius = 40;
const symlinkEntryMessage = 'Symbolic links are not allowed in exported trees.';
const publishRaceMessage = 'Destination directory must remain empty until publish completes.';

class CliError extends Error {
    constructor(message, exitCode = 2) {
        super(message);
        this.name = 'CliError';
        this.exitCode = exitCode;
    }
}

function escapeRegexLiteral(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function joinEncoded(parts, separator = '') {
    return parts.join(separator);
}

const internalBrandingWord = joinEncoded(['inter', 'nal']);
const pilotBrandingWord = joinEncoded(['pi', 'lot']);
const privateDenyPatternFileName = 'private-deny-patterns.json';
const brandingContextTerms = [
    'author',
    'maintainer',
    'maintainers',
    'owner',
    'plugin',
    'plugins',
    'marketplace',
    'tool',
    'tools',
].map(escapeRegexLiteral).join('|');
const codeownersRelativePath = '.github/CODEOWNERS';
const codeownersPathPattern = /^\.github\/CODEOWNERS$/i;
const licenseFilePattern = /^LICENSE(?:\.[^/]+)?$/i;

const REQUIRED_FILE_RULES = [
    { id: 'required-readme', label: 'README', patterns: [/^README(?:\.[^/]+)?$/i] },
    {
        id: 'required-contributing',
        label: 'CONTRIBUTING',
        patterns: [/^CONTRIBUTING(?:\.[^/]+)?$/i],
    },
    { id: 'required-security', label: 'SECURITY', patterns: [/^SECURITY(?:\.[^/]+)?$/i] },
    { id: 'required-privacy', label: 'PRIVACY', patterns: [/^PRIVACY(?:\.[^/]+)?$/i] },
    {
        id: 'required-code-of-conduct',
        label: 'CODE_OF_CONDUCT',
        patterns: [/^CODE_OF_CONDUCT(?:\.[^/]+)?$/i],
    },
    { id: 'required-support', label: 'SUPPORT', patterns: [/^SUPPORT(?:\.[^/]+)?$/i] },
    {
        id: 'required-plugin-manifest',
        label: 'plugin manifest',
        patterns: [/^plugins\/[^/]+\/plugin\.json$/],
    },
    {
        id: 'required-marketplace-manifest',
        label: 'marketplace manifest',
        patterns: [/^\.github\/plugin\/marketplace\.json$/],
    },
    { id: 'required-version', label: 'VERSION', patterns: [/^VERSION$/] },
    { id: 'required-changelog', label: 'CHANGELOG', patterns: [/^CHANGELOG(?:\.[^/]+)?$/i] },
];

const DEFAULT_PATH_RULES = [
    {
        id: 'path-internal-github-policy',
        description: 'Internal-only GitHub policy paths must not be exported.',
        regex: /^\.github\/(?:acl|compliance|policies)(?:\/|$)/i,
    },
    {
        id: 'path-dot-git-metadata',
        description: '.git metadata must never appear in the public export.',
        regex: /(?:^|\/)\.git(?:\/|$)/,
    },
    {
        id: 'path-public-placeholder',
        description: 'Unresolved public placeholders must not appear in paths.',
        regex: /<PUBLIC_[A-Z0-9_:-]+>/,
    },
    {
        id: 'path-secret-filename',
        description: 'Likely secret-bearing filenames must not be exported.',
        regex: /(?:^|\/)(?:\.env(?:\.[^/]+)?|\.npmrc|\.yarnrc(?:\.yml)?|id_[^/]+|[^/]*(?:secret|credential|token|password|api[-_]?key|private[-_]?key)[^/]*|[^/]+\.(?:pem|pfx|p12|key))$/i,
    },
];

const nonPublicEmailDomainPattern =
    '(?:[A-Z0-9-]+\\.)*(?:corp|internal|intra|local|lan|private|test|example|invalid|localhost|localdomain)\\b';
const nonPublicUrlHostPattern = [
    '(?:[A-Z0-9-]+\\.)*(?:corp|internal|intra|local|lan|private|test|example|invalid|localhost|localdomain)',
    '(?:10|127)\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}',
    '192\\.168\\.\\d{1,3}\\.\\d{1,3}',
    '172\\.(?:1[6-9]|2\\d|3[0-1])\\.\\d{1,3}\\.\\d{1,3}',
].join('|');
const hostedPrivateRepositoryHostPattern = [
    'dev\\.azure\\.com',
    '[A-Z0-9-]+\\.visualstudio\\.com',
].join('|');

const DEFAULT_CONTENT_RULES = [
    {
        id: 'content-public-placeholder',
        description: 'Unresolved public placeholders must not appear in file contents.',
        regex: /<PUBLIC_[A-Z0-9_:-]+>/,
    },
    {
        id: 'content-nonpublic-branding',
        description: 'Residual non-public maintainer or tool branding must not appear in exported content.',
        allowlistWaivable: true,
        regex: new RegExp(
            [
                `\\b(?:${escapeRegexLiteral(internalBrandingWord)}|${escapeRegexLiteral(pilotBrandingWord)})\\b[^\\r\\n]{0,80}?\\b(?:${brandingContextTerms})\\b`,
                `\\b(?:${brandingContextTerms})\\b[^\\r\\n]{0,80}?\\b(?:${escapeRegexLiteral(internalBrandingWord)}|${escapeRegexLiteral(pilotBrandingWord)})\\b`,
            ].join('|'),
            'i',
        ),
    },
    {
        id: 'content-corporate-email',
        description: 'Corporate email addresses must not appear in exported content.',
        regex: new RegExp(`\\b[A-Z0-9._%+-]+@${nonPublicEmailDomainPattern}`, 'i'),
    },
    {
        id: 'content-private-repository-url',
        description: 'Likely private repository references must not appear in exported content.',
        regex: new RegExp(
            [
                '\\bssh://(?:[^\\s/@]+@)?[^\\s/:]+(?::\\d+)?[/:][^\\s]+',
                '\\bgit@[^\\s:]+:[^\\s]+',
                '\\bhttps?://[^\\s/@]+@[^\\s/]+/[^\\s]+',
                `\\b(?:https?://)?(?:${hostedPrivateRepositoryHostPattern})/[^\\s]+`,
                `\\bhttps?://(?:${nonPublicUrlHostPattern})(?::\\d+)?/[^\\s]+`,
            ].join('|'),
            'i',
        ),
    },
    {
        id: 'content-private-key-block',
        description: 'Private key material must not appear in exported content.',
        regex: /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/i,
    },
    {
        id: 'content-github-token',
        description: 'GitHub tokens must not appear in exported content.',
        regex: /\bgh(?:p|o|u|s|r)_[A-Za-z0-9]{20,}\b/,
    },
    {
        id: 'content-aws-access-key',
        description: 'AWS access keys must not appear in exported content.',
        regex: /\bAKIA[0-9A-Z]{16}\b/,
    },
    {
        id: 'content-generic-secret',
        description: 'Likely secret assignments must not appear in exported content.',
        regex: /\b(?:api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|connection[_-]?string|password)\b\s*[:=]\s*["']?[A-Za-z0-9/+._=-]{12,}/i,
    },
];

const CODEOWNERS_GATE_MESSAGE =
    'Public release requires a regular .github/CODEOWNERS file with at least one concrete non-comment ownership rule.';
const LICENSE_GATE_MESSAGE =
    'Public release requires a regular LICENSE* file with substantive non-whitespace content.';
const VALIDATION_SKIP_MESSAGE =
    'Validation was skipped by option; public release requires bash tests/validate-plugin.sh on Fedora Linux 44.';
const VALIDATION_NOT_RUN_MESSAGE =
    'Validation did not run because export extraction failed.';
const VALIDATOR_DEFINITIONS = [
    {
        id: 'bash',
        command: 'bash',
        commandLine: 'bash tests/validate-plugin.sh',
        scriptRelativePath: 'tests/validate-plugin.sh',
        buildArgs(scriptPath) {
            return [scriptPath];
        },
    },
];

function usage(command) {
    const common = [
        '  --deny-file <file>          Optional JSON file with extra deny rules.',
        '  --allowlist-file <file>     Optional reviewed allowlist JSON file.',
        '  --audit-report <file>       Optional audit report path. Defaults to <destination>.audit.txt.',
        '  --skip-validation           Emit a blocking finding instead of running validators.',
        '  --help                      Show this help.',
    ].join('\n');

    if (command === 'export') {
        return [
            'Usage:',
            '  public-export --source-ref <ref> --destination <directory> [options]',
            '',
            'Runs bash tests/validate-plugin.sh by default.',
            '',
            'Options:',
            '  --source-ref <ref>         Exact source ref or commit to export.',
            '  --destination <directory>  Empty destination directory outside the source repository.',
            common,
        ].join('\n');
    }

    if (command === 'preflight') {
        return [
            'Usage:',
            '  public-preflight --destination <directory> [options]',
            '',
            'Runs bash tests/validate-plugin.sh by default.',
            '',
            'Options:',
            '  --destination <directory>  Existing exported tree to scan.',
            '  --source-commit <sha>      Optional source commit to record in the audit report.',
            common,
        ].join('\n');
    }

    return [
        'Usage:',
        '  public-export --source-ref <ref> --destination <directory> [options]',
        '  public-preflight --destination <directory> [options]',
        '',
        'Use the Bash wrappers in tools/public-release/.',
    ].join('\n');
}

function parseArgs(command, rawArgs) {
    const options = {
        skipValidation: false,
    };

    const nextValue = (arg, index, inlineValue) => {
        if (inlineValue !== undefined) {
            if (inlineValue.length === 0) {
                throw new CliError(`Missing value for ${arg}.`);
            }
            return { value: inlineValue, nextIndex: index };
        }
        const value = rawArgs[index + 1];
        if (!value || value.startsWith('--')) {
            throw new CliError(`Missing value for ${arg}.`);
        }
        return { value, nextIndex: index + 1 };
    };

    for (let index = 0; index < rawArgs.length; index += 1) {
        const arg = rawArgs[index];
        const [name, inlineValue] = arg.startsWith('--') ? arg.split(/=(.*)/s, 2) : [arg, undefined];
        switch (name) {
            case '--source-ref': {
                const parsed = nextValue(name, index, inlineValue);
                options.sourceRef = parsed.value;
                index = parsed.nextIndex;
                break;
            }
            case '--source-commit': {
                const parsed = nextValue(name, index, inlineValue);
                options.sourceCommit = parsed.value;
                index = parsed.nextIndex;
                break;
            }
            case '--destination': {
                const parsed = nextValue(name, index, inlineValue);
                options.destination = parsed.value;
                index = parsed.nextIndex;
                break;
            }
            case '--deny-file':
            case '--deny-pattern-file': {
                const parsed = nextValue(name, index, inlineValue);
                options.userDenyFile = parsed.value;
                index = parsed.nextIndex;
                break;
            }
            case '--allowlist-file': {
                const parsed = nextValue(name, index, inlineValue);
                options.allowlistFile = parsed.value;
                index = parsed.nextIndex;
                break;
            }
            case '--audit-report': {
                const parsed = nextValue(name, index, inlineValue);
                options.auditReport = parsed.value;
                index = parsed.nextIndex;
                break;
            }
            case '--skip-validation':
                options.skipValidation = true;
                break;
            case '--help':
            case '-h':
                options.help = true;
                break;
            default:
                throw new CliError(`Unknown option: ${arg}`);
        }
    }

    if (command === 'export') {
        if (!options.help && !options.sourceRef) {
            throw new CliError('Missing required --source-ref option.');
        }
        if (options.sourceCommit) {
            throw new CliError('--source-commit is only valid with preflight.');
        }
    } else if (options.sourceRef) {
        throw new CliError('--source-ref is only valid with export.');
    }

    if (!options.help && !options.destination) {
        throw new CliError('Missing required --destination option.');
    }

    return options;
}

function normalizePosixPath(inputPath) {
    return inputPath.split(path.sep).join('/').replace(/\\/g, '/');
}

function normalizeComparablePath(inputPath) {
    const resolved = path.resolve(inputPath);
    return comparisonCaseInsensitive ? resolved.toLowerCase() : resolved;
}

function realpathLike(existingPath) {
    if (typeof fs.realpathSync.native === 'function') {
        return fs.realpathSync.native(existingPath);
    }
    return fs.realpathSync(existingPath);
}

function resolveActualTargetPath(targetPath) {
    const absoluteTarget = path.resolve(targetPath);
    if (fs.existsSync(absoluteTarget)) {
        return realpathLike(absoluteTarget);
    }

    const trailingSegments = [];
    let probe = absoluteTarget;
    while (!fs.existsSync(probe)) {
        const parent = path.dirname(probe);
        if (parent === probe) {
            return absoluteTarget;
        }
        trailingSegments.unshift(path.basename(probe));
        probe = parent;
    }

    return path.resolve(realpathLike(probe), ...trailingSegments);
}

function containsPath(parentPath, childPath) {
    const relative = path.relative(parentPath, childPath);
    return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

function assertOutsidePath(label, targetPath, blockedRoot, blockedLabel) {
    if (
        containsPath(
            normalizeComparablePath(resolveActualTargetPath(blockedRoot)),
            normalizeComparablePath(resolveActualTargetPath(targetPath)),
        )
    ) {
        throw new CliError(`${label} must be outside the ${blockedLabel}.`);
    }
}

function spawnCommand(command, args, options = {}) {
    return spawnSync(command, args, {
        cwd: options.cwd,
        input: options.input,
        encoding: options.encoding ?? 'utf8',
        env: options.env,
        maxBuffer: 64 * 1024 * 1024,
    });
}

function runCommand(command, args, options = {}) {
    const result = spawnCommand(command, args, options);
    if (result.error) {
        throw new CliError(`Failed to run ${command}: ${result.error.message}`);
    }
    return result;
}

function resolveSourceRepoRoot() {
    const result = runCommand('git', ['-C', sourceRepoRootHint, 'rev-parse', '--show-toplevel']);
    if (result.status !== 0) {
        throw new CliError((result.stderr || result.stdout || 'Unable to locate the source repository.').trim());
    }
    return realpathLike(result.stdout.trim());
}

function ensureCleanWorktree(sourceRepoRoot) {
    const result = runCommand('git', ['-C', sourceRepoRoot, 'status', '--porcelain', '--untracked-files=all']);
    if (result.status !== 0) {
        throw new CliError((result.stderr || result.stdout || 'Unable to inspect source worktree state.').trim());
    }
    if (result.stdout.trim().length > 0) {
        throw new CliError('Source worktree must be clean before running a public export.', 1);
    }
}

function resolveCommit(sourceRepoRoot, sourceRef) {
    const result = runCommand('git', ['-C', sourceRepoRoot, 'rev-parse', '--verify', `${sourceRef}^{commit}`]);
    if (result.status !== 0) {
        throw new CliError(`Unable to resolve source ref to a commit: ${sourceRef}`, 1);
    }
    return result.stdout.trim();
}

function resolveGitWorktreeRoot(targetPath) {
    const result = runCommand('git', ['-C', targetPath, 'rev-parse', '--show-toplevel']);
    if (result.status !== 0) {
        return null;
    }
    const worktreeRoot = result.stdout.trim();
    return worktreeRoot ? realpathLike(worktreeRoot) : null;
}

function inspectPathState(targetPath) {
    const absolutePath = path.resolve(targetPath);
    if (!fs.existsSync(absolutePath)) {
        return { path: absolutePath, exists: false };
    }

    const stats = fs.lstatSync(absolutePath);
    if (stats.isSymbolicLink()) {
        return { path: absolutePath, exists: true, type: 'symlink', stats };
    }
    if (stats.isDirectory()) {
        const entries = fs.readdirSync(absolutePath);
        return {
            path: absolutePath,
            exists: true,
            type: 'directory',
            stats,
            isEmpty: entries.length === 0,
        };
    }
    if (stats.isFile()) {
        return { path: absolutePath, exists: true, type: 'file', stats };
    }
    return { path: absolutePath, exists: true, type: 'other', stats };
}

function resolveDestinationPath(rawDestination, options = {}) {
    const destinationPath = path.resolve(process.cwd(), rawDestination);
    if (options.sourceRepoRoot) {
        assertOutsidePath('Destination', destinationPath, options.sourceRepoRoot, 'source repository');
    }

    const state = inspectPathState(destinationPath);
    if (state.exists) {
        if (state.type !== 'directory') {
            throw new CliError('Destination must be a directory path.', 1);
        }
        if (!options.mustBeExisting && !state.isEmpty) {
            throw new CliError('Destination directory must be empty.', 1);
        }
        return { path: destinationPath, existed: true };
    }

    if (options.mustBeExisting) {
        throw new CliError('Destination directory does not exist.', 1);
    }

    return { path: destinationPath, existed: false };
}

function resolveAuditReportPath(rawAuditReport, destinationPath, options = {}) {
    const auditReportPath = path.resolve(
        process.cwd(),
        rawAuditReport ?? `${destinationPath}.audit.txt`,
    );
    if (options.sourceRepoRoot) {
        assertOutsidePath('Audit report', auditReportPath, options.sourceRepoRoot, 'source repository');
    }
    if (
        containsPath(
            normalizeComparablePath(resolveActualTargetPath(destinationPath)),
            normalizeComparablePath(resolveActualTargetPath(auditReportPath)),
        )
    ) {
        throw new CliError('Audit report must be outside the exported destination tree.', 1);
    }
    fs.mkdirSync(path.dirname(auditReportPath), { recursive: true });
    if (fs.existsSync(auditReportPath)) {
        const auditReportStats = fs.lstatSync(auditReportPath);
        if (auditReportStats.isSymbolicLink() || auditReportStats.isDirectory()) {
            throw new CliError('Audit report path must be a regular file path.', 1);
        }
    }
    return auditReportPath;
}

function createTemporarySiblingDirectory(destinationPath) {
    const parentPath = path.dirname(destinationPath);
    const baseName = path.basename(destinationPath);
    fs.mkdirSync(parentPath, { recursive: true });

    for (let attempt = 0; attempt < 128; attempt += 1) {
        const suffix = `${process.pid}-${Date.now().toString(36)}-${crypto.randomBytes(6).toString('hex')}`;
        const candidate = path.join(parentPath, `.${baseName}.public-release-staging-${suffix}`);
        try {
            fs.mkdirSync(candidate, { recursive: false });
            return candidate;
        } catch (error) {
            if (error && error.code === 'EEXIST') {
                continue;
            }
            throw new CliError(`Unable to create temporary export staging directory: ${error.message}`, 1);
        }
    }

    throw new CliError('Unable to allocate a unique temporary export staging directory.', 1);
}

function cleanupPathIfExists(targetPath) {
    if (!targetPath || !fs.existsSync(targetPath)) {
        return;
    }
    fs.rmSync(targetPath, { recursive: true, force: true });
}

function assertDestinationReadyForPublish(destinationPath) {
    const state = inspectPathState(destinationPath);
    if (!state.exists) {
        return state;
    }
    if (state.type !== 'directory') {
        throw new CliError('Destination must remain a directory path until publish completes.', 1);
    }
    if (!state.isEmpty) {
        throw new CliError(publishRaceMessage, 1);
    }
    return state;
}

function publishExportedTree(stagingPath, destinationPath) {
    const publishState = assertDestinationReadyForPublish(destinationPath);

    if (!publishState.exists) {
        try {
            fs.renameSync(stagingPath, destinationPath);
        } catch (error) {
            throw new CliError(`Failed to publish exported tree: ${error.message}`, 1);
        }
        return;
    }

    try {
        fs.rmdirSync(destinationPath);
    } catch (error) {
        throw new CliError(`${publishRaceMessage} ${error.message}`, 1);
    }

    try {
        fs.renameSync(stagingPath, destinationPath);
    } catch (error) {
        try {
            if (!fs.existsSync(destinationPath)) {
                fs.mkdirSync(destinationPath, { recursive: false });
            }
        } catch {
            // Best effort to restore the original empty destination on failure.
        }
        throw new CliError(`Failed to publish exported tree: ${error.message}`, 1);
    }
}

function exportTree(sourceRepoRoot, sourceCommit, destinationPath) {
    return new Promise((resolve, reject) => {
        const archive = spawn('git', ['-C', sourceRepoRoot, 'archive', '--format=tar', sourceCommit], {
            stdio: ['ignore', 'pipe', 'pipe'],
        });
        const untar = spawn('tar', ['-xf', '-', '-C', destinationPath], {
            stdio: ['pipe', 'ignore', 'pipe'],
        });

        let archiveError = '';
        let untarError = '';
        let settled = false;
        let archiveClosed = false;
        let untarClosed = false;
        let archiveCode = 1;
        let untarCode = 1;

        const finalize = () => {
            if (settled || !archiveClosed || !untarClosed) {
                return;
            }
            settled = true;
            if (untarCode !== 0) {
                reject(new CliError(`tar extraction failed: ${(untarError || 'unknown error').trim()}`, 1));
                return;
            }
            if (archiveCode !== 0) {
                reject(new CliError(`git archive failed: ${(archiveError || 'unknown error').trim()}`, 1));
                return;
            }
            resolve();
        };

        archive.stdout.pipe(untar.stdin);
        archive.stdout.on('error', (error) => {
            if (error.code === 'EPIPE') {
                return;
            }
            if (!settled) {
                settled = true;
                reject(new CliError(`git archive stream failed: ${error.message}`, 1));
            }
        });
        untar.stdin.on('error', (error) => {
            if (error.code === 'EPIPE') {
                return;
            }
            if (!settled) {
                settled = true;
                reject(new CliError(`tar input stream failed: ${error.message}`, 1));
            }
        });
        archive.stderr.on('data', (chunk) => {
            archiveError += chunk.toString('utf8');
        });
        untar.stderr.on('data', (chunk) => {
            untarError += chunk.toString('utf8');
        });

        archive.on('error', (error) => {
            if (!settled) {
                settled = true;
                reject(new CliError(`Failed to start git archive: ${error.message}`));
            }
        });
        untar.on('error', (error) => {
            if (!settled) {
                settled = true;
                reject(new CliError(`Failed to start tar extraction: ${error.message}`));
            }
        });

        archive.on('close', (code) => {
            archiveClosed = true;
            archiveCode = code ?? 1;
            finalize();
        });
        untar.on('close', (code) => {
            untarClosed = true;
            untarCode = code ?? 1;
            if (untarCode !== 0 && !archiveClosed) {
                archive.stdout.unpipe(untar.stdin);
                archive.kill('SIGTERM');
            }
            finalize();
        });
    });
}

function loadJsonFile(label, filePath) {
    try {
        return JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch (error) {
        throw new CliError(`Unable to read ${label} ${filePath}: ${error.message}`);
    }
}

function parseRuleDocument(label, document, options = {}) {
    const parseRules = (kind, entries) => {
        if (entries === undefined) {
            return [];
        }
        if (!Array.isArray(entries)) {
            throw new CliError(`${label} field ${kind} must be an array.`);
        }
        return entries.map((entry, index) => {
            if (!entry || typeof entry !== 'object') {
                throw new CliError(`${label} ${kind}[${index}] must be an object.`);
            }
            const id = `${entry.id ?? ''}`.trim();
            const pattern = `${entry.pattern ?? ''}`;
            const description = `${entry.description ?? ''}`.trim();
            const flags = `${entry.flags ?? ''}`;
            if (!id || !pattern || !description) {
                throw new CliError(`${label} ${kind}[${index}] requires id, pattern, and description.`);
            }
            try {
                return {
                    id,
                    description,
                    regex: new RegExp(pattern, flags),
                    allowlistWaivable: options.forceNonWaivable
                        ? false
                        : kind === 'content' && entry.allowlistWaivable === true,
                };
            } catch (error) {
                throw new CliError(`Invalid deny pattern ${id}: ${error.message}`);
            }
        });
    };

    return {
        pathRules: parseRules('path', document.path),
        contentRules: parseRules('content', document.content),
    };
}

function mergeRuleSets(ruleSets) {
    return ruleSets.reduce(
        (merged, ruleSet) => ({
            pathRules: [...merged.pathRules, ...ruleSet.pathRules],
            contentRules: [...merged.contentRules, ...ruleSet.contentRules],
        }),
        { pathRules: [], contentRules: [] },
    );
}

function resolveDenyRuleSources(options) {
    const sources = [];
    const automaticPrivateFilePath = path.join(scriptDir, privateDenyPatternFileName);
    if (fs.existsSync(automaticPrivateFilePath)) {
        const stats = fs.lstatSync(automaticPrivateFilePath);
        if (!stats.isFile()) {
            throw new CliError(`${privateDenyPatternFileName} must be a regular file when present.`, 1);
        }
        sources.push({
            label: privateDenyPatternFileName,
            path: automaticPrivateFilePath,
            forceNonWaivable: true,
        });
    }

    if (options.userDenyFile) {
        const userPath = path.resolve(process.cwd(), options.userDenyFile);
        const duplicate = sources.some((source) => normalizeComparablePath(source.path) === normalizeComparablePath(userPath));
        if (!duplicate) {
            sources.push({
                label: 'deny file',
                path: userPath,
                forceNonWaivable: false,
            });
        }
    }

    return sources;
}

function loadDenyRules(options) {
    const sources = resolveDenyRuleSources(options);
    if (sources.length === 0) {
        return { pathRules: [], contentRules: [] };
    }

    const ruleSets = sources.map((source) => {
        const document = loadJsonFile(source.label, source.path);
        return parseRuleDocument(source.label, document, {
            forceNonWaivable: source.forceNonWaivable === true,
        });
    });
    return mergeRuleSets(ruleSets);
}

function buildAllowlistKey(kind, entryPath, ruleId, details = {}) {
    if (kind === 'content') {
        return `${kind}\u0000${entryPath}\u0000${ruleId}\u0000${details.line}\u0000${details.matchHash}`;
    }
    if (kind === 'path') {
        return `${kind}\u0000${entryPath}\u0000${ruleId}`;
    }
    return null;
}

function loadAllowlist(filePath) {
    if (!filePath) {
        return { entries: [], entryMap: new Map() };
    }

    const resolvedPath = path.resolve(process.cwd(), filePath);
    const document = loadJsonFile('allowlist file', resolvedPath);
    if (!document || typeof document !== 'object' || !Array.isArray(document.entries)) {
        throw new CliError('allowlist file must contain an entries array.');
    }

    const entryMap = new Map();
    const entries = document.entries.map((entry, index) => {
        if (!entry || typeof entry !== 'object') {
            throw new CliError(`allowlist entry ${index} must be an object.`);
        }
        const kind = `${entry.kind ?? ''}`.trim();
        const entryPath = normalizePosixPath(`${entry.path ?? ''}`.trim());
        const ruleId = `${entry.ruleId ?? ''}`.trim();
        const reviewedBy = `${entry.reviewedBy ?? ''}`.trim();
        const reason = `${entry.reason ?? ''}`.trim();
        if (!['path', 'content'].includes(kind) || !entryPath || !ruleId || !reviewedBy || !reason) {
            throw new CliError(
                `allowlist entry ${index} requires kind, path, ruleId, reviewedBy, and reason.`,
            );
        }

        let line;
        let matchHash;
        if (kind === 'content') {
            line = Number(entry.line);
            matchHash = `${entry.matchHash ?? ''}`.trim().toLowerCase();
            if (!Number.isInteger(line) || line < 1 || !matchHash) {
                throw new CliError(
                    `allowlist content entry ${index} requires positive integer line and non-empty matchHash.`,
                );
            }
        }

        const key = buildAllowlistKey(kind, entryPath, ruleId, { line, matchHash });
        if (!key) {
            throw new CliError(`Unsupported allowlist kind at entry ${index}: ${kind}.`);
        }
        if (entryMap.has(key)) {
            throw new CliError(`Duplicate allowlist entry for ${kind} ${entryPath} ${ruleId}.`);
        }
        const normalizedEntry = {
            kind,
            path: entryPath,
            ruleId,
            reviewedBy,
            reason,
            line,
            matchHash,
            key,
        };
        entryMap.set(key, normalizedEntry);
        return normalizedEntry;
    });

    return { entries, entryMap };
}

function collectEntries(rootPath, options = {}) {
    const entries = [];

    const walk = (currentPath, relativePrefix) => {
        const directoryEntries = fs.readdirSync(currentPath, { withFileTypes: true })
            .sort((left, right) => left.name.localeCompare(right.name));
        for (const entry of directoryEntries) {
            if (options.ignoreRootGitMetadata === true && !relativePrefix && entry.name === '.git') {
                continue;
            }
            const absolutePath = path.join(currentPath, entry.name);
            const relativePath = relativePrefix ? `${relativePrefix}/${entry.name}` : entry.name;
            const stats = fs.lstatSync(absolutePath);
            if (stats.isDirectory()) {
                walk(absolutePath, relativePath);
                continue;
            }

            const entryType = stats.isSymbolicLink() ? 'symlink' : 'file';
            entries.push({ absolutePath, relativePath, stats, entryType });
        }
    };

    walk(rootPath, '');
    entries.sort((left, right) => left.relativePath.localeCompare(right.relativePath));
    return entries;
}

function isGitAttributeEnabled(value) {
    return value !== '' && value !== 'unspecified' && value !== 'unset';
}

function loadExportIgnorePaths(rootPath, trackedPaths) {
    if (trackedPaths.length === 0) {
        return new Set();
    }

    const result = runCommand(
        'git',
        ['-C', rootPath, 'check-attr', '--stdin', '-z', 'export-ignore'],
        { input: `${trackedPaths.join('\u0000')}\u0000` },
    );
    if (result.status !== 0) {
        throw new CliError((result.stderr || result.stdout || 'Unable to evaluate export-ignore attributes.').trim(), 1);
    }

    const exportIgnorePaths = new Set();
    const records = result.stdout.split('\u0000');
    for (let index = 0; index + 2 < records.length; index += 3) {
        const relativePath = normalizePosixPath(records[index]);
        const attributeName = records[index + 1];
        const attributeValue = records[index + 2];
        if (!relativePath || attributeName !== 'export-ignore') {
            continue;
        }
        if (isGitAttributeEnabled(attributeValue)) {
            exportIgnorePaths.add(relativePath);
        }
    }

    return exportIgnorePaths;
}

function collectTrackedEntries(rootPath) {
    const result = runCommand('git', ['-C', rootPath, 'ls-files', '-z']);
    if (result.status !== 0) {
        throw new CliError((result.stderr || result.stdout || 'Unable to enumerate tracked worktree entries.').trim(), 1);
    }

    const trackedPaths = result.stdout
        .split('\u0000')
        .filter(Boolean)
        .map((rawRelativePath) => normalizePosixPath(rawRelativePath));
    const exportIgnorePaths = loadExportIgnorePaths(rootPath, trackedPaths);
    const entries = [];
    const seenPaths = new Set();
    for (const relativePath of trackedPaths) {
        if (seenPaths.has(relativePath)) {
            continue;
        }
        seenPaths.add(relativePath);
        if (exportIgnorePaths.has(relativePath)) {
            continue;
        }

        const absolutePath = path.join(rootPath, ...relativePath.split('/'));
        if (!fs.existsSync(absolutePath)) {
            continue;
        }

        const stats = fs.lstatSync(absolutePath);
        if (stats.isDirectory()) {
            continue;
        }

        const entryType = stats.isSymbolicLink() ? 'symlink' : 'file';
        entries.push({ absolutePath, relativePath, stats, entryType });
    }

    entries.sort((left, right) => left.relativePath.localeCompare(right.relativePath));
    return entries;
}

function isLikelyText(buffer) {
    return !buffer.includes(0);
}

function sha256Hex(buffer) {
    return crypto.createHash('sha256').update(buffer).digest('hex');
}

function lineAndColumnForIndex(text, index) {
    let line = 1;
    let column = 1;
    for (let cursor = 0; cursor < index; cursor += 1) {
        if (text.charCodeAt(cursor) === 10) {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return { line, column };
}

function occurrenceHashForMatch(text, matchIndex, matchText, location) {
    const contextStart = Math.max(0, matchIndex - contentHashContextRadius);
    const contextEnd = Math.min(text.length, matchIndex + matchText.length + contentHashContextRadius);
    const context = text.slice(contextStart, contextEnd);
    return sha256Hex(Buffer.from(JSON.stringify({
        line: location.line,
        column: location.column,
        matchText,
        context,
    }), 'utf8'));
}

function createGlobalRegex(regex) {
    const flags = regex.flags.includes('g') ? regex.flags : `${regex.flags}g`;
    return new RegExp(regex.source, flags);
}

function collectContentFindings(text, relativePath, rule) {
    const findings = [];
    const globalRegex = createGlobalRegex(rule.regex);
    let match;
    while ((match = globalRegex.exec(text)) !== null) {
        const matchText = match[0];
        const location = lineAndColumnForIndex(text, match.index);
        findings.push({
            kind: 'content',
            ruleId: rule.id,
            path: relativePath,
            line: location.line,
            column: location.column,
            matchHash: occurrenceHashForMatch(text, match.index, matchText, location),
            message: rule.description,
            allowlistWaivable: rule.allowlistWaivable === true,
        });
        if (matchText.length === 0) {
            globalRegex.lastIndex += 1;
        }
    }
    return findings;
}

function hasHardPlaceholderFinding(findings, targetPath) {
    return findings.some(
        (finding) => finding.path === targetPath
            && ['path-public-placeholder', 'content-public-placeholder'].includes(finding.ruleId),
    );
}

function codeownersHasConcreteRule(text) {
    return text.split(/\r?\n/u).some((line) => {
        const trimmedLine = line.trim();
        if (!trimmedLine || trimmedLine.startsWith('#')) {
            return false;
        }

        const meaningfulTokens = [];
        for (const token of trimmedLine.split(/\s+/u)) {
            if (token.startsWith('#')) {
                break;
            }
            meaningfulTokens.push(token);
        }

        if (meaningfulTokens.length < 2) {
            return false;
        }

        return meaningfulTokens
            .slice(1)
            .some((owner) => /[A-Za-z0-9@]/u.test(owner));
    });
}

function evaluateCodeownersGate(fileRecords, findings) {
    const codeownersEntry = fileRecords.find((file) => codeownersPathPattern.test(file.path));
    if (!codeownersEntry || codeownersEntry.type !== 'file') {
        return {
            kind: 'gate',
            ruleId: 'required-codeowners-gate',
            path: codeownersRelativePath,
            message: CODEOWNERS_GATE_MESSAGE,
        };
    }

    if (hasHardPlaceholderFinding(findings, codeownersEntry.path)) {
        return null;
    }

    if (typeof codeownersEntry.text !== 'string' || !codeownersHasConcreteRule(codeownersEntry.text)) {
        return {
            kind: 'gate',
            ruleId: 'required-codeowners-gate',
            path: codeownersEntry.path,
            message: CODEOWNERS_GATE_MESSAGE,
        };
    }

    return null;
}

function evaluateLicenseGate(fileRecords, findings) {
    const licenseCandidates = fileRecords.filter((file) => licenseFilePattern.test(file.path));
    const resolvedLicense = licenseCandidates.find(
        (file) => file.type === 'file'
            && !hasHardPlaceholderFinding(findings, file.path)
            && typeof file.text === 'string'
            && file.text.trim().length > 0,
    );
    if (resolvedLicense) {
        return null;
    }

    const hasPlaceholderLicense = licenseCandidates.some(
        (file) => file.type === 'file' && hasHardPlaceholderFinding(findings, file.path),
    );
    if (hasPlaceholderLicense) {
        return null;
    }

    return {
        kind: 'gate',
        ruleId: 'required-license-gate',
        path: licenseCandidates[0]?.path ?? 'LICENSE',
        message: LICENSE_GATE_MESSAGE,
    };
}

function findingAllowlistKey(finding) {
    if (finding.allowlistWaivable !== true) {
        return null;
    }
    if (finding.kind === 'content') {
        return buildAllowlistKey(finding.kind, finding.path, finding.ruleId, {
            line: finding.line,
            matchHash: finding.matchHash,
        });
    }
    if (finding.kind === 'path') {
        return buildAllowlistKey(finding.kind, finding.path, finding.ruleId);
    }
    return null;
}

function addFinding(findings, allowlistState, finding) {
    const key = findingAllowlistKey(finding);
    if (key) {
        const allowlistEntry = allowlistState.entryMap.get(key);
        if (allowlistEntry) {
            allowlistState.usedKeys.add(key);
            allowlistState.applied.push({ finding, allowlistEntry });
            return;
        }
    }
    findings.push(finding);
}

function scanExportedTree(destinationPath, options) {
    const extraRules = loadDenyRules(options);
    const allowlist = loadAllowlist(options.allowlistFile);
    const allowlistState = {
        entryMap: allowlist.entryMap,
        usedKeys: new Set(),
        applied: [],
        entries: allowlist.entries,
    };
    const allPathRules = [...DEFAULT_PATH_RULES, ...extraRules.pathRules];
    const allContentRules = [...DEFAULT_CONTENT_RULES, ...extraRules.contentRules];
    const files = [];
    const fileRecords = [];
    const findings = [];

    const collectedEntries = options.gitTrackedRootScan === true
        ? collectTrackedEntries(destinationPath)
        : collectEntries(destinationPath, {
            ignoreRootGitMetadata: options.ignoreRootGitMetadata === true,
        });

    for (const entry of collectedEntries) {
        const relativePath = normalizePosixPath(entry.relativePath);
        let hash;
        let text;

        if (entry.entryType === 'symlink') {
            const target = fs.readlinkSync(entry.absolutePath);
            hash = sha256Hex(Buffer.from(target, 'utf8'));
            findings.push({
                kind: 'symlink',
                ruleId: 'symlink-entry',
                path: relativePath,
                message: symlinkEntryMessage,
            });
        } else {
            const buffer = fs.readFileSync(entry.absolutePath);
            hash = sha256Hex(buffer);
            if (isLikelyText(buffer)) {
                text = buffer.toString('utf8');
            }
        }

        files.push({ path: relativePath, hash, type: entry.entryType });
        fileRecords.push({ path: relativePath, hash, type: entry.entryType, text });

        for (const rule of allPathRules) {
            rule.regex.lastIndex = 0;
            if (rule.regex.test(relativePath)) {
                addFinding(findings, allowlistState, {
                    kind: 'path',
                    ruleId: rule.id,
                    path: relativePath,
                    message: rule.description,
                    allowlistWaivable: rule.allowlistWaivable === true,
                });
            }
        }

        if (typeof text === 'string') {
            for (const rule of allContentRules) {
                for (const finding of collectContentFindings(text, relativePath, rule)) {
                    addFinding(findings, allowlistState, finding);
                }
            }
        }
    }

    const regularFiles = fileRecords.filter((file) => file.type === 'file');
    for (const requirement of REQUIRED_FILE_RULES) {
        const present = regularFiles.some((file) => requirement.patterns.some((pattern) => pattern.test(file.path)));
        if (!present) {
            findings.push({
                kind: 'required',
                ruleId: requirement.id,
                message: `Missing required public file: ${requirement.label}.`,
            });
        }
    }

    const codeownersGateFinding = evaluateCodeownersGate(fileRecords, findings);
    if (codeownersGateFinding) {
        findings.push(codeownersGateFinding);
    }
    const licenseGateFinding = evaluateLicenseGate(fileRecords, findings);
    if (licenseGateFinding) {
        findings.push(licenseGateFinding);
    }

    const unusedAllowlistEntries = allowlistState.entries.filter(
        (entry) => !allowlistState.usedKeys.has(entry.key),
    );

    findings.sort(compareFindings);
    files.sort((left, right) => left.path.localeCompare(right.path));

    return {
        files,
        findings,
        appliedAllowlist: allowlistState.applied,
        unusedAllowlistEntries,
    };
}

function compareFindings(left, right) {
    const comparisons = [
        left.kind.localeCompare(right.kind),
        `${left.path ?? ''}`.localeCompare(`${right.path ?? ''}`),
        `${left.ruleId}`.localeCompare(`${right.ruleId}`),
        (left.line ?? 0) - (right.line ?? 0),
        (left.column ?? 0) - (right.column ?? 0),
        `${left.matchHash ?? ''}`.localeCompare(`${right.matchHash ?? ''}`),
    ];
    for (const comparison of comparisons) {
        if (comparison !== 0) {
            return comparison;
        }
    }
    return 0;
}

function createValidationPlaceholderResults(status, message) {
    return VALIDATOR_DEFINITIONS.map((validator) => ({
        id: validator.id,
        status,
        commandLine: validator.commandLine,
        scriptRelativePath: validator.scriptRelativePath,
        message,
    }));
}

function collectCommandOutput(result) {
    return `${result.stdout ?? ''}${result.stderr ?? ''}`.trim();
}

function runSingleValidator(destinationPath, validator) {
    const scriptPath = path.join(destinationPath, ...validator.scriptRelativePath.split('/'));
    const baseResult = {
        id: validator.id,
        commandLine: validator.commandLine,
        scriptRelativePath: validator.scriptRelativePath,
    };

    if (!fs.existsSync(scriptPath)) {
        return {
            ...baseResult,
            status: 'failed',
            message: `Missing ${validator.scriptRelativePath} in the exported tree.`,
        };
    }

    const result = spawnCommand(validator.command, validator.buildArgs(scriptPath), {
        cwd: destinationPath,
    });
    const output = collectCommandOutput(result);
    if (result.error) {
        if (result.error.code === 'ENOENT') {
            return {
                ...baseResult,
                status: 'failed',
                message: `Missing validator runtime: ${validator.command}.`,
            };
        }
        return {
            ...baseResult,
            status: 'failed',
            message: `Failed to start ${validator.commandLine}: ${result.error.message}`,
            output: output || undefined,
        };
    }

    if (result.status !== 0) {
        return {
            ...baseResult,
            status: 'failed',
            exitCode: result.status ?? 1,
            message: `${validator.commandLine} failed with exit code ${result.status ?? 1}.`,
            output: output || undefined,
        };
    }

    return {
        ...baseResult,
        status: 'passed',
        exitCode: result.status ?? 0,
        message: 'Passed.',
        output: output || undefined,
    };
}

function runValidation(destinationPath, options) {
    if (options.skipValidation) {
        return {
            status: 'skipped',
            message: VALIDATION_SKIP_MESSAGE,
            results: createValidationPlaceholderResults('skipped', 'Skipped by --skip-validation.'),
        };
    }

    const results = VALIDATOR_DEFINITIONS.map((validator) => runSingleValidator(destinationPath, validator));
    const status = results.every((result) => result.status === 'passed') ? 'passed' : 'failed';
    return { status, results };
}

function buildValidationFindings(validation) {
    if (validation.status === 'skipped') {
        return [{
            kind: 'validation',
            ruleId: 'validation-skipped',
            message: validation.message,
        }];
    }

    if (validation.status !== 'failed') {
        return [];
    }

    return validation.results
        .filter((result) => result.status === 'failed')
        .map((result) => ({
            kind: 'validation',
            ruleId: `validation-${result.id}`,
            message: result.message,
        }));
}

function buildReport(baseReport, scan, validation) {
    const findings = [
        ...scan.findings,
        ...buildValidationFindings(validation),
    ];
    findings.sort(compareFindings);
    return {
        ...baseReport,
        validation,
        files: scan.files,
        findings,
        appliedAllowlist: scan.appliedAllowlist,
        unusedAllowlistEntries: scan.unusedAllowlistEntries,
    };
}

function formatFindingLocation(finding) {
    if (!finding.path) {
        return '';
    }
    let location = ` ${finding.path}`;
    if (finding.line !== undefined) {
        location += `:${finding.line}`;
    }
    if (finding.column !== undefined) {
        location += `:${finding.column}`;
    }
    if (finding.matchHash) {
        location += ` match_hash=${finding.matchHash}`;
    }
    return location;
}

function formatAllowlistEntryLocation(entry) {
    let location = ` ${entry.path}`;
    if (entry.kind === 'content') {
        location += `:${entry.line}`;
        location += ` match_hash=${entry.matchHash}`;
    }
    return location;
}

function formatValidationStatus(validation) {
    const perValidator = validation.results
        ?.map((result) => `${result.id}=${result.status}`)
        .join(', ');
    return perValidator ? `${validation.status} (${perValidator})` : validation.status;
}

function validatorResultAuditLines(result) {
    const lines = [
        `[${result.id}] status=${result.status} command=${result.commandLine}${result.exitCode !== undefined ? ` exit_code=${result.exitCode}` : ''}`,
    ];

    if (result.status !== 'passed' || result.output) {
        lines.push(`message: ${result.message}`);
    }

    if (result.output) {
        lines.push('output:');
        for (const line of result.output.split('\n')) {
            lines.push(`  ${line}`);
        }
    }

    return lines;
}

function writeAuditReport(reportPath, report) {
    const lines = [
        'PUBLIC RELEASE AUDIT REPORT',
        `generated_at: ${new Date().toISOString()}`,
        `mode: ${report.mode}`,
        `source_ref: ${report.sourceRef ?? 'n/a'}`,
        `source_commit: ${report.sourceCommit ?? 'unknown'}`,
        `destination_name: ${path.basename(report.destinationPath)}`,
        `preflight: ${report.findings.length === 0 ? 'passed' : 'failed'}`,
        `validation: ${report.validation.status}`,
        `finding_count: ${report.findings.length}`,
        '',
        'VALIDATOR RESULTS',
    ];

    for (const result of report.validation.results ?? []) {
        lines.push(...validatorResultAuditLines(result));
    }

    lines.push('', 'FINDINGS');
    if (report.findings.length === 0) {
        lines.push('none');
    } else {
        for (const finding of report.findings) {
            lines.push(`[${finding.kind}|${finding.ruleId}]${formatFindingLocation(finding)} ${finding.message}`);
        }
    }

    lines.push('', 'ALLOWLIST APPLIED');
    if (report.appliedAllowlist.length === 0) {
        lines.push('none');
    } else {
        for (const applied of report.appliedAllowlist) {
            lines.push(
                `[${applied.finding.kind}|${applied.finding.ruleId}]${formatFindingLocation(applied.finding)} reviewedBy=${applied.allowlistEntry.reviewedBy} reason=${applied.allowlistEntry.reason}`,
            );
        }
    }

    lines.push('', 'UNUSED ALLOWLIST ENTRIES');
    if (report.unusedAllowlistEntries.length === 0) {
        lines.push('none');
    } else {
        for (const entry of report.unusedAllowlistEntries) {
            lines.push(`[${entry.kind}|${entry.ruleId}]${formatAllowlistEntryLocation(entry)} reviewedBy=${entry.reviewedBy}`);
        }
    }

    if (report.validation.message) {
        lines.push('', 'VALIDATION SUMMARY', report.validation.message);
    }

    lines.push('', 'EXPORTED FILES');
    for (const file of report.files) {
        const suffix = file.type === 'symlink' ? ' [symlink]' : '';
        lines.push(`${file.hash}  ${file.path}${suffix}`);
    }

    fs.writeFileSync(reportPath, `${lines.join('\n')}\n`, 'utf8');
}

function printSummary(reportPath, report) {
    const preflightStatus = report.findings.length === 0 ? 'passed' : 'failed';
    console.log(`Audit report: ${reportPath}`);
    console.log(`Preflight: ${preflightStatus}`);
    console.log(`Validation: ${formatValidationStatus(report.validation)}`);
    if (report.findings.length > 0) {
        for (const finding of report.findings.slice(0, 12)) {
            console.log(`- [${finding.ruleId}]${formatFindingLocation(finding)} ${finding.message}`);
        }
        if (report.findings.length > 12) {
            console.log(`- ... ${report.findings.length - 12} more finding(s)`);
        }
    }
    for (const result of report.validation.results ?? []) {
        if (result.output) {
            console.log(`Validation output (${result.id}):`);
            console.log(result.output);
        }
    }
}

function extractionFailureReport(baseReport, message) {
    return {
        ...baseReport,
        validation: {
            status: 'not-run',
            message: VALIDATION_NOT_RUN_MESSAGE,
            results: createValidationPlaceholderResults('not-run', VALIDATION_NOT_RUN_MESSAGE),
        },
        files: [],
        findings: [{ kind: 'export', ruleId: 'archive-extraction', message }],
        appliedAllowlist: [],
        unusedAllowlistEntries: [],
    };
}

async function runExport(options) {
    const sourceRepoRoot = resolveSourceRepoRoot();
    ensureCleanWorktree(sourceRepoRoot);
    const sourceCommit = resolveCommit(sourceRepoRoot, options.sourceRef);
    const destination = resolveDestinationPath(options.destination, {
        sourceRepoRoot,
        mustBeExisting: false,
    });
    const auditReportPath = resolveAuditReportPath(options.auditReport, destination.path, {
        sourceRepoRoot,
    });
    const stagingPath = createTemporarySiblingDirectory(destination.path);
    const baseReport = {
        mode: 'export',
        sourceRef: options.sourceRef,
        sourceCommit,
        destinationPath: destination.path,
    };

    try {
        try {
            await exportTree(sourceRepoRoot, sourceCommit, stagingPath);
        } catch (error) {
            const report = extractionFailureReport(baseReport, error.message);
            writeAuditReport(auditReportPath, report);
            printSummary(auditReportPath, report);
            process.exitCode = 1;
            return;
        }

        const scan = scanExportedTree(stagingPath, {
            ...options,
            ignoreRootGitMetadata: false,
        });
        const validation = runValidation(stagingPath, options);
        const report = buildReport(baseReport, scan, validation);
        if (report.findings.length > 0) {
            writeAuditReport(auditReportPath, report);
            printSummary(auditReportPath, report);
            process.exitCode = 1;
            return;
        }

        try {
            publishExportedTree(stagingPath, destination.path);
        } catch (error) {
            report.findings.push({
                kind: 'publish',
                ruleId: 'destination-publish',
                message: error.message,
            });
            report.findings.sort(compareFindings);
            writeAuditReport(auditReportPath, report);
            printSummary(auditReportPath, report);
            process.exitCode = 1;
            return;
        }

        writeAuditReport(auditReportPath, report);
        printSummary(auditReportPath, report);
        process.exitCode = 0;
    } finally {
        cleanupPathIfExists(stagingPath);
    }
}

function runPreflight(options) {
    const destination = resolveDestinationPath(options.destination, {
        mustBeExisting: true,
    });
    const auditReportPath = resolveAuditReportPath(options.auditReport, destination.path);
    const worktreeRoot = resolveGitWorktreeRoot(destination.path);
    const gitTrackedRootScan =
        worktreeRoot !== null
        && normalizeComparablePath(resolveActualTargetPath(destination.path))
            === normalizeComparablePath(worktreeRoot);
    const scan = scanExportedTree(destination.path, {
        ...options,
        gitTrackedRootScan,
        ignoreRootGitMetadata: gitTrackedRootScan,
    });
    const validation = runValidation(destination.path, options);
    const report = buildReport(
        {
            mode: 'preflight',
            sourceCommit: options.sourceCommit ?? null,
            destinationPath: destination.path,
        },
        scan,
        validation,
    );

    writeAuditReport(auditReportPath, report);
    printSummary(auditReportPath, report);
    process.exitCode = report.findings.length === 0 ? 0 : 1;
}

async function main() {
    const [command, ...rawArgs] = process.argv.slice(2);
    if (!command || command === 'help' || command === '--help' || command === '-h') {
        console.log(usage());
        return;
    }
    if (!['export', 'preflight'].includes(command)) {
        throw new CliError(`Unknown command: ${command}`);
    }

    const options = parseArgs(command, rawArgs);
    if (options.help) {
        console.log(usage(command));
        return;
    }

    if (command === 'export') {
        await runExport(options);
        return;
    }

    runPreflight(options);
}

main().catch((error) => {
    if (error instanceof CliError) {
        console.error(`ERROR: ${error.message}`);
        process.exit(error.exitCode);
        return;
    }
    console.error(`ERROR: ${error.stack || error.message}`);
    process.exit(1);
});
