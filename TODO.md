# FEKKA (Schkobba 40) — Master Implementation Plan

> **Strategy**: Phase 1 proves the engine. Phase 2 builds the house.  
> **Gate**: Python engine fully unit-tested before TypeScript port begins.

---

## PROJECT STRUCTURE

```
D:\Apps\Fakka\
├── TODO.md                        ← This file
├── Prompt.txt                     ← Phase 1 spec: Python CLI
├── Fekka_Multiplayer_App_Implementation_Prompt.txt  ← Phase 2 spec: NestJS + Flutter
├── fekka_cli\                     ← Phase 1: Python game engine
│   └── fekka.py
├── fekka_server\                  ← Phase 2: NestJS backend
│   └── (NestJS project)
└── fekka_app\                     ← Phase 2: Flutter frontend
    └── (Flutter project)
```

---

## ARCHITECTURAL SKETCH

**Phase 1** is a self‑contained Python 3.10+ script with deterministic seeding and `--auto` mode — the sole source of truth for rules, captured in pure functions and unit tests.  
**Phase 2** lifts the verified algorithms 1:1 into a framework‑agnostic `GameEngineService` (TypeScript), wraps it in NestJS with Redis (LIFO stacks via lists, room state hashes) + PostgreSQL (history), and exposes state via a namespaced Socket.IO gateway to a thin Flutter/Riverpod UI. Redis is the runtime authority; the engine is stateless pure logic — every `play_card` invokes `engine.processTurn(state, card)` and returns the new state diff.

---

## PHASE 1 — Python CLI Engine (Risk Reduction Gate)

### [ ] 1.1 — Data Model & Stack Primitives
**File**: `fekka_cli/fekka.py`  
- [ ] `Card` dataclass: `rank: str` (1-7, J, Q, K), `suit: str`, `point_value` property (face=2, numeral=1), `__eq__` by rank only
- [ ] `Deck`: build 40-card Italian deck (4 suits × 10 ranks), `shuffle(seed)`, `deal(n)`, `recycle(excluded_cards)` reshuffles non-excluded cards
- [ ] `PlayerStack`: LIFO list wrapper — `push`, `push_many`, `pop`, `peek_top → Card|None`, `steal_all → list`, `score → int`
- [ ] `MiddlePool`: extends PlayerStack — `sequential_reveal(rank) → list`: while loop `pool not empty and top.rank == rank: captured.append(pool.pop())`

### [ ] 1.2 — Player & GameManager
- [ ] `Player`: `name`, `hand: list[Card]`, `stack: PlayerStack`, `cumulative_score: int`, `eliminated: bool`, `rank_earned: int|None`
  - `play_card(index) → Card`, `add_captures(list[Card])`, `tally_score()`
- [ ] `GameManager`: `deck`, `pool: MiddlePool`, `players: list[Player]`, `active_players`, `current_player_index`, `next_rank`
  - `setup_round()`: deal 3 to each active player + 4 to pool; recycle deck if needed
  - `run_round()`: 12 plays × active_count
  - `process_turn(player, card)`: **THE CRITICAL METHOD**
    1. `captured = pool.sequential_reveal(card.rank)` (pool cascade)
    2. For each other active player: if `other.stack.peek_top().rank == card.rank` → `stolen.append(other.stack.steal_all())`
    3. If any captures: merge all into player's stack (pool cards + played card + stolen stacks in seat order)
    4. If zero captures: push played card onto pool (discard)
  - `score_round()`: each active player `tally_score()`, accumulate
  - `check_elimination()`: if `cumulative >= 51` → assign `rank_earned`, remove from active_players; if multiple, sort by score desc
  - Auto-assign final rank when 1 player remains

### [ ] 1.3 — CLI & Test Suite
- [ ] `argparse`: `--auto` flag, `--seed` for deterministic random, `--players 4`
- [ ] Manual mode: display pool top, each player's hand/stack top/score, prompt for card index
- [ ] Auto mode: random valid card selection, print each turn + round-end scores + final ranking
- [ ] `--test` mode runs unittest block: **12 deterministic scenarios**:
  1. Empty-pool discard
  2. Single pool capture
  3. 3-deep cascade
  4. Steal from one opponent
  5. Steal from two simultaneously
  6. Combined pool-cascade + steal
  7. Scoring: numerals = 1pt
  8. Scoring: face cards = 2pt
  9. Elimination at 51
  10. Rank assignment 1→4
  11. Redeal with pool persistence
  12. Seeded full 4-player game
- [ ] 100 `--auto` game smoke test: no exceptions, score monotonicity, deterministic with fixed seed

---

## PHASE 2 — Multiplayer Mobile App

### [ ] 2.1 — NestJS Scaffold + Engine Port
- [ ] `nest new fekka_server`, create `fekka` module
- [ ] `GameEngineService`: pure TypeScript, zero NestJS deps
  - Port `Card`, `Deck`, `MiddlePool`, `PlayerStack`, `executeTurn` 1:1 from Python
  - Jest unit tests mirroring all 12 Python scenarios → **GATE: all must pass**
