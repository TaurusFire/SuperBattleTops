# Beyblade Simulation — Design Document

## Goal

Produce short-form content (TikTok-style) of Beyblade-style battles that are
**reliably watchable** every run. The previous physics-driven simulation was
unpredictable and required heavy tuning to produce a good clip; this design
inverts the approach by **scripting movement and using formula-driven
collisions**, with physics only used where it adds genuine visual value.

---

## Design Philosophy

| Concern | Old approach | New approach |
|---|---|---|
| Movement | Emergent from forces | Scripted patterns, RPM-modulated |
| Collisions | Physics impulses + corrective forces | Stat-driven knockback formula |
| Outcomes | Unpredictable per run | Deterministic given stat profiles |
| Tuning | Many interacting parameters | One stat = one effect |
| Drama | By luck | By design |
| Edge cases | Many (wall-hug, rattleback, stuck states) | Eliminated by construction |

**Physics is kept only for the final dying phase**, where emergent wobble and
topple sells the loss in a way scripted animation cannot match.

---

## Per-Top Stats

Each top type is defined by a small set of stats. These plug into formulas that
determine collision outcomes and movement behaviour.

| Stat | Purpose | Typical range |
|---|---|---|
| `base_knockback` | How hard this top hits opponents in a collision | 30 — 100 |
| `defence` | Resistance to incoming knockback | 10 — 60 |
| `damage` | How much RPM the opponent loses per clash | 5 — 30 |
| `mass` | Used in knockback distribution (heavier = pushed less) | 0.05 — 0.20 |
| `starting_rpm` | RPM at launch | 4000 — 6000 |
| `rpm_decay_rate` | How fast RPM bleeds off over time (per second) | 5 — 50 |
| `movement_pattern` | Which scripted pattern this top follows | (enum) |
| `pattern_scale` | Size of the pattern (radius for circles, etc.) | 30 — 120 mm |
| `pattern_speed` | Base movement speed along the pattern | 30 — 150 mm/s |
| `ability` | Optional — special mechanic (see Abilities section) | (enum or null) |

### Stat budget — abilities vs raw stats

Each top has a **stat budget** that's spent on either an ability or improved
base stats. A top without an ability gets a meaningful bonus across its
combat stats (roughly +20% on whichever of `base_knockback`, `defence`,
`damage`, or `starting_rpm` suits its role), making "ability or no" a real
design choice rather than a free upgrade.

This trade-off is what makes ability picks meaningful for content variety:
viewers can see "the kamikaze top vs the no-ability brawler" as two distinct
fighters rather than one having an objective advantage.

### Type archetypes (starting points, no ability)

These are tops with **no ability** — full stat budget spent on raw numbers.
Tops with abilities would have somewhat weaker versions of these.

| | Attack | Defence | Stamina |
|---|---|---|---|
| `base_knockback` | 80 | 40 | 30 |
| `defence` | 15 | 60 | 30 |
| `damage` | 25 | 15 | 8 |
| `mass` | 0.06 | 0.18 | 0.08 |
| `starting_rpm` | 6000 | 4500 | 5000 |
| `rpm_decay_rate` | 40 | 25 | 8 |
| `movement_pattern` | aggressive_seek | tight_orbit | wide_spiral |
| `pattern_scale` | 80 | 40 | 100 |
| `pattern_speed` | 130 | 50 | 70 |

These are starting values to iterate on. The goal is for each type to **feel
distinct** in how it moves and how matchups resolve.

---

## Movement: What's Scripted

Each top follows a **movement pattern** that defines a target position relative
to the arena centre at each moment in time. The top steers toward this target
each frame with a steering force that scales with RPM (low-RPM tops can't keep
up with the pattern, which produces natural-looking drift).

### Pattern types

- **`circle`** — orbits the centre at a fixed radius
- **`tight_orbit`** — small circle near the centre, used by defence types
- **`figure_eight`** — traces a figure-eight, ideal for stamina types
- **`wide_spiral`** — slowly varying radius, lazy graceful motion
- **`aggressive_seek`** — chases the opponent's recent position with delay
- **`zigzag`** — sharp directional changes, used by aggressive attackers

