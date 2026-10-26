#!/usr/bin/env bun
/**
 * skill-update: keeps the skills in the shared store up to date from their
 * upstream GitHub repos. Runs in the background, at most once per check
 * interval: with bun on NixOS (claude-shared hook), and with bun or, failing
 * that, node (--experimental-strip-types) on Windows (hook.ps1).
 *
 * Where sources come from (all merged, never removed):
 *   - shared.json "skillSources": repos added by hand, e.g. a bundle of
 *     hundreds of skills ({"repo": "owner/name", "dir": "skills"}) or one
 *     skill ({"repo": ..., "skill": "name", "path": "dir/in/repo"});
 *   - every `npx skills` lock file (~/.agents/.skill-lock.json) on any OS;
 *   - discovery, for every other skill: GitHub links in its frontmatter and a
 *     skills.sh search by name give candidate repos; a candidate is accepted
 *     only if it contains a skill of that name whose SKILL.md matches ours.
 *     A few skills are looked up per run; a miss is retried after MISS_DAYS.
 *   All of it is remembered in _sync/skill-sources.json, shared by both OSes.
 *
 * Skipped: claude.ai account skills (.account-skill), skills a live link keeps
 * current (.linked-from) until an upstream is known for them, and personal
 * skills no public repo has. Once a linked skill has an upstream, its link
 * marker is dropped and .skill-source written, so the link copy stops
 * overwriting the updates (claude-shared re-points the Linux link too).
 *
 * Crash safety: a new version is staged in _sync/tmp, a journal is written,
 * then the old folder is moved to _sync/skill-history/<name>/<stamp> and the
 * staged one moved in. Both are renames on the same drive. A run interrupted
 * at any point (power cut, killed hook) is finished or rolled back by the
 * next run. Old versions are kept (last KEEP_HISTORY per skill), so a local
 * edit overwritten by an update can always be recovered.
 */
import { createHash } from "node:crypto";
import {
  cpSync, existsSync, mkdirSync, openSync, closeSync, readdirSync, readFileSync,
  renameSync, rmSync, statSync, unlinkSync, writeFileSync, appendFileSync,
} from "node:fs";
import { spawnSync } from "node:child_process";
import { basename, dirname, join, relative, sep } from "node:path";

const KEEP_HISTORY = 3;
const DEFAULT_INTERVAL_DAYS = 1;
const LOCK_STALE_MS = 2 * 60 * 60 * 1000;
// Discovery budget per run, and how long a skill with no public source waits
// before it is looked up again.
const MAX_LOOKUPS = 25;
const MAX_DOWNLOADS = 8;
const MISS_DAYS = 30;
const MIN_SIMILARITY = 0.6;
// Our own bookkeeping files inside a skill folder; never compared or copied.
const MARKERS = new Set([".linked-from", ".nix-mirror", ".account-skill", ".skill-source"]);

type Source = { repo: string; ref?: string; dir?: string; skill?: string; path?: string; intervalDays?: number };
type Exact = { repo: string; ref?: string; path: string };
type Known = { exact: Record<string, Exact>; claims: Record<string, string>; misses: Record<string, number> };
type State = { checked?: Record<string, number>; seen?: Record<string, string>; lastRun?: string; [k: string]: unknown };

function parseArgs() {
  const out = { shared: "", manifest: "", locks: [] as string[], force: false };
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--shared") out.shared = argv[++i];
    else if (a === "--manifest") out.manifest = argv[++i];
    else if (a === "--lock") out.locks.push(argv[++i]);
    else if (a === "--force") out.force = true;
  }
  if (!out.shared) throw new Error("--shared is required");
  if (!out.manifest) out.manifest = join(out.shared, "_sync", "shared.json");
  return out;
}

const args = parseArgs();
const SYNC = join(args.shared, "_sync");
const SKILLS = join(args.shared, "skills");
const TMP = join(SYNC, "tmp");
const HISTORY = join(SYNC, "skill-history");
const LOG = join(SYNC, "skill-update.log");
const STATE = join(SYNC, "state", "skill-update.json");
const KNOWN = join(SYNC, "skill-sources.json");

function log(msg: string) {
  try { appendFileSync(LOG, `${new Date().toISOString().slice(0, 19)} ${msg}\n`); } catch {}
}

