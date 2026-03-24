/**
 * Generate Ed25519 test vectors for oracle attestation tests.
 *
 * Usage:
 *   node scripts/gen_test_vectors.mjs delivery <bounty_id_hex>
 *   node scripts/gen_test_vectors.mjs build <bounty_id_hex> <assembly_id_hex>
 *
 * Outputs Move-compatible hex constants for:
 *   - ORACLE_PUBKEY (32 bytes)
 *   - ATTESTATION_MSG (BCS-encoded)
 *   - ATTESTATION_SIG (64 bytes Ed25519 signature)
 */

import * as ed25519 from '@noble/ed25519';
import { sha512 } from '@noble/hashes/sha2.js';
import { keccak_256 } from '@noble/hashes/sha3.js';
import { bytesToHex } from '@noble/hashes/utils.js';

// @noble/ed25519 v2 requires explicit sha512 config
ed25519.hashes.sha512 = (...m) => sha512(ed25519.etc.concatBytes(...m));

// Deterministic keypair from known seed (32 bytes)
const SEED = new Uint8Array(32);
SEED[0] = 0x42; // deterministic, reproducible

const privKey = SEED;
const pubKey = ed25519.getPublicKey(privKey);

// --- BCS helpers ---
function bcsAddress(hexStr) {
  // address = 32 raw bytes (no length prefix in BCS for fixed-size)
  const clean = hexStr.replace(/^0x/, '').padStart(64, '0');
  return Buffer.from(clean, 'hex');
}

function bcsU64(value) {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64LE(BigInt(value));
  return buf;
}

// --- Attestation encoders ---
function encodeDeliveryAttestation({ bountyId, hunter, itemTypeId, quantity, assemblyId, timestamp, nonce }) {
  return Buffer.concat([
    bcsAddress(bountyId),
    bcsAddress(hunter),
    bcsU64(itemTypeId),
    bcsU64(quantity),
    bcsAddress(assemblyId),
    bcsU64(timestamp),
    bcsU64(nonce),
  ]);
}

function encodeBuildAttestation({ bountyId, hunter, assemblyTypeId, solarSystemId, assemblyId, timestamp, nonce }) {
  return Buffer.concat([
    bcsAddress(bountyId),
    bcsAddress(hunter),
    bcsU64(assemblyTypeId),
    bcsU64(solarSystemId),
    bcsAddress(assemblyId),
    bcsU64(timestamp),
    bcsU64(nonce),
  ]);
}

async function signMessage(message) {
  const msgHash = keccak_256(message);
  const signature = ed25519.sign(msgHash, privKey);
  return { msgHash, signature };
}

function toMoveHex(buf) {
  return 'x"' + bytesToHex(buf instanceof Uint8Array ? buf : new Uint8Array(buf)) + '"';
}

// --- Main ---
const mode = process.argv[2];
const bountyId = process.argv[3];

if (!mode || !bountyId) {
  console.error('Usage: node gen_test_vectors.mjs <delivery|build> <bounty_id_hex> [assembly_id_hex]');
  process.exit(1);
}

console.log(`// === Ed25519 Test Vectors (${mode.toUpperCase()}) ===`);
console.log(`// Seed: 0x42 + 31 zero bytes`);
console.log(`const ORACLE_PUBKEY: vector<u8> = ${toMoveHex(pubKey)};`);
console.log();