Each pattern is a function `(time, rpm_ratio) -> Vector2` returning a target
horizontal position. The Y axis is handled by gravity + bowl curve normally.

### RPM modulation

Pattern behaviour scales with RPM:

- **Pattern speed** scales with `rpm_ratio` — slower top traces the pattern
  slower
- **Pattern scale** can shrink at low RPM — dying tops draw smaller circles
- **Steering responsiveness** scales with `rpm_ratio` — low-RPM tops can't
  keep up with the pattern's target position, lagging behind it visibly

This produces the visual identity of each type while still letting RPM be the
core resource that drives the match's arc.

### Randomisation

Patterns include subtle randomisation to prevent the motion looking
mechanical:

- Small per-frame jitter on the target position (~3-5mm)
- Occasional "pattern breaks" — for 0.3-0.5s the top ignores the pattern and
  drifts freely, then reacquires
- Mild random rotation of the pattern's phase angle on spawn

---

## Collisions: The Formula

Collisions are detected by **proximity**, not physics contacts (which proved
unreliable). When two tops come within `collision_threshold`, a one-shot
exchange occurs:

```
applied_knockback = (
    attacker.base_knockback × attacker.rpm_ratio
    - defender.defence × defender.rpm_ratio × 0.5
) × mass_factor

damage_dealt = attacker.damage × attacker.rpm_ratio
```

Where `mass_factor = 2 × attacker.mass / (attacker.mass + defender.mass)`
(lighter tops get pushed more).

### What each side experiences

**Attacker:**
- Small recoil (~25% of applied_knockback, opposite direction)
- Small RPM loss (~10% of damage_dealt)

**Defender:**
- Knockback impulse in the direction away from the attacker
- RPM loss equal to `damage_dealt`
- Enters reactive state for ~0.4s (see below)

### Symmetry

Both tops can be considered "attacker" simultaneously — each one applies its
own attack to the other in the same frame. This is conceptually cleaner than
the previous "one top handles the collision" approach.

### Vertical component

Vertical kick is small (5–10% of horizontal knockback magnitude) and scales
inversely with the **defender's** RPM ratio. Full-RPM defenders don't fly
upward at all; low-RPM defenders can be launched out of the arena.

### Ability hooks

The collision formula has well-defined hook points for passive abilities to
modify outcomes — see the Abilities section below.

---

## Reactive State (Post-Collision)

For ~0.4s after a collision, the top is in **reactive state**:

- Scripted movement is suspended
- The top moves freely under the applied knockback impulse with gradual damping
- The top can collide again during this period (no cooldown lockout)
- A small `recovery_steering` force gently reorients toward the scripted
  pattern's current target, blending back in

After the reactive period ends, the top resumes scripted movement. The pattern
isn't restarted from the beginning — it continues from where it was, so
collisions don't disrupt the overall flow of the choreography.

### Recovery curve

The blend from reactive → scripted happens over the last ~0.15s of the
reactive period, where the steering force ramps up smoothly. This avoids the
"snap" of the top suddenly resuming its path.

---

## Abilities

Abilities are **optional** special mechanics that some tops have. They give
each top a memorable identity beyond raw stats and create distinct gameplay
moments — useful for short-form content where viewers latch onto recognisable
character behaviour.

A top has either zero or one ability. Tops with abilities have a smaller stat
budget (see Per-Top Stats), making the choice between "stronger raw fighter"
and "specialist with a trick" a genuine trade-off.

### Two categories

Abilities split into two distinct kinds, each integrating with the architecture
differently:

| Category | When it fires | Where it hooks |
|---|---|---|
| **Trigger** | On a specific condition | State machine — adds new states |
| **Passive** | Always active | Existing systems (collision formula, RPM bleed, etc.) |

### Trigger abilities

Trigger abilities activate on a condition and produce a dramatic, time-limited
effect. They temporarily replace normal behaviour with ability-specific
behaviour.

A trigger ability has three parts:

1. **Activation condition** — when does it fire? (e.g. `current_rpm < 100`,
   `collision_count >= 3`, `time_in_match > 20s`)
2. **Effect** — what does the top do during the ability? (e.g. high-speed
   seek, brief invulnerability, RPM burst)