function readJson<T>(path: string, fallback: T): T {
  try { return JSON.parse(readFileSync(path, "utf8")) as T; } catch { return fallback; }
}

// Write to a temp file, then rename: a power cut leaves the old file or the new one, never half.
function writeJson(path: string, data: unknown) {
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, JSON.stringify(data, null, 2) + "\n");
  renameSync(tmp, path);
}

function stamp() { return new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19); }

function files(dir: string): string[] {
  const out: string[] = [];
  const walk = (d: string) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const p = join(d, e.name);
      if (e.isDirectory()) { if (e.name !== ".git") walk(p); }
      else if (!(d === dir && MARKERS.has(e.name))) out.push(relative(dir, p).split(sep).join("/"));
    }
  };
  walk(dir);
  return out.sort();
}

function hashDir(dir: string): string {
  const h = createHash("sha256");
  for (const rel of files(dir)) h.update(rel + "\0").update(readFileSync(join(dir, rel)));
  return h.digest("hex");
}

function frontmatterName(dir: string): string | null {
  try {
    const m = readFileSync(join(dir, "SKILL.md"), "utf8").match(/^---\r?\n([\s\S]*?)\r?\n---/);
    const n = m?.[1].match(/^name:\s*['"]?([^'"\r\n]+?)['"]?\s*$/m);
    return n ? n[1] : null;
  } catch { return null; }
}

// ── one run at a time, across processes and OSes ─────────────────────────
function acquireLock(): boolean {
  mkdirSync(TMP, { recursive: true });
  const lock = join(TMP, "skill-update.lock");
  try {
    if (Date.now() - statSync(lock).mtimeMs > LOCK_STALE_MS) unlinkSync(lock); // left by a crash
  } catch {}
  try { closeSync(openSync(lock, "wx")); return true; } catch { return false; }
}

function releaseLock() { try { unlinkSync(join(TMP, "skill-update.lock")); } catch {} }

// ── finish or roll back swaps a crash interrupted ────────────────────────
function recover() {
  for (const f of readdirSync(TMP)) {
    if (!f.startsWith("swap-") || !f.endsWith(".json")) continue;
    const j = readJson<{ name: string; stage: string; old: string } | null>(join(TMP, f), null);
    if (!j) { unlinkSync(join(TMP, f)); continue; }
    const live = join(SKILLS, j.name);
    if (!existsSync(live)) {
      if (existsSync(j.stage) && existsSync(join(j.stage, "SKILL.md"))) { renameSync(j.stage, live); log(`recovered: finished updating ${j.name}`); }
      else if (existsSync(j.old)) { renameSync(j.old, live); log(`recovered: rolled ${j.name} back to the previous version`); }
    }
    unlinkSync(join(TMP, f));
  }
  // Staging and download folders without a journal never touched a live skill.
  for (const f of readdirSync(TMP)) {
    if (f.startsWith("stage-") || f.startsWith("src-")) rmSync(join(TMP, f), { recursive: true, force: true });
  }
}

function swapIn(name: string, upstream: string, repo: string) {
  const live = join(SKILLS, name);
  const stage = join(TMP, `stage-${name}`);
  const old = join(HISTORY, name, stamp());
  rmSync(stage, { recursive: true, force: true });
  cpSync(upstream, stage, { recursive: true });
  // Upstream owns the skill now: drop .nix-mirror (Nix's copy) and
  // .linked-from (a local link copy would undo the update).
  if (existsSync(join(live, ".account-skill"))) cpSync(join(live, ".account-skill"), join(stage, ".account-skill"));
  writeFileSync(join(stage, ".skill-source"), repo + "\n");
  const journal = join(TMP, `swap-${name}.json`);
  writeJson(journal, { name, stage, old });
  mkdirSync(dirname(old), { recursive: true });
  renameSync(live, old);
  try {
    renameSync(stage, live);
  } catch (err) {
    renameSync(old, live); // e.g. a file in the new folder is locked on Windows
    throw err;
  } finally {
    try { unlinkSync(journal); } catch {}
  }
  const kept = readdirSync(dirname(old)).sort();
  for (const v of kept.slice(0, Math.max(0, kept.length - KEEP_HISTORY))) rmSync(join(dirname(old), v), { recursive: true, force: true });
}