if (mode === 'delivery') {
  const hunter = '0xBB';           // matches HUNTER in test
  const itemTypeId = 100;          // matches criteria
  const quantity = 10;             // matches min_quantity
  const assemblyId = '0x0';        // @0x0 = any
  const timestamp = 1_000_000_000;
  const nonce = 1;

  const msg = encodeDeliveryAttestation({
    bountyId, hunter, itemTypeId, quantity, assemblyId, timestamp, nonce,
  });

  const { signature } = await signMessage(msg);

  console.log('// --- Happy path (matching criteria) ---');
  console.log(`const DELIVERY_MSG: vector<u8> = ${toMoveHex(msg)};`);
  console.log(`const DELIVERY_SIG: vector<u8> = ${toMoveHex(signature)};`);
  console.log(`// nonce=1, item_type_id=100, quantity=10, assembly=@0x0`);
  console.log();

  // --- Mismatch vectors ---
  // Wrong bounty_id
  const wrongBountyMsg = encodeDeliveryAttestation({
    bountyId: '0xDEAD', hunter, itemTypeId, quantity, assemblyId, timestamp, nonce: 2,
  });
  const { signature: wrongBountySig } = await signMessage(wrongBountyMsg);
  console.log('// --- Wrong bounty_id ---');
  console.log(`const DELIVERY_WRONG_BOUNTY_MSG: vector<u8> = ${toMoveHex(wrongBountyMsg)};`);
  console.log(`const DELIVERY_WRONG_BOUNTY_SIG: vector<u8> = ${toMoveHex(wrongBountySig)};`);
  console.log();

  // Wrong hunter
  const wrongHunterMsg = encodeDeliveryAttestation({
    bountyId, hunter: '0xEE', itemTypeId, quantity, assemblyId, timestamp, nonce: 3,
  });
  const { signature: wrongHunterSig } = await signMessage(wrongHunterMsg);
  console.log('// --- Wrong hunter ---');
  console.log(`const DELIVERY_WRONG_HUNTER_MSG: vector<u8> = ${toMoveHex(wrongHunterMsg)};`);
  console.log(`const DELIVERY_WRONG_HUNTER_SIG: vector<u8> = ${toMoveHex(wrongHunterSig)};`);
  console.log();

  // Wrong item_type_id (999 instead of 100)
  const wrongItemMsg = encodeDeliveryAttestation({
    bountyId, hunter, itemTypeId: 999, quantity, assemblyId, timestamp, nonce: 4,
  });
  const { signature: wrongItemSig } = await signMessage(wrongItemMsg);
  console.log('// --- Wrong item_type_id ---');
  console.log(`const DELIVERY_WRONG_ITEM_MSG: vector<u8> = ${toMoveHex(wrongItemMsg)};`);
  console.log(`const DELIVERY_WRONG_ITEM_SIG: vector<u8> = ${toMoveHex(wrongItemSig)};`);
  console.log();

  // Insufficient quantity (5 < 10)
  const lowQtyMsg = encodeDeliveryAttestation({
    bountyId, hunter, itemTypeId, quantity: 5, assemblyId, timestamp, nonce: 5,
  });
  const { signature: lowQtySig } = await signMessage(lowQtyMsg);
  console.log('// --- Insufficient quantity ---');
  console.log(`const DELIVERY_LOW_QTY_MSG: vector<u8> = ${toMoveHex(lowQtyMsg)};`);
  console.log(`const DELIVERY_LOW_QTY_SIG: vector<u8> = ${toMoveHex(lowQtySig)};`);
  console.log();

  // Nonce replay (same nonce=1 as happy path, different timestamp)
  const replayMsg = encodeDeliveryAttestation({
    bountyId, hunter, itemTypeId, quantity, assemblyId, timestamp: 2_000_000_000, nonce: 1,
  });
  const { signature: replaySig } = await signMessage(replayMsg);
  console.log('// --- Nonce replay (nonce=1 again) ---');
  console.log(`const DELIVERY_REPLAY_MSG: vector<u8> = ${toMoveHex(replayMsg)};`);
  console.log(`const DELIVERY_REPLAY_SIG: vector<u8> = ${toMoveHex(replaySig)};`);

  // Target assembly mismatch (for when criteria has specific target)
  // We'll generate a separate set where criteria target = @0xAA but attestation has @0xBB
  const wrongTargetMsg = encodeDeliveryAttestation({
    bountyId, hunter, itemTypeId, quantity, assemblyId: '0xBB', timestamp, nonce: 6,
  });
  const { signature: wrongTargetSig } = await signMessage(wrongTargetMsg);
  console.log();
  console.log('// --- Target assembly mismatch (attestation=@0xBB, criteria=@0xAA) ---');
  console.log(`const DELIVERY_WRONG_TARGET_MSG: vector<u8> = ${toMoveHex(wrongTargetMsg)};`);
  console.log(`const DELIVERY_WRONG_TARGET_SIG: vector<u8> = ${toMoveHex(wrongTargetSig)};`);

} else if (mode === 'build') {
  const assemblyId = process.argv[4];
  if (!assemblyId) {
    console.error('Build mode requires assembly_id_hex as 4th arg');
    process.exit(1);
  }

  const hunter = '0xBB';
  const assemblyTypeId = 8888;     // matches ASSEMBLY_TYPE_ID
  const solarSystemId = 0;         // 0 = any (criteria solar=0)
  const timestamp = 1_000_000_000;
  const nonce = 1;

  const msg = encodeBuildAttestation({
    bountyId, hunter, assemblyTypeId, solarSystemId, assemblyId, timestamp, nonce,
  });
  const { signature } = await signMessage(msg);

  console.log('// --- Happy path (matching criteria) ---');
  console.log(`const BUILD_MSG: vector<u8> = ${toMoveHex(msg)};`);
  console.log(`const BUILD_SIG: vector<u8> = ${toMoveHex(signature)};`);
  console.log(`// nonce=1, assembly_type_id=8888, solar=0`);
  console.log();

  // Wrong bounty_id
  const wrongBountyMsg = encodeBuildAttestation({
    bountyId: '0xDEAD', hunter, assemblyTypeId, solarSystemId, assemblyId, timestamp, nonce: 2,
  });
  const { signature: wrongBountySig } = await signMessage(wrongBountyMsg);
  console.log('// --- Wrong bounty_id ---');
  console.log(`const BUILD_WRONG_BOUNTY_MSG: vector<u8> = ${toMoveHex(wrongBountyMsg)};`);
  console.log(`const BUILD_WRONG_BOUNTY_SIG: vector<u8> = ${toMoveHex(wrongBountySig)};`);
  console.log();

  // Wrong hunter
  const wrongHunterMsg = encodeBuildAttestation({
    bountyId, hunter: '0xEE', assemblyTypeId, solarSystemId, assemblyId, timestamp, nonce: 3,
  });
  const { signature: wrongHunterSig } = await signMessage(wrongHunterMsg);
  console.log('// --- Wrong hunter ---');
  console.log(`const BUILD_WRONG_HUNTER_MSG: vector<u8> = ${toMoveHex(wrongHunterMsg)};`);
  console.log(`const BUILD_WRONG_HUNTER_SIG: vector<u8> = ${toMoveHex(wrongHunterSig)};`);
  console.log();

  // Wrong assembly_id
  const wrongAssemblyMsg = encodeBuildAttestation({
    bountyId, hunter, assemblyTypeId, solarSystemId, assemblyId: '0xDEAD', timestamp, nonce: 4,
  });
  const { signature: wrongAssemblySig } = await signMessage(wrongAssemblyMsg);
  console.log('// --- Wrong assembly_id ---');
  console.log(`const BUILD_WRONG_ASSEMBLY_MSG: vector<u8> = ${toMoveHex(wrongAssemblyMsg)};`);
  console.log(`const BUILD_WRONG_ASSEMBLY_SIG: vector<u8> = ${toMoveHex(wrongAssemblySig)};`);
  console.log();

  // Wrong type_id (9999 instead of 8888)
  const wrongTypeMsg = encodeBuildAttestation({
    bountyId, hunter, assemblyTypeId: 9999, solarSystemId, assemblyId, timestamp, nonce: 5,
  });
  const { signature: wrongTypeSig } = await signMessage(wrongTypeMsg);
  console.log('// --- Wrong assembly_type_id ---');
  console.log(`const BUILD_WRONG_TYPE_MSG: vector<u8> = ${toMoveHex(wrongTypeMsg)};`);
  console.log(`const BUILD_WRONG_TYPE_SIG: vector<u8> = ${toMoveHex(wrongTypeSig)};`);
  console.log();

  // Solar system mismatch (attestation solar=99, criteria solar=42)
  const wrongSolarMsg = encodeBuildAttestation({
    bountyId, hunter, assemblyTypeId, solarSystemId: 99, assemblyId, timestamp, nonce: 6,
  });
  const { signature: wrongSolarSig } = await signMessage(wrongSolarMsg);
  console.log('// --- Solar system mismatch (att=99, criteria=42) ---');
  console.log(`const BUILD_WRONG_SOLAR_MSG: vector<u8> = ${toMoveHex(wrongSolarMsg)};`);
  console.log(`const BUILD_WRONG_SOLAR_SIG: vector<u8> = ${toMoveHex(wrongSolarSig)};`);
  console.log();

  // Nonce replay
  const replayMsg = encodeBuildAttestation({
    bountyId, hunter, assemblyTypeId, solarSystemId, assemblyId, timestamp: 2_000_000_000, nonce: 1,
  });
  const { signature: replaySig } = await signMessage(replayMsg);
  console.log('// --- Nonce replay (nonce=1 again) ---');
  console.log(`const BUILD_REPLAY_MSG: vector<u8> = ${toMoveHex(replayMsg)};`);
  console.log(`const BUILD_REPLAY_SIG: vector<u8> = ${toMoveHex(replaySig)};`);
}

console.log();
console.log('// Done.');