3. **Termination** — when does it end? (e.g. collision happens, fixed
   duration expires, out of bounds)

Most trigger abilities are **one-shot per match** — they can only fire once,
which makes the activation moment a clear story beat. Some may be repeatable
with cooldowns if balanced carefully.

#### Example: Kamikaze

> When `current_rpm < 100`, the top launches toward the opponent at maximum
> velocity, ignoring its normal movement pattern.

- **Condition:** `current_rpm < 100` (one-time check; cannot retrigger)
- **Effect:** Suspend scripted movement. Steer aggressively toward opponent's
  current position at 3–4× normal max speed.
- **Termination:** Collision with the opponent, or top crosses
  `knockout_radius` (flies out of arena), or RPM hits 0.
- **Story beat:** A losing top makes one final desperate strike. May result in
  a dramatic tie, a last-second knockout, or comic failure if it overshoots.

#### Other trigger ability ideas

- **Burst** — once per match, the next collision deals 2× knockback
- **Panic Drift** — below 30% RPM, brief teleport-style dash to centre of
  arena (looks like a recovery move)
- **Last Stand** — when RPM first drops below 500, restore RPM to 1000 and
  switch to `aggressive_seek` pattern
- **Shed** — when knocked back hard, gain 0.5s of invulnerability but lose
  20% RPM

### Passive abilities

Passive abilities are **always active** and modify how the top reacts to
ongoing events. They don't add new states; instead they tweak the formulas
that already run each frame.

A passive ability defines hooks into existing systems:

- **`on_collision`** — modifies the collision formula's outcome
- **`on_rpm_decay`** — modifies the natural RPM bleed each frame
- **`on_pattern_step`** — modifies the movement target each frame
- **`on_knockback_received`** — modifies incoming knockback

Multiple passives could theoretically stack (if a top had two), but the design
keeps it to one per top for clarity.

#### Example: Speed Boost

> Adds a small amount of RPM to the top on every collision.

- **Hook:** `on_collision` (after damage is applied)
- **Effect:** `current_rpm += 100` (capped at `starting_rpm × 1.1` to prevent
  runaway feedback loops)
- **Story beat:** A top that thrives on aggression — the more it clashes, the
  longer it lasts. Counters stamina types that try to outlast it.

#### Other passive ability ideas

- **Resilience** — incoming `damage` is reduced by 50%
- **Counter** — when hit, deal additional knockback equal to 30% of the
  knockback received (back at the attacker)
- **Heavy** — `mass_factor` in collisions is permanently treated as if the
  top were 50% heavier
- **Magnetic** — collision threshold is increased by 50%, so this top
  initiates clashes more easily
- **Erosion** — opponent's RPM decay rate is doubled while this top is within
  collision range
- **Steady** — pattern jitter is reduced and pattern speed stays high even at
  low RPM (better tracking)

---

## The Dying Phase (Physics-Driven)

When a top's RPM drops below `dying_threshold` (e.g. 500 RPM), the simulation
**switches to physics-based behaviour** for visual drama:

- Scripted movement turns off
- The top is subject to gyroscopic precession (using the COM-aware code from
  the previous simulation)
- Precession grows dramatically as RPM continues to drop, producing wide
  wobbles
- When RPM hits ~5, the top falls over and the match ends with the existing
  slow-motion + greyscale game-over sequence

This is the one place where physics simulation produces something genuinely
better than scripted animation. A dying top wobbling unpredictably before
toppling is visually compelling in a way no scripted curve can replicate.

**Trigger abilities can pre-empt the dying phase** — kamikaze fires at 100
RPM, which is below the 500 dying threshold. In this case the top skips
straight from SCRIPTED → ABILITY_ACTIVE without passing through DYING. When
the ability terminates, the top enters DYING.

---

## RPM as the Match Clock

RPM serves as the universal timer for a match:

1. Both tops launch at their `starting_rpm`
2. RPM bleeds off at `rpm_decay_rate` per second continuously
3. Collisions cost additional RPM (`damage` formula)
4. Passives may modify the bleed or gain rate
5. When RPM crosses `dying_threshold`, the dying phase begins (unless an
   ability triggers first)
6. When RPM hits 0, the match ends

This means matches have a **predictable maximum length**:

