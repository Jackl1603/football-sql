"""
load_data.py  —  Ingest football-data.co.uk season CSVs into the
                 normalised PostgreSQL 'football' database.

The job of this script (the core "data engineering" skill):
    flat CSVs  ->  normalised tables (teams stored once, matches link to them)

Loads every season listed in SEASONS below. Re-runnable: reloading a
season replaces its matches rather than duplicating them.

Run:  python load_data.py
"""

import os
import pandas as pd
from sqlalchemy import create_engine, text

# ------------------------------------------------------------------
# 0. Config
# ------------------------------------------------------------------
# Read the DB password from the environment, never hardcode a secret.
# Set it before running, e.g. (PowerShell):  $env:PGPASSWORD = "yourpassword"
DB_PASSWORD = os.environ.get("PGPASSWORD", "")
DB_URL = f"postgresql+psycopg2://postgres:{DB_PASSWORD}@localhost:5432/football"

COMPETITION = "Premier League"
COUNTRY     = "England"

# football-data.co.uk uses a 4-digit code per season (e.g. 2324 = 2023/24).
# "E0" is the England Premier League file. To add a season, add a line here.
SEASONS = [
    {"label": "2019/20", "code": "1920"},
    {"label": "2020/21", "code": "2021"},
    {"label": "2021/22", "code": "2122"},
    {"label": "2022/23", "code": "2223"},
    {"label": "2023/24", "code": "2324"},
]
BASE_URL = "https://www.football-data.co.uk/mmz4281/{code}/E0.csv"

engine = create_engine(DB_URL)


def get_or_create_id(conn, insert_sql, select_sql, params):
    """Insert a row if it's new, then return its id either way.

    ON CONFLICT DO NOTHING means re-running won't create duplicates —
    it just fetches the existing id.
    """
    conn.execute(text(insert_sql), params)
    return conn.execute(text(select_sql), params).scalar_one()


def load_season(conn, df, competition_id, season_label):
    """Load one season's DataFrame into the database."""
    season_id = get_or_create_id(
        conn,
        "INSERT INTO seasons (label) VALUES (:label) ON CONFLICT (label) DO NOTHING",
        "SELECT id FROM seasons WHERE label = :label",
        {"label": season_label},
    )

    # Make the load re-runnable: wipe any matches already loaded for this
    # competition+season (match_team_stats rows cascade-delete with them).
    conn.execute(
        text("DELETE FROM matches WHERE competition_id = :c AND season_id = :s"),
        {"c": competition_id, "s": season_id},
    )

    # Teams: insert each unique name once, build a name -> id map.
    team_names = pd.unique(df[["HomeTeam", "AwayTeam"]].values.ravel())
    team_id = {}
    for name in team_names:
        team_id[name] = get_or_create_id(
            conn,
            "INSERT INTO teams (name) VALUES (:name) ON CONFLICT (name) DO NOTHING",
            "SELECT id FROM teams WHERE name = :name",
            {"name": name},
        )

    match_sql = text("""
        INSERT INTO matches
            (competition_id, season_id, match_date,
             home_team_id, away_team_id, home_goals, away_goals, result)
        VALUES (:c, :s, :d, :home, :away, :hg, :ag, :res)
        RETURNING id
    """)
    stats_sql = text("""
        INSERT INTO match_team_stats
            (match_id, team_id, is_home, goals, shots,
             shots_on_target, corners, fouls, yellow_cards, red_cards)
        VALUES (:m, :team, :is_home, :goals, :shots,
                :sot, :corners, :fouls, :yellow, :red)
    """)

    for r in df.itertuples(index=False):
        match_id = conn.execute(match_sql, {
            "c": competition_id, "s": season_id, "d": r.Date,
            "home": team_id[r.HomeTeam], "away": team_id[r.AwayTeam],
            "hg": r.FTHG, "ag": r.FTAG, "res": r.FTR,
        }).scalar_one()

        conn.execute(stats_sql, {                      # HOME team's stats
            "m": match_id, "team": team_id[r.HomeTeam], "is_home": True,
            "goals": r.FTHG, "shots": r.HS, "sot": r.HST, "corners": r.HC,
            "fouls": r.HF, "yellow": r.HY, "red": r.HR,
        })
        conn.execute(stats_sql, {                      # AWAY team's stats
            "m": match_id, "team": team_id[r.AwayTeam], "is_home": False,
            "goals": r.FTAG, "shots": r.AS, "sot": r.AST, "corners": r.AC,
            "fouls": r.AF, "yellow": r.AY, "red": r.AR,
        })

    return len(df), len(team_names)


def main():
    with engine.begin() as conn:
        # competition (one row, shared by all seasons)
        competition_id = get_or_create_id(
            conn,
            "INSERT INTO competitions (name, country) VALUES (:name, :country) "
            "ON CONFLICT (name, country) DO NOTHING",
            "SELECT id FROM competitions WHERE name = :name AND country = :country",
            {"name": COMPETITION, "country": COUNTRY},
        )

        total_matches = 0
        for season in SEASONS:
            url = BASE_URL.format(code=season["code"])
            df = pd.read_csv(url)
            # Save a local copy so the project has the raw data too.
            df.to_csv(f"data/E0_{season['code']}.csv", index=False)
            # CSV dates look like 11/08/2023 (day/month/year).
            df["Date"] = pd.to_datetime(df["Date"], format="%d/%m/%Y").dt.date

            n_matches, n_teams = load_season(
                conn, df, competition_id, season["label"]
            )
            total_matches += n_matches
            print(f"  {season['label']}: {n_matches} matches, {n_teams} teams")

    print(f"Done. Loaded {total_matches} matches across {len(SEASONS)} seasons.")


if __name__ == "__main__":
    main()