// ── upstream downloads ───────────────────────────────────────────────────
async function latestSha(repo: string, ref?: string): Promise<string | null> {
  const res = await fetch(`https://api.github.com/repos/${repo}/commits/${ref || "HEAD"}`, {
    headers: { Accept: "application/vnd.github.sha", "User-Agent": "claude-shared-skill-update" },
    redirect: "follow",
  });
  return res.ok ? (await res.text()).trim() : null;
}

async function download(repo: string, sha: string): Promise<string> {
  const dest = join(TMP, `src-${repo.replace(/[^A-Za-z0-9._-]/g, "_")}`);
  rmSync(dest, { recursive: true, force: true });
  mkdirSync(dest, { recursive: true });
  const res = await fetch(`https://codeload.github.com/${repo}/tar.gz/${sha}`, { redirect: "follow" });
  if (!res.ok) throw new Error(`download ${repo}: HTTP ${res.status}`);
  const archive = `${dest}.tar.gz`;
  writeFileSync(archive, Buffer.from(await res.arrayBuffer()));
  // Windows 10+ ships bsdtar in System32. Not plain "tar" there: Git for
  // Windows' GNU tar reads "C:\\..." as a remote host.
  const tarBin = process.platform === "win32" ? join(process.env.SystemRoot ?? "C:\\Windows", "System32", "tar.exe") : "tar";
  const tar = spawnSync(tarBin, ["-xzf", archive, "-C", dest], { encoding: "utf8" });
  unlinkSync(archive);
  if (tar.status !== 0) throw new Error(`extract ${repo}: ${(tar.stderr || String(tar.error)).trim()}`);
  const [top] = readdirSync(dest);
  return join(dest, top);
}

// ── sources ──────────────────────────────────────────────────────────────
function githubRepo(entry: { source?: string; sourceType?: string; sourceUrl?: string }): string | null {
  const url = entry.sourceUrl?.match(/github\.com[/:]([^/]+\/[^/.]+?)(\.git)?\/?$/);
  if (url) return url[1];
  if (entry.sourceType === "github" && entry.source && /^[^/\s]+\/[^/\s]+$/.test(entry.source)) return entry.source;
  return null;
}

function collectSources(manifest: { skillSources?: Source[] }): { known: Known; bundles: Source[] } {
  const known = readJson<Known>(KNOWN, { exact: {}, claims: {}, misses: {} });
  known.exact ??= {};
  known.claims ??= {};
  known.misses ??= {};
  const bundles: Source[] = [];
  for (const s of manifest.skillSources ?? []) {
    if (!s.repo) continue; // e.g. a _comment entry
    if (s.skill && s.path) known.exact[s.skill] = { repo: s.repo, ref: s.ref, path: s.path };
    else bundles.push(s);
  }
  for (const lockPath of args.locks) {
    const lock = readJson<{ skills?: Record<string, any> }>(lockPath, {});
    for (const [name, entry] of Object.entries(lock.skills ?? {})) {
      const repo = githubRepo(entry);
      if (!repo || typeof entry.skillPath !== "string") continue;
      const dir = dirname(entry.skillPath);
      known.exact[name] = { repo, ref: entry.ref, path: dir === "." ? "" : dir };
    }
  }
  writeJson(KNOWN, known);
  return { known, bundles };
}

function isSkill(name: string): boolean {
  const dir = join(SKILLS, name);
  return !name.startsWith(".") && existsSync(join(dir, "SKILL.md")) && !existsSync(join(dir, ".account-skill"));
}

function updatable(name: string, known: Known): boolean {
  return isSkill(name) && (!existsSync(join(SKILLS, name, ".linked-from")) || !!known.exact[name]);
}

// ── discovery ────────────────────────────────────────────────────────────
function readSkillMd(dir: string): string {
  try { return readFileSync(join(dir, "SKILL.md"), "utf8").replace(/\r\n/g, "\n").trim(); } catch { return ""; }
}

function similarity(a: string, b: string): number {
  if (a === b) return 1;
  const la = new Set(a.split("\n").map((l) => l.trim()).filter(Boolean));
  const lb = new Set(b.split("\n").map((l) => l.trim()).filter(Boolean));
  let both = 0;
  for (const l of la) if (lb.has(l)) both++;
  return both / Math.max(1, la.size + lb.size - both);
}