```
max_duration = starting_rpm / rpm_decay_rate
```

For default stamina type values: `5000 / 8 = 625 seconds` (~10 minutes
absent collisions). For attack: `6000 / 40 = 150 seconds` (2.5 minutes
unmolested). Collision damage shortens this further.

For short-form content, **default decay rates should be tuned so matches last
20–40 seconds even without aggressive play**, with collisions producing
dramatic finishes earlier.

---

## Environment: The Stadium

The stadium is a **purely visual** element with minimal physics interaction.
Tops move within an arena boundary (defined by `wall_radius`) using scripted
movement; they never genuinely contact the wall under normal play.

### Boundary handling

If a top is knocked outward by a collision, it can fly past the boundary —
this is a knockout. The boundary check is a simple radius test, no wall
contact physics needed.

- `wall_radius` (~150mm) — soft boundary; pattern targets are clamped to stay
  inside
- `knockout_radius` (~190mm) — past this, the top counts as knocked out
- If knockout happens, that top enters dying phase immediately regardless of RPM

### Visual stadium

The stadium mesh remains for visual purposes (the bowl shape, the rim, etc.)
and provides ground collision so tops sit on it visually. It does not need
the elaborate physics interactions of the previous simulation — friction,
wall repel, centripetal pulls, etc. all go away.

---

## What's Still Simulated (Not Scripted)

| System | Simulated? | Why |
|---|---|---|
| Top spin (visual) | Yes — apply angular velocity around Y axis | Cheap and necessary for visuals |
| Falling onto bowl on spawn | Yes — gravity drops top onto bowl | Looks natural, no need to script |
| Knockback impulses | Half-and-half | Initial impulse applied physically, scripted movement resumes after reactive period |
| Dying phase wobble | Yes — full physics with gyroscope | Visual drama beyond what scripting can do |
| Final topple and stop | Yes — full physics | Natural ending feels right |
| Collision detection | No — pure distance check | Proximity is reliable, physics contacts were not |
| Horizontal movement | No — scripted patterns | This is the whole point |
| Vertical position | Mostly physics (gravity + bowl) | Tops sit on the bowl, scripted patterns handle Y= constant |
| Wall contact | Eliminated | Pattern boundary keeps tops in arena |
| Ability effects | Mostly scripted | Triggers swap behaviour to scripted ability logic |

---

## State Machine Per Top

```
       ┌──────────────┐
       │   SPAWNING   │  (~0.5s — drops onto bowl, settles)
       └──────┬───────┘
              ↓
       ┌──────────────┐  ──── collision detected  ──→  ┌─────────────┐
       │   SCRIPTED   │                                 │  REACTIVE   │
       │              │  ←── reactive period expires ── │   (~0.4s)   │
       └──────┬───────┘                                 └─────────────┘
              │                                          ↑
              │  ability condition met                   │ collision
              ↓                                          │ during ability
       ┌──────────────┐                                  │
       │   ABILITY    │ ─────── ability terminates ──────┤
       │   ACTIVE     │ ──── (or ends at RPM = 0) ───┐   │
       └──────┬───────┘                              │   │
              │                                      │   │
              │  RPM drops below dying_threshold     │   │
              ↓                                      ↓   │
       ┌──────────────┐                       ┌─────────────┐
       │    DYING     │ ────────────────────→ │  GAME_OVER  │
       └──────────────┘                       └─────────────┘
```

The ABILITY_ACTIVE state exists only for tops with **trigger** abilities.
Passive abilities don't appear in the state machine; they modify the
behaviour of other states transparently.

Transitions are clear and non-overlapping. Each frame the top is in exactly
one state, and only that state's logic runs.

---

## Implementation Architecture

### Suggested file structure

