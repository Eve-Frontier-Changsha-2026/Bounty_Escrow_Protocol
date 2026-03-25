# E2E Manual Test — v7 Encrypted Bounty Details

Testnet: `V7_PACKAGE_ID = 0xc27986d5da78ffda924f420e2e22381a2a5dc45c67f4ec28b6da3407e2dadded`
Dev server: `npm run dev` → http://localhost:5173/

## Pre-check
- [ ] `npm run build` passes (0 errors)
- [ ] `sui move test` passes (265 tests)
- [ ] Wallet connected (testnet, has SUI balance)

---

## Test 1: Dashboard — Task Type Badges

| # | Step | Expected |
|---|------|----------|
| 1.1 | Open http://localhost:5173/ | Dashboard loads, "BOUNTY BOARD" title |
| 1.2 | Check pre-v5 bounty cards | No task type badge next to title (graceful null) |
| 1.3 | After Test 2 completes, refresh dashboard | New bounty shows TaskTypeBadge (e.g. `KILL`) next to title |
| 1.4 | Click status filter tabs (ALL/OPEN/CLAIMED) | Filters work, badges remain visible |
| 1.5 | Type in search box | Search filters correctly, badges stay |

---

## Test 2: Create Bounty — Task Type + Encrypted Details

| # | Step | Expected |
|---|------|----------|
| 2.1 | Click "CREATE" in nav | Create page loads |
| 2.2 | Fill title, description, reward, stake, deadline | Form accepts input |
| 2.3 | Select task type: KILL | Kill criteria fields appear (target name, min kills, solar system) |
| 2.4 | Fill kill criteria fields | Fields accept input |
| 2.5 | Toggle "Encrypt Details" ON | Textarea for encrypted content appears |
| 2.6 | Type secret intel in textarea | Text accepted, char count shown |
| 2.7 | Click "Create Bounty" | TX1 fires: create_bounty_owned + set_task_type + set_kill_criteria + share_bounty |
| 2.8 | Wait for TX1 success | Progress shows "Encrypting..." |
| 2.9 | TX2 auto-fires: Seal encrypt + set_encrypted_details | Success toast + redirect to detail page |
| 2.10 | Repeat with DELIVERY task type | Delivery criteria fields (item name, quantity, target assembly) |
| 2.11 | Repeat with BUILD task type | Build criteria fields (blueprint, target assembly, verification mode) |
| 2.12 | Repeat with INTEL task type | Intel criteria fields (topic, min length) |

---

## Test 3: BountyDetail — Task Type Panel + Decrypt Flow

| # | Step | Expected |
|---|------|----------|
| 3.1 | Open detail page of bounty created in Test 2 | Page loads with all panels |
| 3.2 | Check header | TaskTypeBadge (e.g. `KILL`) next to bounty title |
| 3.3 | Check "TASK TYPE" panel | Shows: task type, verification mode, criteria fields |
| 3.4 | Check "ENCRYPTED DETAILS" panel (as creator) | Shows backup key message or "You encrypted this bounty" |
| 3.5 | Switch to hunter wallet | Connect different wallet |
| 3.6 | Click "Mint Viewer Receipt" | TX mints BountyViewerReceipt, success toast |
| 3.7 | Click "Decrypt" | Seal session key flow → signPersonalMessage → decrypted plaintext displayed |
| 3.8 | Check decrypted content | Matches what was typed in Test 2.6 |

---

## Test 4: Edge Cases

| # | Step | Expected |
|---|------|----------|
| 4.1 | Create bounty with CUSTOM type (no criteria) | No criteria fields, bounty created successfully |
| 4.2 | Create bounty WITHOUT encryption | No encrypted details panel on detail page |
| 4.3 | View pre-v5 bounty detail page | No task type panel, no encrypted details panel |
| 4.4 | Try decrypt without minting receipt | Button disabled or error message |
| 4.5 | Refresh detail page after decrypt | Receipt persists, can decrypt again (session key cached) |

---

## Test 5: Full Bounty Lifecycle (v5+v7)

| # | Step | Expected |
|---|------|----------|
| 5.1 | Create KILL bounty with encryption | Success |
| 5.2 | Hunter claims bounty (stake SUI) | Claim succeeds, status → CLAIMED |
| 5.3 | Hunter mints viewer receipt + decrypts | Sees encrypted details |
| 5.4 | Hunter submits proof | Proof submitted |
| 5.5 | Creator/verifier approves proof | Status → COMPLETED, hunter gets reward |
| 5.6 | Verify dashboard shows completed bounty with KILL badge | Badge + COMPLETED status |

---

## Results

| Test | Pass/Fail | Notes |
|------|-----------|-------|
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |
