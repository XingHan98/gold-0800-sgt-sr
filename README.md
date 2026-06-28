# Gold 08:00 SGT Support / Resistance

Automation that draws daily **support and resistance lines for gold (XAU/USD)** at
**08:00 Singapore time (SGT)** on weekdays, based on the price action just before 08:00.

Two implementations are included:

| File | Platform | Use |
|------|----------|-----|
| [`GoldSupportResistance.pine`](GoldSupportResistance.pine) | TradingView (Pine Script v5) | Cleaner visuals + native SGT timezone |
| [`GoldSupportResistance.mq5`](GoldSupportResistance.mq5) | MetaTrader 5 (MQL5 EA) | Drawing now; auto-trading later |

## Strategy logic

On the **15-minute** timeframe, at 08:00 SGT each weekday (Mon–Fri):

- **Bar A** starts as the 07:45 SGT candle (the one that closes at 08:00),
  **Bar B** as the 07:30 SGT candle before it.
- **Resistance:** if `Close(A) > High(B)` → resistance = `High(B)`. Otherwise step
  back one 15-minute interval (`A := B`, `B :=` the older neighbour) and compare
  again, repeating until the condition is met.
- **Support:** if `Close(A) < Low(B)` → support = `Low(B)`. Same backward walk.
- The two searches are independent, each starting from the 07:45 / 07:30 pair.

> Note: 08:00 SGT == 00:00 UTC year-round (Singapore observes no daylight saving),
> which the MT5 version uses as a clean anchor.

## TradingView setup

1. Open an `OANDA:XAUUSD` chart on the **15-minute** timeframe.
2. Open the **Pine Editor**, paste the contents of `GoldSupportResistance.pine`.
3. **Save**, then **Add to chart**. Lines draw for current and historical days.

Inputs let you adjust the backward-search depth, line colors/width, and toggle labels.

## MetaTrader 5 setup

1. Copy `GoldSupportResistance.mq5` into `MQL5/Experts/` (MT5 → File → Open Data Folder).
2. Open it in MetaEditor and **Compile (F7)**.
3. Attach to a **XAUUSD M15** chart with **Algo Trading** enabled.

The EA auto-detects the broker's server-to-UTC offset (with a manual override input)
and logs the computed levels, source bars, and times to the Experts tab.

## Status

Line drawing is complete on both platforms. Auto-trading off these levels is the
planned next phase for the MT5 version.