```
res://
├── scripts/
│   ├── tops/
│   │   ├── base_top.gd              # State machine, top behaviour
│   │   ├── attack_top.gd            # Stats + pattern choice for attack
│   │   ├── defence_top.gd
│   │   └── stamina_top.gd
│   ├── stats/
│   │   └── top_stats.gd             # Resource: stat values
│   ├── patterns/
│   │   ├── movement_pattern.gd      # Base class
│   │   ├── circle_pattern.gd
│   │   ├── figure_eight_pattern.gd
│   │   ├── aggressive_seek_pattern.gd
│   │   └── ...
│   ├── abilities/
│   │   ├── ability.gd               # Base class with hook methods
│   │   ├── kamikaze.gd              # Trigger ability
│   │   ├── burst.gd                 # Trigger ability
│   │   ├── speed_boost.gd           # Passive ability
│   │   ├── resilience.gd            # Passive ability
│   │   └── ...
│   └── managers/
│       └── game_manager.gd          # Match flow, game over
└── ...
```

### Ability base class shape

```gdscript
class_name Ability
extends Resource

# Overridden by subclasses
func get_category() -> String: return "passive"   # or "trigger"

# Trigger lifecycle
func should_activate(top: BaseTop) -> bool: return false
func on_activate(top: BaseTop) -> void: pass
func update_active(top: BaseTop, delta: float) -> void: pass
func should_terminate(top: BaseTop) -> bool: return true
func on_terminate(top: BaseTop) -> void: pass

# Passive hooks (called from base_top.gd)
func modify_outgoing_collision(attacker: BaseTop, defender: BaseTop, knockback: float, damage: float) -> Dictionary:
    return {"knockback": knockback, "damage": damage}
func modify_incoming_knockback(top: BaseTop, knockback: float) -> float:
    return knockback
func modify_rpm_decay(top: BaseTop, delta_rpm: float) -> float:
    return delta_rpm
func on_collision(top: BaseTop, other: BaseTop) -> void: pass
```

Each ability subclass implements only the hooks it needs. The base_top.gd
state machine and collision logic call into these hooks at the appropriate
points.

### What to preserve from the old code

- Game manager (`game_manager.gd`) — works fine, mostly unchanged
- Stadium scene (visual only)
- Dying-phase precession code — extract from `_apply_gyroscopic_physics`
- The OBJ models and Blender pipeline

### What to discard

- All zone-based force code (centre pull, wall repel, etc.)
- Attraction system (replaced by scripted patterns drawing tops toward each
  other naturally)
- Queued impulse pattern (collisions are symmetric and direct now)
- The whole gyroscopic system, except dying phase
- Wall contact handling

---

## Tuning & Iteration Plan

1. **Phase 1 — Build the state machine.** Get a top spawning, following a
   pattern, dying after enough time. No collisions yet, no abilities.
2. **Phase 2 — Add collision detection and the knockback formula.** Two tops
   should now interact in a basic way.
3. **Phase 3 — Add reactive state.** Collisions should now feel impactful
   with proper recovery.
4. **Phase 4 — Polish patterns.** Add randomisation, pattern breaks,
   per-type tuning.
5. **Phase 5 — Reintroduce dying phase physics.** Polish the final wobble.
6. **Phase 6 — Add abilities framework.** Base class, hook system,
   ability_active state.
7. **Phase 7 — Implement a trigger ability (kamikaze).** Validates the
   activation/effect/termination cycle.
8. **Phase 8 — Implement a passive ability (speed_boost).** Validates the
   hook system.
9. **Phase 9 — Stat balance pass.** Run many matches across various stat
   profiles and abilities. Tune until each combination feels distinct and
   matchups are interesting.

Each phase should be **runnable and visibly improved** before moving to the
next. Don't go back to fix earlier phases until you've tried the current one
in motion.

---

## Open Questions

These are things to decide as you go:

- Should `dying_threshold` be a fixed RPM or a percentage of starting RPM?
- Should collisions trigger camera effects (zoom, shake, slowmo) for drama?
- Should abilities have visible activation effects (particle bursts, screen
  flashes, UI callouts)? Probably yes for triggers, no for passives.
- Can a top have multiple passive abilities, or strictly one?
- Should the stat budget be a hard system (literal point allocation) or a
  soft guideline (you decide per top)?
- How many distinct movement patterns are needed? (Probably 6–8 is enough.)
- How many abilities to ship initially? (Probably 4–6 — two triggers, two
  passives, plus a few "no ability" tops with raw-stat dominance.)
- Should ability triggers be telegraphed (visual warning before activation)
  so viewers can anticipate the moment?

These are good problems to encounter mid-implementation rather than try to
solve up-front.
