#!/usr/bin/env python3
"""
NBL Data Fetcher for Omarchy Shell
Fetches latest scores, schedule, and standings from ESPN API.
"""
import os
import sys
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone
import concurrent.futures

ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports/basketball/nbl"
ESPN_STANDINGS = "https://site.api.espn.com/apis/v2/sports/basketball/nbl/standings"
CACHE_DIR = os.path.expanduser("~/.local/state/omarchy/nbl")
CACHE_FILE = os.path.join(CACHE_DIR, "data.json")
USER_AGENT = "curl/8.22.0"

def http_get(url, timeout=8):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))

def fetch_all():
    # 1. Main scoreboard to get calendar and today
    main_sb = http_get(f"{ESPN_BASE}/scoreboard")
    calendar = main_sb.get("leagues", [{}])[0].get("calendar", [])
    now_local = datetime.now().astimezone()
    today_local = now_local.strftime("%Y-%m-%d")
    today_utc = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    past_dates = [d[:10].replace("-", "") for d in calendar if d[:10] < min(today_local, today_utc)][-3:]
    today_dates = list({today_local.replace("-", ""), today_utc.replace("-", "")})
    future_dates = [d[:10].replace("-", "") for d in calendar if d[:10] > max(today_local, today_utc)][:5]
    target_dates = past_dates + today_dates + future_dates

    def fetch_date(d):
        try:
            return http_get(f"{ESPN_BASE}/scoreboard?dates={d}")
        except Exception:
            return None

    raw_events = list(main_sb.get("events", []))
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
        for res in ex.map(fetch_date, target_dates):
            if res:
                raw_events.extend(res.get("events", []))

    # Deduplicate events by id
    seen_ids = set()
    events = []
    for ev in raw_events:
        eid = ev.get("id")
        if eid and eid not in seen_ids:
            seen_ids.add(eid)
            events.append(ev)

    # 2. Standings
    standings = []
    try:
        standings_raw = http_get(ESPN_STANDINGS)
        entries = standings_raw.get("standings", {}).get("entries", [])
        for entry in entries:
            team = entry.get("team", {})
            stats = {s.get("name"): s.get("displayValue") for s in entry.get("stats", []) if "name" in s}
            rank_val = stats.get("playoffSeed") or "99"
            try:
                rank = int(float(rank_val))
            except Exception:
                rank = 99
            logos = team.get("logos", [])
            logo_url = logos[0].get("href", "") if logos else ""
            standings.append({
                "rank": rank,
                "team": team.get("displayName", ""),
                "abbrev": team.get("abbreviation", ""),
                "logo": logo_url,
                "wins": stats.get("wins", "0"),
                "losses": stats.get("losses", "0"),
                "win_pct": stats.get("winPercent", ".000"),
                "diff": stats.get("pointDifferential", "0"),
                "streak": stats.get("streak", "-"),
                "pf": stats.get("pointsFor", "0"),
                "pa": stats.get("pointsAgainst", "0")
            })
        standings.sort(key=lambda x: x["rank"])
    except Exception as e:
        print(f"Warning fetching standings: {e}", file=sys.stderr)
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r") as f:
                    old_data = json.load(f)
                    standings = old_data.get("standings", [])
            except Exception:
                pass

    # 3. Classify games
    live_games = []
    recent_games = []
    upcoming_games = []

    for ev in events:
        status_type = ev.get("status", {}).get("type", {})
        state = status_type.get("state", "pre")
        comp = ev.get("competitions", [{}])[0]
        competitors = comp.get("competitors", [])
        if len(competitors) < 2:
            continue
        
        home = next((c for c in competitors if c.get("homeAway") == "home"), competitors[0])
        away = next((c for c in competitors if c.get("homeAway") == "away"), competitors[1])
        
        date_raw = ev.get("date", "")
        try:
            dt = datetime.fromisoformat(date_raw.replace("Z", "+00:00")).astimezone()
            date_str = dt.strftime("%a %d %b")
            time_str = dt.strftime("%I:%M %p")
        except Exception:
            date_str = date_raw[:10]
            time_str = ""

        venue = comp.get("venue", {}).get("fullName", "")
        city = comp.get("venue", {}).get("address", {}).get("city", "")
        venue_str = f"{venue}, {city}" if venue and city else (venue or city or "")

        game_info = {
            "id": ev.get("id"),
            "date_str": date_str,
            "time_str": time_str,
            "raw_date": date_raw,
            "state": state,
            "status_detail": status_type.get("shortDetail") or status_type.get("detail", ""),
            "venue": venue_str,
            "home": {
                "name": home.get("team", {}).get("displayName", ""),
                "abbrev": home.get("team", {}).get("abbreviation", ""),
                "score": home.get("score", "0"),
                "logo": home.get("team", {}).get("logo", ""),
                "winner": home.get("winner", False),
                "record": (home.get("records", [{}])[0].get("summary", "") if home.get("records") else "")
            },
            "away": {
                "name": away.get("team", {}).get("displayName", ""),
                "abbrev": away.get("team", {}).get("abbreviation", ""),
                "score": away.get("score", "0"),
                "logo": away.get("team", {}).get("logo", ""),
                "winner": away.get("winner", False),
                "record": (away.get("records", [{}])[0].get("summary", "") if away.get("records") else "")
            }
        }

        if state == "in":
            live_games.append(game_info)
        elif state == "post":
            recent_games.append(game_info)
        else:
            upcoming_games.append(game_info)

    recent_games.sort(key=lambda x: x["raw_date"], reverse=True)
    upcoming_games.sort(key=lambda x: x["raw_date"])

    has_live = len(live_games) > 0
    if has_live:
        g = live_games[0]
        bar_summary = f"🔴 {g['home']['abbrev']} {g['home']['score']} - {g['away']['score']} {g['away']['abbrev']} ({g['status_detail']})"
    elif recent_games:
        g = recent_games[0]
        status = g.get('status_detail') or 'Final'
        bar_summary = f"🏀 {g['home']['abbrev']} {g['home']['score']} - {g['away']['score']} {g['away']['abbrev']} ({status})"
    elif upcoming_games:
        u = upcoming_games[0]
        bar_summary = f"🏀 Next: {u['home']['abbrev']} vs {u['away']['abbrev']} ({u['date_str']} {u['time_str']})"
    else:
        bar_summary = "🏀 NBL Match Center"

    now_local = datetime.now().astimezone()
    payload = {
        "last_updated": now_local.strftime("%I:%M %p"),
        "last_updated_iso": now_local.isoformat(),
        "has_live": has_live,
        "bar_summary": bar_summary,
        "live_games": live_games,
        "recent_games": recent_games,
        "upcoming_games": upcoming_games,
        "standings": standings
    }
    return payload

def main():
    try:
        data = fetch_all()
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp_file = CACHE_FILE + ".tmp"
        with open(tmp_file, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp_file, CACHE_FILE)
        if "--json" in sys.argv or "--stdout" in sys.argv:
            print(json.dumps(data))
        elif "--print" in sys.argv or "-p" in sys.argv:
            print(f"Summary: {data['bar_summary']}")
            print(f"Live: {len(data['live_games'])}, Recent: {len(data['recent_games'])}, Upcoming: {len(data['upcoming_games'])}, Standings: {len(data['standings'])}")
        return 0
    except Exception as e:
        print(f"Error fetching NBL data: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
