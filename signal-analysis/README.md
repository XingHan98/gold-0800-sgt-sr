# Instructor signal analysis (reverse-engineering)

Goal: collect the instructor's daily gold signals and test them against a library
of common reference levels to see whether a consistent **strategy/pattern** drives
the entry, stop, and take-profit prices.

> The signal data (`instructor_signals.csv`) is **gitignored** — it stays on your
> machine and is not pushed to the public repo, since these are a paid product.

## How to log each signal

Two signals per day: **AM = 08:00 SGT**, **PM = 19:00 SGT**. Add one row per signal
to `instructor_signals.csv`:

| Column | Meaning | Example |
|--------|---------|---------|
| `date` | calendar date in SGT (YYYY-MM-DD) | `2026-06-30` |
| `session` | `AM` (08:00 SGT) or `PM` (19:00 SGT) | `AM` |
| `direction` | `buy` or `sell` (leave blank and I'll infer it) | `buy` |
| `entry` | the instructor's entry price | `4065.0` |
| `stop_loss` | the stop level | `4058.0` |
| `tp1`,`tp2`,`tp3` | take-profit targets (leave extras blank) | `4070.0` |
| `notes` | anything unusual (e.g. "two entries", "cancelled", "entry not hit") | |

Tips:
- Record the price **as given**, even if it looks like a typo — accuracy matters.
- If a session has more than one call, add multiple rows with the same date/session.
- If there are more than 3 TPs, add `tp4`, `tp5` columns — that's fine.
- Delete the two `example row` lines once you start logging real data.

## What I'll do with it

For each signal I'll pull the OANDA XAU/USD market context around the 08:00 / 19:00
SGT timestamp and test how closely the instructor's prices line up with candidate
levels, e.g.:

- Pivot points (classic / Fibonacci / Camarilla) from the prior session
- Previous session high / low / close / open; Asian-range high/low
- Fibonacci retracements / extensions of the recent swing
- Round numbers
- ATR-based offsets (and the entry-to-SL / entry-to-TP distances vs ATR)
- Session-open prices

The consistent matches across many signals reveal the method. ~20–30 signals gives
a reliable read; fewer is suggestive at best.

## Status

Collecting. Ping me when you have a couple of weeks of data (or whenever you want a
first look) and I'll build the analysis script and run it.
