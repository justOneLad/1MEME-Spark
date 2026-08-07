#!/usr/bin/env node
/**
 * compile.js — Spark Launchpad Contracts
 *
 * Uses the solc Node API with viaIR:true (required — contracts exceed the
 * EVM's 16-slot stack limit under legacy codegen).
 *
 * Resolves imports via a findImportCallback: `@openzeppelin/...` imports read
 * from node_modules/@openzeppelin/...; everything else is read relative to
 * the repo root (plain relative imports like "../common/SparkRouting.sol"
 * need no extra configuration — solc normalizes them against the importing
 * file's own path before calling the callback).
 *
 * Outputs: out/<Contract>.abi  and  out/<Contract>.bin  — one pair per
 * contract encountered anywhere in the compilation graph, not just the entry
 * files below (so common/SparkRouting.sol, e.g., also gets emitted).
 *
 * Usage:
 *   node compile.js            — compile all contracts
 *   node compile.js --verbose  — show warnings too
 */

'use strict';

const solc = require('solc');
const fs   = require('fs');
const path = require('path');

const VERBOSE = process.argv.includes('--verbose');
const OUT_DIR = path.join(__dirname, 'out');
const NODE_MODULES = path.join(__dirname, 'node_modules');

// ── Entry-point source files to compile ─────────────────────────────────────
const ENTRY_FILES = [
  'spark/SparkToken.sol',
  'spark/SparkLocker.sol',
  'spark/SparkLauncherUpgradeable.sol',
  'spark-go/SparkGoLauncher.sol',
  'spark-go/SparkGoBurner.sol',
  'spark-go/hooks/SparkGoHookV4.sol',
  'spark-go/hooks/SparkGoHookInfinity.sol',
  'distributor/MultiSender.sol',
  'distributor/MerkleDistributor.sol',
];

// ── Build source map (entry files only — imports resolved lazily below) ────
const sources = {};
let missing = false;
for (const f of ENTRY_FILES) {
  const abs = path.join(__dirname, f);
  if (!fs.existsSync(abs)) {
    console.error('✗ Missing:', f);
    missing = true;
  } else {
    sources[f] = { content: fs.readFileSync(abs, 'utf8') };
  }
}
if (missing) process.exit(1);

// ── Import resolution ────────────────────────────────────────────────────────
function findImports(importPath) {
  const abs = importPath.startsWith('@openzeppelin/')
    ? path.join(NODE_MODULES, importPath)
    : path.join(__dirname, importPath);
  try {
    return { contents: fs.readFileSync(abs, 'utf8') };
  } catch {
    return { error: `File not found: ${importPath}` };
  }
}

// ── Compiler input ───────────────────────────────────────────────────────────
const compilerInput = JSON.stringify({
  language: 'Solidity',
  sources,
  settings: {
    optimizer: { enabled: true, runs: 200 },
    viaIR: true,
    outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object'] } },
  },
});

// ── Compile ──────────────────────────────────────────────────────────────────
console.log('Compiling with solc', solc.version(), '(viaIR: true, optimizer: 200 runs)…');
const output = JSON.parse(solc.compile(compilerInput, { import: findImports }));

// ── Report errors / warnings ─────────────────────────────────────────────────
const errors   = (output.errors || []).filter(e => e.severity === 'error');
const warnings = (output.errors || []).filter(e => e.severity === 'warning');

if (errors.length) {
  console.error('\n── Errors (' + errors.length + ') ──────────────────────────────────────');
  errors.forEach(e => console.error(e.formattedMessage || e.message));
  process.exit(1);
}

if (VERBOSE && warnings.length) {
  console.warn('\n── Warnings (' + warnings.length + ') ────────────────────────────────────');
  warnings.forEach(w => console.warn(w.formattedMessage || w.message));
}

// ── Write artifacts ──────────────────────────────────────────────────────────
// Contract/interface names aren't unique across files (e.g. ISwapRouter is
// declared in multiple sources) — Foundry disambiguates by keying on
// {path}:{name}, but a flat out/<Name>.abi namespace can't. Pre-scan for
// collisions; only the colliding names get qualified with their source
// file's basename, so the common case still gets plain out/<Name>.abi files.
fs.mkdirSync(OUT_DIR, { recursive: true });

const sourcesByName = {};
for (const file of Object.keys(output.contracts || {})) {
  for (const name of Object.keys(output.contracts[file])) {
    (sourcesByName[name] ||= []).push(file);
  }
}

let count = 0;
for (const file of Object.keys(output.contracts || {})) {
  const contracts = output.contracts[file];
  for (const [name, artifact] of Object.entries(contracts)) {
    const colliding = sourcesByName[name].length > 1;
    const base = colliding ? `${path.basename(file, '.sol')}.${name}` : name;
    if (colliding) console.warn(`⚠ ${name} defined in multiple files — writing as ${base}.abi/.bin`);
    fs.writeFileSync(path.join(OUT_DIR, `${base}.abi`), JSON.stringify(artifact.abi, null, 2));
    fs.writeFileSync(path.join(OUT_DIR, `${base}.bin`), artifact.evm.bytecode.object);
    count++;
  }
}

console.log(`✓ Compiled ${count} contract(s) → out/`);
