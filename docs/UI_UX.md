# LifeOS — UI/UX Design Plan

> Liquid glass over a living color mesh · editorial serif + Geist · one iridescent signature reserved for AI. A personal operating system that feels alive but stays calm enough to use every day.
> Companion to [ARCHITECTURE.md](ARCHITECTURE.md) · Status: **design plan, ready for implementation** · 2026-11-12

---

## Table of contents

1. [Design direction](#1-design-direction)
2. [What we take from each reference](#2-what-we-take-from-each-reference)
3. [Design principles](#3-design-principles)
4. [Design tokens](#4-design-tokens)
5. [Glass system](#5-glass-system)
6. [Background per screen](#6-background-per-screen)
7. [Motion system](#7-motion-system)
8. [Navigation and app shell](#8-navigation-and-app-shell)
9. [Screen specifications](#9-screen-specifications)
10. [Progression system (XP, levels, achievements)](#10-progression-system-xp-levels-achievements)
11. [Charts and data visualization](#11-charts-and-data-visualization)
12. [Component library](#12-component-library)
13. [States: empty, loading, error, offline](#13-states-empty-loading-error-offline)
14. [Accessibility](#14-accessibility)
15. [Performance budget](#15-performance-budget)
16. [Flutter project structure](#16-flutter-project-structure)
17. [Mock data strategy](#17-mock-data-strategy)
18. [Implementation plan](#18-implementation-plan)
19. [Decisions and deviations from the brief](#19-decisions-and-deviations-from-the-brief)
20. [Implementation status](#20-implementation-status)

---

## 1. Design direction

**One sentence:** frosted glass panels floating over slowly shifting color, with calm editorial type — the AI is the only thing that shimmers.

| Feeling | How the UI delivers it |
|---|---|
| *I understand my life* | One calm Home screen with a clear hierarchy: ring → insight → priorities → the rest collapsed |
| *I know what to do* | Top 3 priorities always visible; timeline for the day; one-tap completion |
| *I can see progress* | Animated rings, count-up stats, charts that draw themselves |
| *I'm growing* | Level, XP, skill radar, roadmaps as progression paths |
| *Someone is helping me* | A living assistant orb, a daily insight card, proposal cards you approve |

Brand motif: **the AI mark** — a flat iridescent disc with a white spark (like the Apple Intelligence / Gemini language), plus an animated iridescent border on AI surfaces. It replaces both character art (reference 1's character is someone else's IP) and the v1 glossy orb.

---

## 2. What we take from each reference

| Reference | Keep | Leave out |
|---|---|---|
| **1 — Progression dashboard** | Circular "system" visualization around a central figure; skill bars and percentages; stacked dashboard cards; uppercase micro-labels that feel like a game HUD | Anime character art; desktop grid; dense unreadable small text |
| **2 — Atmospheric analytics** | Flowing particle waves; thin luminous lines; gradient-filled area charts; glowing data points; subtle grid | Busy multi-chart walls; heavy glow on everything |
| **3 — Mobile glassmorphism** | Frosted cards; floating pill navigation; greeting header; round icon buttons; lavender gradients; generous spacing and rounding | Light lavender page background (we stay dark); photo-heavy cards |

**Combination rule:** reference 3 provides the **structure and glass** (layout, spacing, components), reference 2 the **atmosphere** (living color background, clean charts), reference 1 the **meaning** (progression, levels, skills). v2 also borrows from shipping apps: iOS 26 liquid glass, Apple Fitness rings, Arc/Linear typography, Things 3 restraint.

---

## 3. Design principles

1. **Hierarchy over density.** Each screen has one hero element. Everything else is secondary or collapsed.
2. **Glass needs color behind it.** Real blur everywhere (shared via BackdropGroup) over a colorful mesh; never dark glass on a black background.
3. **Glow means AI.** The iridescent glow is reserved for assistant surfaces. Everything else uses color, not glow.
4. **Motion explains change.** Every animation answers "what just happened?" — something was added, completed, opened or grew.
5. **Sophisticated gamification.** XP and levels are quiet numbers and thin bars, not cartoons or confetti storms. No penalties, no guilt.
6. **Calm by default.** Ambient effects are slow (8–15 s loops), low-contrast and pause when not visible or when reduced motion is on.
7. **One-thumb usable.** Primary actions sit in the bottom half of the screen; touch targets ≥ 48 dp.

---

## 4. Design tokens

> **v2 visual refresh (2026-11-12).** The first build read as generic "AI dashboard" (purple glow everywhere, glossy orb, uppercase HUD labels, dark-purple cards). v2 follows current platform design instead: iOS 26 / visionOS liquid glass, Apple Fitness rings, Arc/Linear typography. Code: `mobile/lib/core/theme/`.

All tokens live in `lib/core/theme/` as static constants (`LifeColors`, `LifeGradients`, `LifeText`, `Space`, `Radii`, `LifeShadows`).

### 4.1 Color

**Base — neutral and cool, not purple.** Color comes from the mesh background and from accents with a job.

| Token | Value | Use |
|---|---|---|
| `bg` | `#07070B` | App background |
| `bgElevated` | `#101016` | Sheets |
| `solid` | `#14141B` | Opaque cards for dense lists |
| `surfaceHigh` | `#1D1D26` | Tooltips, menus, snackbars |
| `text` | `#F5F5F7` | Primary text |
| `text2` | white-ish @ 62% | Secondary text |
| `text3` | white-ish @ 38% | Hints, disabled, axis labels |
| `onLight` | `#0B0B10` | Text on white buttons/chips |
| `glass` / `glassHigh` / `glassActive` | white @ 6% / 10% / 16% | Glass fills, active capsules |
| `glassBorder` / `hairline` | white @ 12% / 8% | Borders, dividers |

**Accents — each has a job**

| Token | Hex | Job |
|---|---|---|
| `iris` | `#8E7CFF` | Primary accent, tasks, AI |
| `sky` | `#5DB7FF` | Goals, schedule |
| `mint` | `#4FE0B0` | Learning, study, success |
| `coral` | `#FF8E6E` | Habits, high priority |
| `rose` | `#FF6FAE` | Journal, mood |
| `amber` | `#FFC46B` | Streaks, warnings, energy |
| `danger` | `#FF6B7A` | Destructive, overdue |

**Mood 1→5:** slate `#7C8AA5` → iris → sky → mint → amber. Low moods are cool and calm, never red.

### 4.2 Gradients

| Token | Use |
|---|---|
| `ai` / `aiColors` (iris → rose → amber → mint → sky, sweep) | **Only** AI elements: AI mark, AI border, proposal badges |
| `glassFill` (white 12% → 5% → 3%, diagonal) | Glass panel fill |
| `glassRim` (white 40% → 8% → 4% → 20%) | 1 px specular rim on glass |
| `accent(c)` (c → c+30% white) | Progress bars, ring arcs |
| `chartFill(c)` / `bar(c)` | Chart areas and bars |

Rule: **no decorative gradients on buttons or text.** Primary buttons are solid white.

### 4.3 Typography

| Role | Font | Why |
|---|---|---|
| Editorial titles, greeting | **Instrument Serif** (regular + italic) | Gives a personal, editorial tone that generic dashboards lack |
| UI text and big numbers | **Geist** (tight tracking on large sizes) | Modern, neutral, excellent numerals |
| Small numeric meta | **Geist Mono** | Durations, times, counts: "45m · Due 8:00 PM" |

| Style | Size / line | Font |
|---|---|---|
| `display` | 40 / 44 | Instrument Serif — page titles |
| `titleSerif` / `titleSerifItalic` | 30 / 34 | Instrument Serif — greeting, prompts |
| `statHero` | 48 / 50, −2 tracking | Geist 600 — Home "54%" |
| `statLarge` | 36 / 40 | Geist 600 |
| `stat` | 22 / 26 | Geist 600 |
| `h2` | 20 / 26 | Geist 600 |
| `title` | 16 / 22 | Geist 600 — section titles |
| `body` / `bodyStrong` | 15 / 22 | Geist 400 / 500 |
| `label` | 13 / 18 | Geist 500 |
| `eyebrow` | 13 / 18, `text2` | Geist 500 — small label above a title or value (sentence case) |
| `caption` | 12 / 16, `text2` | Geist 400 |
| `mono` | 12 / 16, `text2` | Geist Mono 500 |

**No uppercase letter-spaced labels.** Sentence case everywhere. Numbers use tabular figures.

### 4.4 Spacing, radius, size

| Spacing (4-pt grid) | `xs 4` · `sm 8` · `md 12` · `lg 16` · `xl 20` · `xxl 24` · `xxxl 32` · `huge 40` |
|---|---|
| Screen side padding | 20 |
| Gap between cards | 12 |
| Section gap | 24 |

| Radius | Value | Use |
|---|---|---|
| `sm` | 12 | Small chips |
| `md` | 18 | Inputs |
| `lg` | 24 | Cards |
| `xl` | 30 | Hero card, sheets |
| `pill` | 999 | Nav, segmented control, chips, buttons |

Nav bar height 64; avatar 44; touch targets ≥ 48.

### 4.5 Shadows and glow

| Token | Use |
|---|---|
| `glass` | Soft lift under glass (rarely needed) |
| `float` | Nav bar, FAB, sheets |
| `halo(color)` | Selected mood orb, accent button |

**Glow is reserved for AI.** The animated iridescent `AiGlowBorder` is the only glowing element in normal use.

### 4.6 Iconography

Lucide (`lucide_icons_flutter`). Icons sit inside **IconChip**s — rounded squares tinted with their domain color (like iOS Settings), not floating bare.

### 4.7 Theme mode

Dark only for v1.

---

## 5. Glass system

Glass only looks like glass when there is color behind it, so v2 pairs **white-tinted liquid glass** with a **colorful mesh background** (§6).

| Surface | Look | Used for |
|---|---|---|
| **Glass** (default) | Backdrop blur σ 24 + `glassFill` + 1 px `glassRim` specular edge | Cards, nav bar, buttons, chips, segmented control |
| **Tinted glass** | Glass + accent tint (22% → 8%) | A card that belongs to a domain (mint level card, mood-tinted check-in) |
| **Solid** | `solid` fill + hairline border | Long dense lists |
| **Sheet** | Blur σ 40 + dark gradient fill + bright top edge | Bottom sheets |

**Performance:** all glass surfaces use `BackdropFilter.grouped` inside one app-wide `BackdropGroup`, so the blur is computed once per frame and shared. That's what makes real glass affordable on every card. Verify in profile mode on the S23 FE.

**Card anatomy**

```
╭──────────────────────────────╮  ← specular rim: bright top-left & bottom-right
│ Eyebrow              action  │  ← sentence-case, text2
│ Title / big number           │
│ content…                     │
╰──────────────────────────────╯
   blurred mesh color shows through a white 5–12% fill
```

---

## 6. Background per screen

One `AmbientBackground` sits behind the shell: a **mesh gradient** of four large blurred color blobs drifting on slow paths (24 s loop), a **readability veil** (colorful top → deeper bottom), and static **film grain**. Switching tabs **blends the colors** (700 ms) instead of swapping backgrounds.

| Screen | Mesh colors | Mood |
|---|---|---|
| **Home** | iris, sky, rose, deep blue | Vivid, motivating |
| **Plan** | sky, cobalt, iris, teal (softer) | Cool, focused |
| **Growth** | mint, sky, deep teal, iris | Fresh, progressing |
| **Journal** | rose, coral, amber, plum (softer) | Warm, personal |
| **Assistant** | iris, rose, sky, mint | Iridescent, AI |

No particles, no sine-wave lines, no orbiting arcs — those read as generic "AI" decoration.

---

## 7. Motion system

### 7.1 Tokens (`lib/core/motion/motion.dart`)

| Token | Duration | Curve | Use |
|---|---|---|---|
| `press` | 120 ms | `easeOutCubic` | Button scale-down (0.97) |
| `release` | 180 ms | `easeOutBack` (subtle) | Button release |
| `check` | 220 ms | `easeOutCubic` | Checkbox morph |
| `card` | 300 ms | `easeInOutCubic` | Expand/collapse, card enter |
| `nav` | 320 ms | `Cubic(0.2, 0, 0, 1)` | Tab switch, nav indicator |
| `modal` | 300 ms | `Cubic(0.2, 0, 0, 1)` in / `easeInCubic` 200 ms out | Sheets, dialogs |
| `page` | 350 ms | `Cubic(0.2, 0, 0, 1)` | Route push (fade + 24 px slide) |
| `countUp` | 800 ms | `easeOutCubic` | Stat numbers |
| `chart` | 900 ms | `easeOutCubic` | Line draw, bar rise |
| `ring` | 1000 ms | `easeOutCubic` | Progress ring fill |
| `stagger` | 40 ms per item, max 6 items | — | Card/list enter |
| `ambient` | 8–15 s loop | `linear` / sine | Background |

### 7.2 Choreography

**Screen enter (first time per session)**
1. Header fades in (0 ms).
2. Hero element scales 0.96 → 1 + fades (60 ms).
3. Cards enter staggered: fade + 16 px rise, 40 ms apart, max 6.
4. Inside cards: rings/charts/count-ups start when the card is ≥ 30% visible (`VisibilityDetector`-style check via scroll position — no extra package needed).

Revisiting a tab does **not** replay entry animations (state kept by `StatefulShellRoute`).

**Task completion**
1. Checkbox: border circle → filled iris circle → check path draws (220 ms).
2. Title gets a strike-through that sweeps left → right (200 ms), text fades to secondary.
3. Card slides out / collapses (300 ms) if the current filter hides done tasks; undo snackbar for 4 s.
4. Home ring animates to its new value (600 ms) and the XP number counts up "+20 XP" in a small floating label.
5. If this completed the day or hit a milestone → `GlowBurst` (one ring of 12 particles, 700 ms). Never more than once per action.

**Proposal approval**
- Accept: card border flashes success → card shrinks to a pill "Task created" → pill fades (total ~600 ms).
- Reject: card slides left and fades (250 ms).
- Modify: card expands in place into an editable form (300 ms, shared size animation).

**Assistant**
- Typing indicator: three dots pulsing in sequence (opacity 0.3 → 1, 900 ms loop).
- Streaming: text appended per chunk with a 120 ms fade on the newest words; the bubble's height animates with `AnimatedSize`.
- AI mark: spectrum turns slowly (8 s) when idle, 3× faster while thinking; the input bar gets the glowing AI border while focused.

### 7.3 Navigation transitions

| Transition | Animation |
|---|---|
| Bottom tab switch | Content cross-fade + 8 px vertical shift (320 ms); background mode cross-fade |
| Push detail screen | Fade-through + 24 px slide up (350 ms) |
| Card → detail | `Hero` on the card container (task, goal, skill, project, journal entry) |
| Bottom sheet | Slide up + background scrim fade; sheet starts at scale 0.98 |
| Back | Reverse of the above |

### 7.4 Reduced motion

`MotionPrefs` provider reads `MediaQuery.disableAnimations` (Android "Remove animations") plus an in-app toggle (Settings → "Reduce motion").

When on:
- Ambient backgrounds are static images of their first frame.
- Durations collapse to 0 for count-ups, charts, rings (values jump).
- Page transitions become simple 150 ms fades.
- No particles, no glow bursts.

### 7.5 Lifecycle rules

- Ambient tickers use `TickerMode` so they **stop when the tab isn't visible**.
- They also stop when the app is backgrounded (`AppLifecycleState.paused`).
- No continuous animation inside list items.

---

## 8. Navigation and app shell

### 8.1 Route map (GoRouter)

```
/splash
/onboarding                     first launch only
/auth/login
/auth/register
/auth/forgot
StatefulShellRoute (bottom nav, state kept per tab)
├── /home
│   ├── /home/review/daily
│   └── /home/notifications
├── /plan                       ?tab=tasks|goals|habits|calendar
│   ├── /plan/task/:id
│   ├── /plan/goal/:id
│   └── /plan/habit/:id
├── /growth                     ?tab=overview|skills|roadmaps|study|projects
│   ├── /growth/skill/:id
│   ├── /growth/roadmap/:id
│   ├── /growth/project/:id
│   ├── /growth/focus           full-screen focus timer
│   └── /growth/achievements
├── /journal
│   ├── /journal/entry/new
│   ├── /journal/entry/:id
│   └── /journal/insights
└── /assistant                  ?tab=chat|reviews|suggestions
    ├── /assistant/chat/:conversationId
    ├── /assistant/review/weekly/:weekStart
    └── /assistant/memories
/settings
/settings/profile · /settings/notifications · /settings/ai · /settings/privacy · /settings/diagnostics
```

Auth redirect: no session → `/auth/login`; session → `/home`.

### 8.2 Floating glass bottom navigation

```
            ╭──────────────────────────────────────────────╮
            │  ⌂        ▦        ✦        ✎        ◉       │
            │ Home     Plan    Growth  Journal  Assistant  │
            ╰──────────────────────────────────────────────╯
                 ↑ active: lighter-glass capsule (white 16% + rim) slides between items; white icon + label
```

- True glass (tier 2), radius pill, margin 16 horizontal, floats 12 dp above the system nav area.
- **Active indicator:** a single pill (`gradPrimary` at 25% + `glowViolet`) that **slides** between items (320 ms, `nav` curve) — it doesn't jump.
- Icon cross-fades outline → filled; label color animates `textMuted → textPrimary`.
- Inactive items show icons + small labels (labels always visible: clearer for daily use).
- Assistant item shows a small pulsing dot when proposals are pending.
- Hides on scroll down (slides 100 dp down, 250 ms), reappears on scroll up — only on long lists (Plan, Journal history).

### 8.3 Quick add (global)

A **Core-orb FAB** (56 dp, `gradAurora`, glow) sits above the nav bar's right edge on Home and Plan.

Tap → bottom sheet (true glass):

```
╭────────────────────────────────────────╮
│  ─────                                 │
│  ✦ Type anything…                      │  ← quick capture: "study graphs tomorrow 7pm"
│    → suggestion preview appears below  │
│                                        │
│  [☐ Task] [⏰ Reminder] [✎ Journal]     │
│  [☺ Mood] [⏱ Study session]            │
╰────────────────────────────────────────╯
```

The text field uses rules first, then `/agent/quick-capture` (see ARCHITECTURE §12.2). The result shows as a mini proposal card to confirm.

### 8.4 Headers

- Large title header (`h1`) that collapses into a compact true-glass app bar on scroll (`SliverAppBar` + blur only when collapsed).
- Settings is reached from the avatar on Home (not a tab).

---

## 9. Screen specifications

Wireframes are schematic (not to scale). `[ ]` = card, `( )` = button/chip.

### 9.0 Onboarding and auth

**Onboarding (3 slides, first launch):** AI mark fades in over the mesh → "Your personal operating system" → "An assistant that suggests, you decide" → "Let's set up your day" (review time, notification permission, Samsung battery-optimization tip).

**Login / Register:** Home mesh background, a single glass card centered low on screen, serif "LifeOS" wordmark above. Register fields: name, email, password (strength bar), invite code (shown only if the server says invite mode). Error states inline under fields.

---

### 9.1 Home — Daily Command Center (high immersion)

**Purpose:** in 5 seconds, know how today is going and what to do next.

```
┌──────────────────────────────────────────┐
│ Thursday, 12 November           🔔  (G)  │  eyebrow + glass bell + avatar
│ Good afternoon,                          │  Instrument Serif 34
│ Gaurav                                   │  Instrument Serif italic, text2
│                                          │
│ ╭──────────── TODAY (glass) ───────────╮ │
│ │ Today                    ╭─────╮     │ │
│ │ 72%                     ( ◎◎◎ )      │ │  Geist 48 + three activity rings
│ │ of your day is done      ╰─────╯     │ │  (tasks iris · habits coral · study mint)
│ │ ● Tasks   ● Habits   ● Study         │ │
│ │ 5/8       4/5        2h 10m          │ │
│ │ ───────────────────────────────────  │ │
│ │ Level 7  ▁▁▁▁▁▁▁▁░░░░░░     +120 XP   │ │  iris→rose bar, Geist Mono
│ ╰──────────────────────────────────────╯ │
│ ╭ iridescent AI border ────────────────╮ │
│ │ (✦) Assistant          Daily insight │ │
│ │ You finish most tasks before 1 PM…   │ │
│ │ (Plan tomorrow)  Later               │ │  white primary + ghost
│ ╰──────────────────────────────────────╯ │
│ Priorities                     See all   │
│ [○ Solve 3 sliding-window problems   ●] │  one glass card, divided rows
│ [  45m · Due 8:00 PM                  ] │  Geist Mono meta
│ [○ Write your first Dockerfile       ●] │
│ [○ Revise SQL joins                  ●] │
│                                          │
│ [(▦) Schedule  3 blocks · next 7:00 PM ⌄]│  collapsible rows with IconChips
│ [(🔥) Habits   4 of 5 · 12-day streak  ⌄]│
│ [(📖) Learning Java DSA · 62%          ⌄]│
│                                   ( + )  │  solid white FAB
│ ╭──────────── glass tab bar ───────────╮ │
└──────────────────────────────────────────┘
```

**Hierarchy**
1. Hero ring card — always visible, the only true-glass card on Home.
2. AI insight — only shown if one exists for today; dismissible (dismissed state saved).
3. Top 3 priorities — the most important action area.
4. Collapsible sections (schedule, habits, learning) — **collapsed summary rows by default**; expansion state remembered.

**Details**
- **Activity rings:** `ActivityRings` — three concentric rings (tasks iris, habits coral, study mint vs. daily goal), 12 dp stroke, rounded caps, each tinted track at 18%. The big number is the average of the three.
- Tap ring → `/home/review/daily` (Hero transition).
- **Priority card:** swipe right = complete, swipe left = snooze to tomorrow. Tap = expand (description, subtasks, "Start focus"). Long-press = edit.
- **Schedule (expanded):** vertical timeline — time on the left, a glowing dot for "now", blocks as small frosted cards, past blocks dimmed.
- **Habits (expanded):** horizontal row of habit chips; tap toggles with a fill animation and a pink glow; streak count beside each.
- **Learning (expanded):** active path progress bar + today's study minutes + "Start focus" button.
- **Header:** greeting changes by time of day; notification bell shows a dot for unread; ⚙ opens Settings.
- **Pull to refresh:** custom indicator = a small activity ring filling up.

---

### 9.2 Plan — Productivity hub (low immersion)

**Purpose:** fast, clean management of tasks, goals, habits and time.

```
┌──────────────────────────────────────────┐
│ Plan                              🔍  ⋯  │
│ ( Tasks | Goals | Habits | Calendar )    │  sliding segmented control
│                                          │
│ [✦ 3 suggestions from your assistant  →] │  pending proposals banner
│                                          │
│ (Today 5) (Upcoming) (Overdue 2) (Done)  │  filter chips w/ counts
│                                          │
│ MORNING                                  │  grouped by time / due
│ [○ Solve 3 sliding-window …   45m ●H  ⌄] │  solid cards (tier 0)
│ [○ Revise SQL joins           30m ●L  ⌄] │
│ EVENING                                  │
│ [○ Docker: first Dockerfile   1h  ●M  ⌄] │
│                                          │
│                                   (◉+)   │
└──────────────────────────────────────────┘
```

**Tasks tab**
- Filters: Today · Upcoming · Overdue · Completed (+ optional goal/tag filter via ⋯).
- Grouping: Today → morning/afternoon/evening/anytime; Upcoming → by date; Overdue → by how late.
- **Expandable TaskCard:** description, subtasks (inline checkboxes), linked goal chip, reminder time, estimate vs actual, buttons: Start focus · Edit · Delete.
- Swipe right = complete (iris reveal with check icon), swipe left = reschedule sheet (Tomorrow / Next week / Pick date).
- Drag handle (long-press) to reorder within a group.
- Overdue tasks: thin `danger` left stripe, not a red card.

**Goals tab**
- Goal cards with category icon, progress bar (or milestone dots), target date, "x days left".
- Detail: progress chart over time, milestones checklist, linked tasks, linked projects/paths.

**Habits tab**
- Each habit: title, 7-day dot row (filled/empty/skipped), streak 🔥 count, today toggle.
- Detail: month heat-map (GitHub-style, pink intensity), best streak, completion % chart.

**Calendar tab**
- Horizontal **week strip** (swipeable), today highlighted with a white ring; dots under days with items.
- Tap ⌄ to expand into a month grid (animated height).
- Below: day agenda timeline = schedule blocks + timed tasks + reminders.
- Tap an empty slot → create a block at that time.

**Proposals banner** → opens Assistant › Suggestions (same ApprovalCards).

---

### 9.3 Growth — Skills, learning and progression (medium immersion)

**Purpose:** see yourself improving as a developer.

```
┌──────────────────────────────────────────┐
│ Growth                                🏆 │
│ ╭──────────── LEVEL CARD ──────────────╮ │
│ │ (Core)  LEVEL 7 · ADEPT              │ │
│ │         ▁▁▁▁▁▁▁▁▁▁▁░░░  1,240/1,600XP │ │
│ │  🔥 12 days   ◆ 34 SP   ★ 9 badges    │ │
│ ╰──────────────────────────────────────╯ │
│ ( Overview | Skills | Roadmaps | Study | Projects )
│                                          │
│ [SKILL RADAR                          ]  │  hexagon radar, glowing outline
│ [   Java ╱╲ DSA                       ]  │
│ [  Cloud ╲╱ SQL …                     ]  │
│                                          │
│ [STUDY THIS WEEK        8h 40m  ▲18%  ]  │  gradient area chart
│ [ ∿∿∿∿∿∿∿∿∿∿∿∿∿∿                       ]  │
│                                          │
│ [ACTIVE ROADMAP  Java DSA  62%   →    ]  │
│ [ ● Arrays ● Hashing ◐ Sliding ○ Trees ]  │  node path preview
│                                          │
│ [PROJECTS  LifeOS 35% · K8s lab 10%   ]  │
│                                          │
│ (⏱ Start focus session)                  │  primary gradient button
└──────────────────────────────────────────┘
```

**Overview:** level card, skill radar (top 6 skills), weekly study chart, active roadmap preview, projects summary, recent achievements row.

**Skills:** list of `SkillProgressCard`s — icon, name, level 1–5 as 5 segments (filled with `gradPrimary`), skill XP bar, hours this month, sparkline. Detail: hours over time, linked topics, sessions.

**Roadmaps:** each learning path as a **vertical progression path**:

```
  ●──  Arrays & Hashing           ✓ done · revised 2×
  │
  ●──  Two Pointers               ✓ done · revision due ⟳
  │
  ◐──  Sliding Window   MEDIUM    in progress · 3 sessions
  │      needs: Two Pointers ✓
  ○──  Trees            HARD      locked until prerequisites done (dimmed)
```

- Node states: done (filled, glow), in progress (half ring animating), not started, locked (prerequisite missing, dimmed — still tappable to see why).
- Revision status: ⟳ badge when `next_revision_at` is due (spaced review: +1 d, +3 d, +7 d, +21 d).
- Tap node → topic sheet: description, resources links, difficulty, sessions, "Start focus", "Mark done", "Mark revised".

**Study:**
- Big focus timer entry (`/growth/focus`): full-screen, aurora ring counting down, choose topic/skill, Pomodoro presets (25/5, 50/10, custom), screen stays awake. Ending creates a `study_session` and shows "+XP".
- Today's minutes, weekly bar/area chart, topic-wise breakdown (horizontal bars), session history list.

**Projects:** cards with name, tech-stack chips, progress bar, next milestone + deadline. Detail: milestones checklist, linked tasks, study sessions on the project, repo link.

**Achievements (`/growth/achievements`):** grid of badges (hexagon frames). Locked = dim outline with hint; unlocked = filled with glow and date.

---

### 9.4 Journal — Calm, personal space (low, soft immersion)

**Purpose:** quick check-in, easy writing, gentle reflection.

```
┌──────────────────────────────────────────┐
│ Journal                           📅  ⋯  │
│ ╭──────── HOW ARE YOU TODAY? ──────────╮ │
│ │   ◌     ◌     ◉     ◌     ◌          │ │  5 mood orbs, selected grows+glows
│ │  low   meh   okay  good  great       │ │
│ │  Energy      ▁▁▁▁▁▁▁▁░░░  7          │ │  glass sliders
│ │  Motivation  ▁▁▁▁▁░░░░░░  5          │ │
│ │  (tired) (focused) (+ tag)           │ │  tag chips
│ ╰──────────────────────────────────────╯ │
│                                          │
│ [✎ PROMPT  What drained your energy    ] │  reflection prompt card
│ [          today?        (Write) (↻)   ] │  ↻ = another prompt
│                                          │
│ THIS MONTH                               │
│ [ mood calendar heat-map (pink scale) ]  │
│                                          │
│ RECENT ENTRIES                           │
│ [ Wed 11 · "Finally understood DP…"   ]  │
│ [ Mon 9  · "Low energy but shipped…"  ]  │
│                                          │
│                          (✎ New entry)   │
└──────────────────────────────────────────┘
```

- **Mood orbs:** five custom-painted faces inside orbs colored by the mood scale. Tap → selected orb scales to 1.25, glow fades in, neighbours shrink slightly to 0.9; background radial tint shifts to that mood's color (400 ms). Saves automatically (debounced) — no Save button.
- **Editor (`/journal/entry/new`):** full-screen, minimal: date, optional title, large body field, mood chip carried over. Autosaves every few seconds to Drift; "Saved" fades in the corner. A small lock icon shows AI access for this entry (off by default, tap to allow).
- **History:** month calendar where each day is tinted by mood; tap a day → that day's mood + entries.
- **Insights (`/journal/insights`):** mood/energy line chart (30 days), tag frequency, "best days" correlation (e.g. more study minutes on high-energy days) — all computed locally; AI commentary only if `mood_ai_enabled`.
- Optional biometric lock just for the Journal tab.

---

### 9.5 Assistant — AI companion (high immersion)

**Purpose:** talk, review, approve.

```
┌──────────────────────────────────────────┐
│          ( ✦ AI mark, iridescent aura )        │
│              LifeOS Assistant            │
│      ( Chat | Reviews | Suggestions 3 )  │
│                                          │
│ ╭ assistant ───────────────────────────╮ │  frosted, left aligned
│ │ You've studied 8h this week — your   │ │
│ │ best week this month. Want me to…    │ │
│ ╰──────────────────────────────────────╯ │
│                     ╭ you ─────────────╮ │  solid white, dark text, right
│                     │ Plan my next week│ │
│                     ╰──────────────────╯ │
│ ╭ PROPOSAL ────────────────────────────╮ │  ApprovalCard
│ │ ✦ Create 5 tasks · Java DSA week     │ │
│ │ Why: interview in 4 weeks, trees not │ │
│ │ started, ~6h free this week          │ │
│ │ ▸ show 5 changes                     │ │
│ │ (Reject)   (Modify)   (Accept all ✓) │ │
│ ╰──────────────────────────────────────╯ │
│ (Plan tomorrow) (How am I doing?) (…)    │  context suggestion chips
│ ╭─ true glass input ──────────── (➤) ──╮ │
└──────────────────────────────────────────┘
```

**Chat**
- Assistant bubbles: frosted, left, small Core avatar on the first bubble of a group. User bubbles: `gradPrimary` at 85%, right.
- Streaming text with typing indicator before the first token.
- Suggestion chips above the input change with context (time of day, pending items): "Plan tomorrow", "How am I doing this week?", "Make a roadmap for…", "I feel unmotivated".
- Input bar: true glass, grows to 5 lines, send button glows when text exists. Shows "Offline — I'll need internet for this" when offline.
- Conversation list via ⋯ (history) — most use is a single ongoing thread.

**Reviews**
- **Daily review card:** done vs planned, study time, habit consistency (dots), highlights ("Completed the Docker basics topic"), needs attention (overdue items), tomorrow's top 3 (as proposals to accept).
- **Weekly review page:** hero stats row (count-up), productivity area chart, learning progress per skill, goal progress bars, mood trend (only if enabled), AI recommendations as numbered cards, proposals at the bottom.
- List of past reviews by date.

**Suggestions** — all pending proposals, grouped by origin (chat / daily review / weekly review), with "Accept all in group".

**ApprovalCard (critical component)**

| Part | Content |
|---|---|
| Header | ✦ icon + action summary ("Create task", "Move 3 tasks to Saturday") |
| Diff | For updates: `before → after` per field (old value struck through, new in iris). For creates: the new item preview. Groups: collapsed list "show N changes" with per-item checkboxes. |
| Reason | One or two lines from the agent, `textSecondary` |
| Meta | Expires in X days · from Daily review |
| Actions | Reject (ghost) · Modify (outline) · Accept (gradient) |

- Accept never happens on a single accidental tap of a group: groups show the count in the button ("Accept 4") reflecting checked items.
- After accept → collapses into a success pill with "View" link to the created item.

**Memories (`/assistant/memories`)** — list grouped by type; each item editable/deletable; proposed memories shown at top with Keep / Discard.

---

### 9.6 Settings

Glass list sections: Profile · Notifications (review times, quiet hours, channels) · AI & privacy (master switch, memory, mood AI, journal AI, daily budget + today's usage) · Appearance (reduce motion, ambient intensity: Off / Low / Normal) · Security (app lock, sessions, change password) · Data (export, delete account) · Diagnostics (sync status, pending items, version) · About.

---

## 10. Progression system (XP, levels, achievements)

Computed **deterministically on the backend** (no AI), from activity events. Sophisticated, never punishing.

### 10.1 XP sources

| Action | XP |
|---|---|
| Complete task | low 10 · medium 20 · high 30 |
| Log habit (done) | 5 (+5 on 7-day, +20 on 30-day streak marks) |
| Study session | 1 XP per minute, max 180/day |
| Complete learning topic | 40 (easy 30 / hard 60) |
| Revise a topic on time | 15 |
| Goal milestone | 100 |
| Complete goal | 250 |
| Project milestone | 80 |
| Journal entry / mood check-in | 5 each, max once per day |
| Approve an AI plan | 0 (no XP for accepting suggestions — XP is for doing) |

Uncompleting a task removes its XP (ledger entry reversed) so XP can't be farmed.

### 10.2 Levels and ranks

- XP needed to go from level *n* to *n+1*: `round(100 × n^1.5)` → L1→2: 100, L5→6: ~1,118, L10→11: ~3,162.
- Rank titles every 5 levels: **Initiate** (1–4) · **Adept** (5–9) · **Specialist** (10–14) · **Expert** (15–19) · **Master** (20–29) · **Architect** (30+).
- Level-up moment: full-screen dim, AI-color ring sweep + glow burst, "Level 8 · Adept" (1.2 s), tap to dismiss. Once per level.

### 10.3 Skill points (SP)

- Each skill has its own XP from study sessions and topics linked to it.
- Every 100 skill XP = 1 SP. SP is shown on the skill card and the radar.
- Suggested skill level (1–5) is derived from SP thresholds; the user can override it (self-assessment wins).

### 10.4 Achievements (examples)

| Badge | Condition |
|---|---|
| First Light | Complete your first task |
| Week Warrior | 7-day habit streak |
| Deep Diver | 3 hours of study in one day |
| Pathfinder | Finish a learning roadmap |
| Century | 100 DSA problems solved (from `problems_solved`) |
| Consistent | 30-day streak on any habit |
| Shipper | Complete a project |
| Reflective | 20 journal entries |

### 10.5 Schema additions

See ARCHITECTURE.md §8 (added): `xp_ledger`, `achievements`, `user_achievements`, and on `learning_topics`: `prerequisite_ids`, `revision_count`, `next_revision_at`.

---

## 11. Charts and data visualization

**Library:** `fl_chart` for line/area/bar/radar (supports curved lines, gradient fills, custom dots, custom tooltips, animated transitions). **CustomPainter** for: activity rings, AI mark, roadmap path, heat-map, ambient background.

### 11.1 Chart style (shared `ChartTheme`)

| Element | Style |
|---|---|
| Lines | 2 px, curved (smoothness 0.35), color = domain accent; outer glow via a second 6 px line at 20% opacity |
| Area | `gradChartFill` (35% → 0%) |
| Bars | Rounded top (radius 6), vertical gradient (accent → accent 40%), track bar behind at 6% white |
| Grid | Horizontal lines only, `white 5%`, dashed; no vertical grid |
| Axes | No axis lines; labels `caption` in `textMuted`; max 4 y-labels |
| Points | Hidden except last point (glowing dot, 4 px + 10 px halo) and the touched point |
| Tooltip | Small frosted pill: value in `stat` style + date in `caption` |
| Entry | Lines draw left → right (900 ms); bars rise with 30 ms stagger; radar scales from center |
| Empty | Faint dashed baseline + "No data yet" + a hint action |

### 11.2 Chart catalogue

| Chart | Type | Where |
|---|---|---|
| Daily completion | Aurora ring | Home hero |
| Weekly productivity | Area (tasks done/day) | Assistant weekly review |
| Study duration | Bars (7 days) / area (30 days) | Growth › Study, Overview |
| Skill profile | Radar (6 axes) | Growth › Overview |
| Skill progression | Sparkline per skill | Skill cards |
| Habit consistency | Dot rows (7 d), heat-map (month) | Plan › Habits, Home |
| Goal progress | Progress bars; line over time in detail | Plan › Goals |
| Mood trend | Smooth line with mood-colored gradient | Journal insights, weekly review (opt-in) |
| Topic breakdown | Horizontal bars | Growth › Study |

---

## 12. Component library

All in `lib/core/widgets/`. Each has a gallery entry (see §18 step 4).

| Component | Key props | Notes |
|---|---|---|
| `AmbientBackground` | `mode` | Mesh gradient + veil + grain behind the shell; blends palettes between tabs |
| `GlassSurface` / `GlassCard` | `tier`, `tint`, `ai`, `padding`, `radius`, `onTap`, `heroTag` | Liquid glass by default; `ai: true` adds the iridescent border |
| `GlassSheet` | `child`, `title` | True glass bottom sheet with drag handle |
| `GlassBottomNav` | `items`, `index`, `onChanged`, `badges` | Sliding indicator |
| `GlassAppBar` | `title`, `actions`, `collapsed` | Blur only when collapsed |
| `SegmentedGlass` | `segments`, `value` | Sliding pill indicator |
| `FilterChipRow` | `chips`, `selected`, `counts` | Horizontal scroll |
| `GradientButton` | `label`, `icon`, `variant` (primary white / accent / glass / ghost / danger), `loading` | Press scale; no gradients |
| `AiMark` / `AiGlowBorder` | `size`, `state` (idle / thinking) | Iridescent AI identity; the only glowing elements |
| `ActivityRings` / `AnimatedProgressRing` | `rings` (value + color), `stroke` | Apple Fitness-style concentric rings |
| `AnimatedCounter` | `value`, `style`, `prefix/suffix`, `format` | Count-up, tabular figures |
| `AnimatedStatCard` / `IconChip` | `label`, `value`, `trend`, `icon`, `accent` | Tinted icon chip + counter |
| `XpBar` | `current`, `max`, `level` | Thin gradient bar with sheen sweep on gain |
| `GlowBurst` | `trigger` | One-shot particle burst |
| `TaskCard` | `task`, `onToggle`, `onExpand`, `dense` | Swipe actions, expandable |
| `AnimatedCheck` | `checked`, `color` | Morph circle → filled → check path |
| `GoalCard` | `goal` | Progress or milestone dots |
| `HabitChip` / `HabitRow` | `habit`, `log` | Tap toggle with fill animation |
| `TimelineView` | `items`, `now` | Day schedule |
| `WeekStrip` / `MonthGrid` | `selected`, `markers` | Calendar |
| `SkillProgressCard` | `skill` | Segments + sparkline |
| `RoadmapPath` | `topics` | Vertical node path |
| `MoodSelector` | `value`, `onChanged` | Five orbs |
| `GlassSlider` | `value`, `min/max`, `label` | Energy, motivation |
| `ChartCard` | `title`, `value`, `trend`, `chart` | Standard wrapper |
| `AIInsightCard` | `insight`, `actions` | Gradient border + Core icon |
| `ApprovalCard` | `proposal` / `group`, callbacks | See §9.5 |
| `ChatBubble` | `message`, `streaming` | Assistant / user styles |
| `TypingIndicator` | — | Three dots |
| `CollapsibleSection` | `title`, `summary`, `child`, `initiallyOpen` | Remembered state |
| `EmptyState` | `icon`, `title`, `message`, `action` | |
| `SkeletonBox` | `width`, `height` | Shimmer loading |
| `OfflineBanner` | — | Shown when offline |

---

## 13. States: empty, loading, error, offline

| State | Treatment |
|---|---|
| **Loading** | Skeletons with a slow white shimmer (1.5 s); never a full-screen spinner. Data from Drift usually makes loading instant. |
| **Empty** | Friendly line + one action: "No tasks today. Enjoy it — or (add one)." Icon in a small glass circle. |
| **Error** | Inline card: what failed + "Try again". No raw error text. |
| **Offline** | Thin glass banner under the header: "Offline · changes will sync". AI surfaces show a disabled state with explanation. |
| **AI unavailable / budget reached** | Insight card: "Your assistant is resting today." AI mark shown without animation. Everything else works. |
| **First run** | Home shows a 3-step "Set up your day" checklist (add a goal, add habits, set review time) instead of empty sections. |

---

## 14. Accessibility

- Contrast: `textPrimary` and `textSecondary` on `bg`/`surface` pass WCAG AA. `textMuted` (~3.9:1) is used only for non-essential text ≥ 14 sp or decorative labels.
- Never rely on color alone: priority = dot **and** label on expand; overdue = stripe **and** "Overdue" text; mood = face shape **and** color.
- All interactive elements ≥ 48 dp; `Semantics` labels on icon buttons, rings ("Daily progress 68 percent"), mood orbs, chart summaries.
- Text scales with system font size up to 1.3×; layouts tested at 1.3× with no overflow.
- Reduced motion (see §7.4) and ambient intensity setting.
- Haptics: light impact on complete/toggle, medium on approval accept, success pattern on level-up (respect system setting).

---

## 15. Performance budget

Target: **smooth 60 fps on the Galaxy S23 FE** (and acceptable on older mid-range Android).

| Rule | Detail |
|---|---|
| Blur budget | ≤ 3 `BackdropFilter`s visible; none in lists |
| Ambient | One `CustomPainter`, ≤ 40 particles, `RepaintBoundary`, pauses off-screen and in background |
| No `Opacity` widget on large subtrees | Use color alpha or `FadeTransition` |
| Shadows | Pre-baked where possible; max a few glow shadows per screen |
| Lists | `ListView.builder` / slivers; `const` constructors |
| Charts | Animate once on first view; static afterwards |
| Images | None needed for core UI (all drawn) → small APK |
| Profiling | `flutter run --profile` + DevTools performance overlay on the S23 FE after each screen |
| Impeller | Default renderer on Android in this Flutter version; verify blur performance in profile mode |

---

## 16. Flutter project structure

```
mobile/
├── pubspec.yaml
├── assets/
│   ├── fonts/            Sora, Inter
│   └── textures/noise.png
└── lib/
    ├── main.dart
    ├── app/
    │   ├── app.dart                 MaterialApp.router + theme
    │   └── bootstrap.dart           ProviderScope, env, mock/real switch
    ├── core/
    │   ├── theme/
    │   │   ├── colors.dart          palette + semantic + mood
    │   │   ├── gradients.dart
    │   │   ├── typography.dart
    │   │   ├── spacing.dart         spacing, radius, sizes
    │   │   ├── shadows.dart
    │   │   ├── life_tokens.dart     ThemeExtension
    │   │   └── app_theme.dart       Material 3 ThemeData (dark)
    │   ├── motion/
    │   │   ├── motion.dart          durations + curves
    │   │   ├── motion_prefs.dart    reduced-motion provider
    │   │   ├── transitions.dart     page transitions for GoRouter
    │   │   └── stagger.dart         staggered entry helper
    │   ├── routing/
    │   │   ├── router.dart
    │   │   └── routes.dart          route names/paths
    │   ├── widgets/                 design system (§12)
    │   │   ├── glass/               glass_card, glass_sheet, glass_app_bar, glass_bottom_nav
    │   │   ├── buttons/             gradient_button, icon_glass_button
    │   │   ├── progress/            progress_ring, xp_bar, animated_counter, stat_card
    │   │   ├── effects/             ambient_background, core_orb, glow_burst, shimmer
    │   │   ├── inputs/              segmented_glass, filter_chips, glass_slider, glass_text_field
    │   │   ├── charts/              chart_theme, line_area_chart, bar_chart, radar_chart, heatmap
    │   │   └── feedback/            empty_state, skeleton, offline_banner, collapsible_section
    │   ├── constants/
    │   └── utils/                   date formatting, extensions
    ├── shell/
    │   └── app_shell.dart           ambient background + nav + FAB
    ├── features/
    │   ├── auth/
    │   ├── onboarding/
    │   ├── home/
    │   ├── plan/                    tasks, goals, habits, calendar
    │   ├── growth/                  skills, roadmaps, study, projects, achievements, focus
    │   ├── journal/
    │   ├── assistant/               chat, reviews, proposals, memories
    │   └── settings/
    │       └── (each feature)
    │           ├── data/            repository interface + mock_*.dart + (later) api_*.dart
    │           ├── domain/          models (freezed)
    │           ├── presentation/
    │           │   ├── screens/
    │           │   └── widgets/
    │           └── providers.dart
    ├── mock/
    │   └── seed.dart                one realistic seeded dataset shared by all mock repos
    └── dev/
        └── gallery_screen.dart      component gallery (debug builds only)
```

---

## 17. Mock data strategy

- Every feature defines a **repository interface** in `data/` (e.g. `TaskRepository`).
- `MockTaskRepository` holds in-memory state seeded from `mock/seed.dart` (a believable week: Java DSA path, Docker path, LifeOS project, 5 habits, 2 weeks of mood/study history, a few pending proposals, a daily and weekly review).
- Mock repos support writes (complete task, log habit, approve proposal) so the UI is fully interactive, and add 150–400 ms fake latency to exercise loading states.
- A single provider override in `bootstrap.dart` switches mock ↔ real (`--dart-define=DATA_SOURCE=mock|api`).
- Later, `ApiTaskRepository` (Dio) and the Drift-backed repos implement the same interfaces — screens don't change.
- The mock assistant streams canned responses word by word and returns sample proposals so ApprovalCards can be tested.

---

## 18. Implementation plan

Each step ends with something runnable on the S23 FE. Mock data throughout; backend integration follows the roadmap in ARCHITECTURE.md.

| # | Step | Output | Check |
|---|---|---|---|
| 1 | **Project setup** | `flutter create` (Android only, org id), packages, fonts, lints, folder structure | App launches |
| 2 | **Design tokens + theme** | colors, gradients, typography, spacing, `LifeTokens`, dark `ThemeData` | Theme applied |
| 3 | **Motion + effects core** | motion tokens, reduced-motion provider, `AmbientBackground`, `AiMark`, `GlowBurst` | Background runs smoothly in profile mode |
| 4 | **Component library + gallery** | Glass tiers, buttons, ring, counter, XP bar, chips, segmented, slider, check, skeleton, empty state, chart theme | `/dev/gallery` shows every component |
| 5 | **Shell + navigation** | GoRouter with `StatefulShellRoute`, `GlassBottomNav` with sliding indicator, tab transitions, quick-add FAB + sheet, mock seed + repos | Can switch tabs; quick-add opens |
| 6 | **Home** | Header, hero ring card, insight card, priorities, collapsible schedule/habits/learning, completion choreography | Completing a task updates ring + XP |
| 7 | **Plan** | Tasks (filters, swipe, expand, reorder), Goals, Habits, Calendar, proposals banner | All four tabs interactive |
| 8 | **Growth** | Level card, radar, study charts, roadmap path, skills, projects, focus timer, achievements | Focus session creates mock study session + XP |
| 9 | **Journal** | Mood check-in, sliders, prompts, editor with autosave, mood calendar, insights | Mood/entries persist in mock state |
| 10 | **Assistant** | Chat with streaming + typing indicator, suggestion chips, ApprovalCard (single + group + modify), reviews, memories | Accepting a proposal creates a task visible on Plan/Home |
| 11 | **Auth + onboarding + settings UI** | Login, register, forgot, onboarding slides, settings sections | Flows navigate correctly (mock auth) |
| 12 | **Polish + performance** | Hero transitions, stagger tuning, reduced-motion pass, text-scale 1.3× pass, profile on S23 FE, fix jank | 60 fps scrolling, no overflow |

After step 12 the UI shell is complete and backend Phase 1 (auth) can be wired into it.

### Packages

| Package | Purpose |
|---|---|
| `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator`, `build_runner` | State |
| `go_router` | Navigation |
| `freezed`, `freezed_annotation`, `json_serializable`, `json_annotation` | Models |
| `fl_chart` | Charts |
| `lucide_icons_flutter` | Icons |
| `intl` | Dates and numbers |
| `uuid` | Client-side IDs |
| `dio` | Added at API integration time |
| `drift`, `flutter_secure_storage`, Firebase | Added at their roadmap phases |

No Rive/Lottie initially — everything above is achievable with built-in animation APIs and `CustomPainter`.

---

## 19. Decisions and deviations from the brief

| Brief says | Decision | Reason |
|---|---|---|
| Android **and iPhone** | Android only (layouts stay platform-neutral) | ARCHITECTURE decision: no Mac, primary device S23 FE |
| "High amount of glassmorphism" | Real glass on every card, blur shared via `BackdropGroup`, over a color mesh | One shared blur pass keeps it fast; color behind glass is what makes it read as glass |
| Character art like reference 1 | Flat iridescent **AI mark** (v1 used a glossy orb) | Original identity, no third-party IP; v1 orb read as generic AI decoration |
| Light/dark preference | Dark only for v1 | Visual identity depends on dark glass |
| Gamification (XP, levels, SP) | Added backend tables + deterministic rules (§10) | Wasn't in the architecture; must not use AI |
| Roadmap prerequisites + revision status | Added topic fields | Wasn't in the schema |
| Quick actions on Home | Global Core-orb FAB + quick-capture sheet | Keeps Home uncluttered; available on Plan too |
| Settings as a section | Reached from avatar, not a tab | Five tabs are already the maximum for comfort |
| Rive/Lottie | Not used initially | Native animation + CustomPainter covers it, fewer dependencies |
| Brief palette (`#0B0814` violet base, lavender, neon accents) | v2 neutral base + iris/sky/mint/coral/rose/amber accents | v1 with the brief palette looked like generic AI output; user asked for a more modern look with more color |
| Sora + Inter, uppercase HUD labels | Instrument Serif + Geist + Geist Mono, sentence case | More distinctive and current; uppercase HUD labels read as sci-fi cliché |

---

## 20. Implementation status

As of 2026-11-12 every screen in §9 is built in `mobile/lib/` and runs on sample data (steps 1–11 of §18).

| Area | Built |
|---|---|
| Shell | Glass tab bar, per-tab mesh background, quick-add (rule parser → real task), floating “+XP” toast, level-up moment |
| Auth | Onboarding (3 slides), sign in, register (strength meter, invite code), forgot password, redirects by sign-in state |
| Home | Activity rings, AI insight (opens suggestions / plans tomorrow), priorities, schedule, habits, learning, notifications sheet |
| Plan | Tasks (filters, time-of-day groups, swipe complete/reschedule, editor sheet with steps), goals (progress types, milestones, linked tasks), habits (7-day dots, month heat-map, new habit), calendar (week strip, agenda) |
| Growth | Level card, skill radar, study chart, skills (levels, sparklines), roadmaps (node path, prerequisites, revision), study history, projects (milestones), focus timer, achievements |
| Journal | Mood check-in (autosaves), energy/motivation/tags, prompts, mood calendar, entries, autosaving editor with per-entry AI lock, insights |
| Assistant | Streaming chat with typing indicator, suggestion chips, approval cards (single, group with checkboxes, modify), daily and weekly reviews, suggestions inbox, memory screen |
| Settings | Profile, reviews and notifications, AI and privacy toggles, daily budget, appearance, security, data, sign out |

**Sample data** lives in `mobile/lib/data/` (`models.dart`, `seed.dart`, `stores.dart`). The stores follow the
backend's rules (XP per priority, 180 XP/day study cap, level curve, goal progress, approval before execution),
so swapping them for API/Drift-backed repositories won't change the screens.
Run with `--dart-define=START_SIGNED_IN=true` to skip onboarding during development.
