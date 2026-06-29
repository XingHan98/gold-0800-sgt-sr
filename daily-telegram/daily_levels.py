#!/usr/bin/env python3
"""
Daily Gold 08:00 SGT support/resistance + ATR take-profit levels -> Telegram.

Mirrors the logic of the MT5 EA / Pine indicator in this repo:
  * 08:00 SGT == 00:00 UTC (Singapore has no DST).
  * On the 5-minute timeframe, Bar A = the 07:55 SGT candle (closes 00:00 UTC),
    Bar B = the 07:50 SGT candle before it.
  * Resistance: first pair (walking back) where Close(A) > High(B) -> High(B).
  * Support:    first pair (walking back) where Close(A) < Low(B)  -> Low(B).
  * ATR (Wilder, default 14) at Bar A; one "step" = ATR * multiple.
  * Buy TPs:  R + 1/2/3 * step.   Sell TPs: S - 1/2/3 * step.

Data source: OANDA v20 REST API (matches the TradingView OANDA:XAUUSD feed).
Designed to run in GitHub Actions on a daily cron; no always-on machine needed.
"""
import os
import sys
import datetime as dt
import requests

# --- Config (overridable via environment) ---
INSTRUMENT  = os.getenv("INSTRUMENT", "XAU_USD")
GRANULARITY = os.getenv("GRANULARITY", "M5")
ATR_PERIOD  = int(os.getenv("ATR_PERIOD", "14"))
ATR_MULT    = float(os.getenv("ATR_MULT", "1.0"))
LOOKBACK    = int(os.getenv("LOOKBACK", "200"))
DECIMALS    = int(os.getenv("DECIMALS", "2"))

OANDA_TOKEN = os.getenv("OANDA_API_TOKEN")
OANDA_ENV   = os.getenv("OANDA_ENV", "practice").lower()  # practice | live
TG_TOKEN    = os.getenv("TELEGRAM_BOT_TOKEN")
TG_CHAT     = os.getenv("TELEGRAM_CHAT_ID")

OANDA_HOST = ("https://api-fxpractice.oanda.com"
              if OANDA_ENV == "practice"
              else "https://api-fxtrade.oanda.com")


def skip(msg: str) -> None:
    """Exit cleanly (no CI failure) when there's nothing to do / config missing."""
    print(f"[skip] {msg}")
    sys.exit(0)


def fetch_candles(to_utc: dt.datetime, count: int):
    """Return completed candles (ascending) with start-time before `to_utc`."""
    url = f"{OANDA_HOST}/v3/instruments/{INSTRUMENT}/candles"
    params = {
        "granularity": GRANULARITY,
        "price": "M",                                   # mid OHLC
        "count": count,
        "to": to_utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    headers = {"Authorization": f"Bearer {OANDA_TOKEN}"}
    r = requests.get(url, params=params, headers=headers, timeout=30)
    r.raise_for_status()
    candles = [c for c in r.json().get("candles", []) if c.get("complete")]
    out = []
    for c in candles:
        m = c["mid"]
        out.append({
            "time": c["time"],
            "o": float(m["o"]), "h": float(m["h"]),
            "l": float(m["l"]), "c": float(m["c"]),
        })
    return out


def wilder_atr(candles, period: int):
    """Wilder's ATR (== TradingView ta.atr) at the last candle."""
    if len(candles) < period + 1:
        return None
    trs = []
    for i in range(1, len(candles)):
        h, l = candles[i]["h"], candles[i]["l"]
        prev_c = candles[i - 1]["c"]
        trs.append(max(h - l, abs(h - prev_c), abs(l - prev_c)))
    atr = sum(trs[:period]) / period            # seed = SMA of first `period` TRs
    for tr in trs[period:]:                     # Wilder recursion
        atr = (atr * (period - 1) + tr) / period
    return atr


def find_levels(candles):
    """Walk back from Bar A/Bar B to find resistance and support."""
    res = sup = None
    n = len(candles)
    max_k = min(LOOKBACK, n - 2)
    for k in range(max_k + 1):                  # Bar A = candles[-1-k], Bar B = candles[-2-k]
        if res is None and candles[-1 - k]["c"] > candles[-2 - k]["h"]:
            res = candles[-2 - k]["h"]
        if sup is None and candles[-1 - k]["c"] < candles[-2 - k]["l"]:
            sup = candles[-2 - k]["l"]
        if res is not None and sup is not None:
            break
    return res, sup


def fmt(x):
    return "n/a" if x is None else f"{x:.{DECIMALS}f}"


def build_message(date_sgt, res, sup, step):
    lines = [f"\U0001F4C5 Gold 08:00 SGT — {date_sgt}", ""]
    if res is not None and step is not None:
        lines += [
            f"\U0001F7E2 BUY entry (R): {fmt(res)}",
            f"   TP1: {fmt(res + step)}  TP2: {fmt(res + 2*step)}  TP3: {fmt(res + 3*step)}",
            "",
        ]
    else:
        lines += [f"\U0001F7E2 BUY entry (R): {fmt(res)}  (TPs n/a)", ""]
    if sup is not None and step is not None:
        lines += [
            f"\U0001F534 SELL entry (S): {fmt(sup)}",
            f"   TP1: {fmt(sup - step)}  TP2: {fmt(sup - 2*step)}  TP3: {fmt(sup - 3*step)}",
        ]
    else:
        lines += [f"\U0001F534 SELL entry (S): {fmt(sup)}  (TPs n/a)"]
    return "\n".join(lines)


def send_telegram(text: str):
    url = f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage"
    r = requests.post(url, data={"chat_id": TG_CHAT, "text": text}, timeout=30)
    if not r.ok:
        # Telegram explains the failure in the body, e.g. "chat not found"
        print(f"[error] Telegram {r.status_code}: {r.text}")
        r.raise_for_status()
    print("[ok] Telegram message sent.")


def main():
    if not OANDA_TOKEN:
        skip("OANDA_API_TOKEN not set")

    now_utc = dt.datetime.now(dt.timezone.utc)
    midnight_utc = now_utc.replace(hour=0, minute=0, second=0, microsecond=0)

    # 00:00 UTC == 08:00 SGT, same calendar date; gold trades Mon-Fri SGT
    if midnight_utc.weekday() >= 5:             # 5=Sat, 6=Sun
        skip(f"{midnight_utc.date()} is a weekend (SGT); gold closed")

    candles = fetch_candles(midnight_utc, count=LOOKBACK + ATR_PERIOD + 5)
    if len(candles) < ATR_PERIOD + 2:
        skip(f"not enough candles before {midnight_utc.isoformat()} ({len(candles)})")

    res, sup = find_levels(candles)
    atr = wilder_atr(candles, ATR_PERIOD)
    step = atr * ATR_MULT if atr is not None else None

    date_sgt = midnight_utc.date().isoformat()  # 00:00 UTC date == 08:00 SGT date
    msg = build_message(date_sgt, res, sup, step)
    print(msg)
    print(f"[info] ATR={fmt(atr)} step={fmt(step)} candles={len(candles)} "
          f"barA={candles[-1]['time']}")

    if TG_TOKEN and TG_CHAT:
        send_telegram(msg)
    else:
        print("[skip] Telegram secrets not set; printed message only (dry run).")


if __name__ == "__main__":
    main()
