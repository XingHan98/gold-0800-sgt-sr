# Gold 08:00 SGT Support / Resistance

Automation that draws daily **support and resistance lines for gold (XAU/USD)** at
**08:00 Singapore time (SGT)** on weekdays, based on the price action just before
08:00, plus **ATR-based take-profit levels** for the buy and sell cases.

Two implementations are included:

| File | Platform | Use |
|------|----------|-----|
| [`GoldSupportResistance.pine`](GoldSupportResistance.pine) | TradingView (Pine Script v5) | Cleaner visuals + native SGT timezone |
| [`GoldSupportResistance.mq5`](GoldSupportResistance.mq5) | MetaTrader 5 (MQL5 EA) | Drawing now; auto-trading later |

## Strategy logic

On the **5-minute** timeframe, at 08:00 SGT each weekday (Mon–Fri):

- **Bar A** starts as the 07:55 SGT candle (the one that closes at 08:00),
  **Bar B** as the 07:50 SGT candle before it.
- **Resistance:** if `Close(A) > High(B)` → resistance = `High(B)`. Otherwise step
  back one interval (`A := B`, `B :=` the older neighbour) and compare again,
  repeating until the condition is met.
- **Support:** if `Close(A) < Low(B)` → support = `Low(B)`. Same backward walk.
- The two searches are independent, each starting from the 07:55 / 07:50 pair.

> Note: 08:00 SGT == 00:00 UTC year-round (Singapore observes no daylight saving),
> which the MT5 version uses as a clean anchor.

> The interval is configurable. In MT5 it's the `InpTimeframe` input (default M5);
> in Pine it's simply the chart's timeframe (use a 5-minute chart).

## Take-profit levels (ATR)

Each day also draws three take-profit lines per side, spaced by the **ATR** (Average
True Range, default period 14) measured at Bar A. One "step" = `ATR × multiple`
(the multiple is an input, default 1.0):

- **Buy case** (above resistance `R`): `R + 1·step`, `R + 2·step`, `R + 3·step`
- **Sell case** (below support `S`): `S − 1·step`, `S − 2·step`, `S − 3·step`

S/R lines are **solid**; the six TP lines are **dotted**. Buy levels use the
resistance colour with labels above; sell levels use the support colour with labels
below. Every line is tagged with its price and the 08:00 SGT time.

> ATR uses TradingView's built-in `ta.atr()` / MT5's native `iATR()` — **no paid
> plan required**.

## TradingView setup

1. Open an `OANDA:XAUUSD` chart on the **5-minute** timeframe.
2. Open the **Pine Editor**, paste the contents of `GoldSupportResistance.pine`.
3. **Save**, then **Add to chart**. Lines draw for current and historical days.

Inputs: backward-search depth, ATR length, ATR multiple per TP step, line
colours/width, and a labels toggle.

## MetaTrader 5 setup

1. Copy `GoldSupportResistance.mq5` into `MQL5/Experts/` (MT5 → File → Open Data Folder).
2. Open it in MetaEditor and **Compile (F7)**.
3. Attach to a **XAUUSD M5** chart with **Algo Trading** enabled.

The EA auto-detects the broker's server-to-UTC offset (with a manual override input),
computes the ATR take-profit spacing, and logs the levels, source bars, ATR step,
and times to the Experts tab.

> MT5 renders dotted lines only at width 1, so the dotted TP lines are forced to
> width 1 while the solid S/R lines keep the configured width.

## Inputs reference

| Setting | MT5 input | Pine input | Default |
|---------|-----------|------------|---------|
| Bar A/B interval | `InpTimeframe` | chart timeframe | M5 / 5-min |
| Search depth | `InpLookbackBars` | `Max bars to search back` | 300 / 200 |
| ATR length | `InpAtrPeriod` | `ATR length` | 14 |
| ATR multiple per step | `InpAtrMult` | `ATR multiple per TP step` | 1.0 |
| Resistance / Buy-TP colour | `InpResColor` | `Resistance / Buy-TP color` | red |
| Support / Sell-TP colour | `InpSupColor` | `Support / Sell-TP color` | blue |
| Line width | `InpLineWidth` | `Line width` | 2 |
| Server→UTC offset | `InpManualOffsetHours` | — (native SGT) | auto |

## Daily Telegram alerts

A cloud job sends the day's levels to Telegram every weekday at 08:00 SGT — no
always-on machine required (it runs on GitHub Actions).

- [`daily-telegram/daily_levels.py`](daily-telegram/daily_levels.py) — fetches
  5-min `XAU_USD` candles from the **OANDA v20 API** and computes the same
  support/resistance + ATR take-profits as the indicators, then sends a Telegram
  message. ATR uses Wilder smoothing to match TradingView's `ta.atr`.
- [`.github/workflows/daily-levels.yml`](.github/workflows/daily-levels.yml) —
  schedule `0 0 * * 1-5` (00:00 UTC = 08:00 SGT, Mon–Fri), plus a manual
  **Run workflow** button.

### Message format

```
📅 Gold 08:00 SGT — 2026-06-29
🟢 BUY entry (R): 4062.34
   TP1: 4067.51  TP2: 4072.69  TP3: 4077.87
🔴 SELL entry (S): 4059.55
   TP1: 4054.37  TP2: 4049.19  TP3: 4044.01
```

### Required GitHub Actions secrets

Repo → Settings → Secrets and variables → Actions:

| Secret | Purpose |
|--------|---------|
| `OANDA_API_TOKEN` | OANDA v20 personal access token (data only) |
| `OANDA_ENV` | `live` or `practice` — **must match where the token was generated** |
| `TELEGRAM_BOT_TOKEN` | token from @BotFather |
| `TELEGRAM_CHAT_ID` | your numeric chat ID (message the bot once first) |

Optional env tweaks (set in the workflow): `ATR_PERIOD`, `ATR_MULT`, `LOOKBACK`,
`INSTRUMENT`, `GRANULARITY`, `DECIMALS`.

### Running / troubleshooting

- **Manual run:** Actions tab → *Daily Gold Levels* → **Run workflow**.
- **401 from OANDA:** `OANDA_ENV` doesn't match the token (live token needs
  `live`, demo token needs `practice`).
- **400 from Telegram:** wrong `TELEGRAM_CHAT_ID`, or you haven't sent your bot a
  message yet (a bot can't message you first).
- The script exits cleanly (no failure email) on weekends, missing data, or
  missing secrets.

## Status

Line drawing and ATR take-profit levels are complete on both platforms, and the
daily Telegram alert is live. Auto-trading off these levels is the planned next
phase for the MT5 version (currently in the backlog).