function hintedRepos(dir: string): string[] {
  const fm = readSkillMd(dir).match(/^---\n([\s\S]*?)\n---/)?.[1] ?? "";
  const out: string[] = [];
  for (const m of fm.matchAll(/github\.com\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+?)(?:\.git)?(?=[\/\s"'#)]|$)/g)) out.push(m[1]);
  for (const m of fm.matchAll(/^source_repo:\s*['"]?([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)['"]?\s*$/gm)) out.push(m[1]);
  return out;
}

async function searchRepos(name: string): Promise<string[]> {
  try {
    const res = await fetch(`https://skills.sh/api/search?${new URLSearchParams({ q: name, limit: "10" })}`);
    if (!res.ok) return [];
    const body = (await res.json()) as { skills?: { source?: string; skillId?: string; name?: string; installs?: number }[] };
    return (body.skills ?? [])
      .filter((s) => s.source && (s.skillId === name || s.name === name))
      .sort((a, b) => (b.installs ?? 0) - (a.installs ?? 0))
      .map((s) => s.source!);
  } catch { return []; }
}

// Folders under root holding a SKILL.md for this skill name.
function findSkillDirs(root: string, name: string): string[] {
  const found: string[] = [];
  const walk = (d: string, depth: number) => {
    if (depth > 6) return;
    let entries;
    try { entries = readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (!e.isDirectory() || e.name === ".git" || e.name === "node_modules") continue;
      const p = join(d, e.name);
      if (existsSync(join(p, "SKILL.md")) && (e.name === name || frontmatterName(p) === name)) found.push(p);
      walk(p, depth + 1);
    }
  };
  if (existsSync(join(root, "SKILL.md")) && frontmatterName(root) === name) found.push(root);
  walk(root, 0);
  return found;
}

async function discover(known: Known, budget: { lookups: number; downloads: number }, roots: Map<string, string | null>) {
  const now = Date.now();
  const unknown = readdirSync(SKILLS).filter((n) => isSkill(n) && !known.exact[n] && !known.claims[n]
    && now - (known.misses[n] ?? 0) > MISS_DAYS * 864e5);
  for (const name of unknown) {
    if (budget.lookups <= 0) break;
    budget.lookups--;
    const mine = readSkillMd(join(SKILLS, name));
    const repos = [...new Set([...hintedRepos(join(SKILLS, name)), ...(await searchRepos(name))])].slice(0, 4);
    // Candidates in priority order (frontmatter links, then most installed):
    // take the first repo that has a close enough match, so an unmaintained
    // fork with an identical old copy never beats the real upstream.
    let best: { repo: string; path: string; score: number } | null = null;
    for (const repo of repos) {
      if (best && best.score >= MIN_SIMILARITY) break;
      if (!roots.has(repo)) {
        if (budget.downloads <= 0) continue;
        budget.downloads--;
        const sha = await latestSha(repo);
        try { roots.set(repo, sha ? await download(repo, sha) : null); } catch { roots.set(repo, null); }
      }
      const root = roots.get(repo);
      if (!root) continue;
      for (const dir of findSkillDirs(root, name)) {
        const score = similarity(mine, readSkillMd(dir));
        if (!best || score > best.score) best = { repo, path: relative(root, dir).split(sep).join("/"), score };
      }
    }
    if (best && best.score >= MIN_SIMILARITY) {
      known.exact[name] = { repo: best.repo, path: best.path };
      delete known.misses[name];
      log(`found source for ${name}: ${best.repo}/${best.path} (${Math.round(best.score * 100)}% match)`);
    } else {
      known.misses[name] = now;
    }
    writeJson(KNOWN, known);
  }
}

async function main() {
  if (!existsSync(SKILLS)) return;
  if (!acquireLock()) return;
  try {
    recover();
    const manifest = readJson<{ skillSources?: Source[] }>(args.manifest, {});
    const { known, bundles } = collectSources(manifest);
    const state = readJson<State>(STATE, {});
    state.checked ??= {};
    state.seen ??= {};
    const local = readdirSync(SKILLS).filter((n) => updatable(n, known));

    // Group every skill we can update by the repo (and ref) it comes from.
    const byRepo = new Map<string, { repo: string; ref?: string; intervalDays: number; exact: Map<string, string>; bundleDirs: string[] }>();
    const group = (repo: string, ref: string | undefined, intervalDays: number) => {
      const key = `${repo}@${ref ?? ""}`;
      if (!byRepo.has(key)) byRepo.set(key, { repo, ref, intervalDays, exact: new Map(), bundleDirs: [] });
      const g = byRepo.get(key)!;
      g.intervalDays = Math.min(g.intervalDays, intervalDays);
      return g;
    };
    for (const name of local) {
      const e = known.exact[name];
      if (e) group(e.repo, e.ref, DEFAULT_INTERVAL_DAYS).exact.set(name, e.path);
    }
    for (const b of bundles) group(b.repo, b.ref, b.intervalDays ?? DEFAULT_INTERVAL_DAYS).bundleDirs.push(b.dir ?? "skills");

    let updated = 0;
    for (const [key, g] of byRepo) {
      if (!args.force && Date.now() - (state.checked[key] ?? 0) < g.intervalDays * 864e5) continue;
      try {
        const sha = await latestSha(g.repo, g.ref);
        if (!sha) { log(`${g.repo}: could not reach GitHub; will retry next session`); continue; }
        // Same commit and same set of local skills as last time: nothing to do.
        const seen = `${sha} ${[...g.exact.keys()].sort().join(",")} ${local.length}`;
        if (state.seen[key] === seen && !args.force) { state.checked[key] = Date.now(); continue; }
        const root = await download(g.repo, sha);
        const candidates = new Map<string, string>(); // skill name -> upstream folder
        for (const [name, path] of g.exact) candidates.set(name, join(root, path));
        for (const dir of g.bundleDirs) {
          if (!existsSync(join(root, dir))) continue;
          for (const name of readdirSync(join(root, dir))) {
            if (candidates.has(name) || known.exact[name] || !local.includes(name)) continue;
            const up = join(root, dir, name);
            if (!existsSync(join(up, "SKILL.md"))) continue;
            // A bundle claims a local skill only if it is clearly the same one:
            // same frontmatter name and most of its files exist upstream.
            if (known.claims[name] !== g.repo) {
              const mine = files(join(SKILLS, name));
              const overlap = mine.filter((f) => existsSync(join(up, f))).length;
              if (frontmatterName(up) !== frontmatterName(join(SKILLS, name)) || overlap * 2 < mine.length) continue;
              known.claims[name] = g.repo;
            }
            candidates.set(name, up);
          }
        }
        for (const [name, up] of candidates) {
          // Never recreate a skill that isn't here (uninstalled, or never installed).
          if (!existsSync(join(SKILLS, name, "SKILL.md"))) continue;
          if (!existsSync(join(up, "SKILL.md"))) { log(`${name}: no longer found in ${g.repo}; kept as is`); continue; }
          if (hashDir(up) === hashDir(join(SKILLS, name))) continue;
          try { swapIn(name, up, g.repo); updated++; log(`updated ${name} from ${g.repo}@${sha.slice(0, 7)}`); }
          catch (err) { log(`${name}: update failed (${err}); kept the current version`); }
        }
        rmSync(dirname(root), { recursive: true, force: true });
        state.seen[key] = seen;
        state.checked[key] = Date.now();
        writeJson(KNOWN, known);
        writeJson(STATE, state); // after each repo, so a crash doesn't redo finished work
      } catch (err) {
        log(`${g.repo}: ${err}`);
      }
    }
    // Find upstreams for the rest; they are updated from the next run on.
    const roots = new Map<string, string | null>();
    try {
      await discover(known, { lookups: MAX_LOOKUPS, downloads: MAX_DOWNLOADS }, roots);
    } finally {
      for (const root of roots.values()) if (root) rmSync(dirname(root), { recursive: true, force: true });
    }
    state.lastRun = new Date().toISOString();
    writeJson(STATE, state);
    if (updated) log(`done: ${updated} skill(s) updated`);
  } finally {
    releaseLock();
  }
}

main().catch((err) => { log(`failed: ${err}`); releaseLock(); });
