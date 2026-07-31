#!/usr/bin/env node
/**
 * compile.js — Spark Launchpad Contracts
 *
 * Uses the solc Node API with viaIR:true (required — contracts exceed the
 * EVM's 16-slot stack limit under legacy codegen).
 *
 * Outputs: out/<Contract>.abi  and  out/<Contract>.bin
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

// ── Source files to compile ──────────────────────────────────────────────────
const CONTRACT_FILES = [
  'spark/SparkToken.sol',
  'spark/SparkLauncher.sol',
  'spark/SparkLocker.sol',
  'spark-v2/SparkLauncherV2.sol',
  'spark-v2/SparkBurner.sol',
  'spark-v2/hooks/SparkHookV4.sol',
  'spark-v2/hooks/SparkHookInfinity.sol',
];

// ── Build source map ─────────────────────────────────────────────────────────
const sources = {};
let missing = false;
for (const f of CONTRACT_FILES) {
  const abs = path.join(__dirname, f);
  if (!fs.existsSync(abs)) {
    console.error('✗ Missing:', f);
    missing = true;
  } else {
    sources[f] = { content: fs.readFileSync(abs, 'utf8') };
  }
}
if (missing) process.exit(1);

// ── Compiler input ───────────────────────────────────────────────────────────
const outputSelection = {};
for (const f of CONTRACT_FILES) {
  outputSelection[f] = { '*': ['abi', 'evm.bytecode.object'] };
}

const compilerInput = JSON.stringify({
  language: 'Solidity',
  sources,
  settings: {
    optimizer: { enabled: true, runs: 200 },
    viaIR: true,
    outputSelection,
  },
});

// ── Compile ──────────────────────────────────────────────────────────────────
console.log('Compiling with solc', solc.version(), '(viaIR: true, optimizer: 200 runs)…');
const output = JSON.parse(solc.compile(compilerInput));

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
fs.mkdirSync(OUT_DIR, { recursive: true });

let count = 0;
for (const file of CONTRACT_FILES) {
  const contracts = output.contracts[file] || {};
  for (const [name, artifact] of Object.entries(contracts)) {
    fs.writeFileSync(path.join(OUT_DIR, `${name}.abi`), JSON.stringify(artifact.abi, null, 2));
    fs.writeFileSync(path.join(OUT_DIR, `${name}.bin`), artifact.evm.bytecode.object);
    count++;
  }
}

console.log(`✓ Compiled ${count} contract(s) → out/`);