- [ ] Configure Jest for the engine service

### [ ] 2.2 — Room System + Redis
- [ ] `RoomRedisRepository`: HSET for metadata, RPUSH/LRANGE for stacks/pool/deck, TTL for waiting rooms
- [ ] `GameRoomService`: create room (6-char code), join, start, state machine (waiting → in_progress → finished → expired)
- [ ] REST endpoints: `POST /games/create`, `POST /games/:roomId/join`, `POST /games/:roomId/start`
- [ ] PostgreSQL `MatchHistory` entity for archiving finished games

### [ ] 2.3 — Socket.IO Gateway
- [ ] `FekkaGateway`: namespace `game`, rooms per `roomId`
- [ ] Events:
  - **C→S**: `play_card { player_id, card }`, `rejoin { player_id, room_id }`
  - **S→C**: `state_update`, `capture_event`, `round_end`, `player_eliminated`, `game_over`, `error`
- [ ] Turn validation: reject out-of-turn plays via `WsException`
- [ ] Reconnection: `rejoin` → validate → full state sync from Redis
- [ ] Per-room Redis lock (`SETNX`) during `executeTurn` to prevent race conditions
- [ ] `RedisIoAdapter` for multi-instance support

### [ ] 2.4 — Flutter App
- [ ] `flutter create fekka_app`, add `riverpod` + `socket_io_client` + `share_plus`
- [ ] `GameNotifier` (Riverpod `StateNotifier`): manages socket connection, deserializes events, exposes reactive state
- [ ] 6 Screens:
  - **Home** — "Create Game" / "Join Game" buttons
  - **Lobby** — room code display, live player list, "Share Invite" (`share_plus`), admin "Start" button
  - **Join** — deep-link pre-fill or manual code entry, name input
  - **GameTable** — 4-position layout, hand cards (own only), pool top, opponent stack tops + hand counts, turn highlight
  - **ScoreSummary** — per-round points + running totals, auto-advance
  - **GameOver** — final 1-4 rankings

### [ ] 2.5 — Animations & Deep Links & Fallback
- [ ] Flutter animations: card-play slide, sequential reveal cascade (staggered pop), stack-steal fly-over, round-end popup
- [ ] Android App Links: `assetlinks.json` at `/.well-known/`
- [ ] iOS Universal Links: `apple-app-site-association` at `/.well-known/`
- [ ] NestJS fallback page: `GET /join/:roomId` → static "Get Fekka" page with store links
- [ ] E2E test: 4 emulators/instances, create→invite→join→play full game→game over

---

## PITFALLS & MITIGATIONS

| Pitfall | Mitigation |
|---|---|
| **Sequential-reveal off-by-one** | `while pool and pool[-1].rank == played_rank:` — check BEFORE pop |
| **Steal order non-determinism** | Canonical order: seat index ascending. Test with fixed seed. |
| **Redis/engine state divergence on reconnect** | On `rejoin`, recompute full sanitized snapshot from Redis, push before accepting moves |
| **Socket.IO room fan-out race** | Per-room Redis lock (`SETNX`) during `executeTurn` |
| **Deck exhaustion mid-redeal** | `Deck.recycle()` excludes all player.stack cards, includes pool + deck remainder |
| **Multiple players ≥51 same round** | Sort by score desc, tiebreak by seat order |
| **Self-steal** | `process_turn` skips `player == other` |
| **No Redis adapter → single-instance only** | Always use `RedisIoAdapter` |
| **Socket `handshake.auth` lost on reconnect** | Use manual `rejoin` event with auth token, not handshake |
| **Game logic in gateway** | Gateway = transport only. All logic in `GameService` + `GameEngineService` |
| **Cross-room data leak** | Always `server.to(roomId).emit(...)`, never bare `server.emit` |
| **Redis memory leak** | TTL on all room keys, refresh on activity |

---

## TESTING STRATEGY

| Phase | What | How |
|---|---|---|
| **1 — Unit** | All 12 game scenarios | `python fekka.py --test` (unittest) |
| **1 — Smoke** | 100 auto games | `python fekka.py --auto --games 100` — assert no exceptions, score monotonic |
| **2 — Engine** | Jest mirrors all 12 Python scenarios | `npm test` in `fekka_server` |
| **2 — Integration** | 4 scripted socket clients vs NestJS + Redis | Docker Compose, assert final scores match seeded Python |
| **2 — Widget** | Each Flutter screen | Mock `GameNotifier`, verify rendered state |
| **2 — E2E** | Full game on 4 emulators | Create → invite → join → play → game over |

---

## GATE CHECKLIST

- [ ] All 12 Python unit tests pass
- [ ] 100-game `--auto` smoke test: 0 exceptions
- [ ] All 12 Jest unit tests pass (TypeScript port)
- [ ] Postman/curl: create room, 3 joins, start → 200 OK
- [ ] 4 socket clients play scripted game → final scores match Python output
- [ ] Flutter deep link opens Join screen with pre-filled room code
- [ ] Share button opens native share sheet with invite link
- [ ] 4-emulator E2E: full game completes with correct rankings
