-- ============================================================
--  Football Analytics Database — Schema
--  PostgreSQL
--
--  Design notes:
--   * Normalised: every real-world thing (team, competition,
--     season) is stored ONCE and referenced by id elsewhere.
--   * Per-match team stats live in their own table, one row
--     per team per match, so aggregating by team is a clean
--     GROUP BY instead of combining home + away.
-- ============================================================

-- Run this whole file once to (re)build the database structure.
-- DROP first so the script is re-runnable while we iterate.
DROP TABLE IF EXISTS match_team_stats CASCADE;
DROP TABLE IF EXISTS matches           CASCADE;
DROP TABLE IF EXISTS teams             CASCADE;
DROP TABLE IF EXISTS seasons           CASCADE;
DROP TABLE IF EXISTS competitions      CASCADE;


-- ------------------------------------------------------------
--  competitions:  e.g. "Premier League" (England)
-- ------------------------------------------------------------
CREATE TABLE competitions (
    id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name    TEXT NOT NULL,
    country TEXT NOT NULL,
    -- No two competitions should share the same name+country.
    UNIQUE (name, country)
);


-- ------------------------------------------------------------
--  seasons:  e.g. "2023/24"
-- ------------------------------------------------------------
CREATE TABLE seasons (
    id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    label TEXT NOT NULL UNIQUE          -- "2023/24"
);


-- ------------------------------------------------------------
--  teams:  e.g. "Arsenal"
-- ------------------------------------------------------------
CREATE TABLE teams (
    id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);


-- ------------------------------------------------------------
--  matches:  one row per match (the "who / when / score")
-- ------------------------------------------------------------
CREATE TABLE matches (
    id             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    competition_id INT  NOT NULL REFERENCES competitions(id),
    season_id      INT  NOT NULL REFERENCES seasons(id),
    match_date     DATE NOT NULL,

    -- Two foreign keys into the SAME table: a match links two teams.
    home_team_id   INT  NOT NULL REFERENCES teams(id),
    away_team_id   INT  NOT NULL REFERENCES teams(id),

    home_goals     INT  NOT NULL CHECK (home_goals >= 0),
    away_goals     INT  NOT NULL CHECK (away_goals >= 0),
    result         CHAR(1) NOT NULL CHECK (result IN ('H', 'D', 'A')),

    -- A team cannot play itself.
    CHECK (home_team_id <> away_team_id)
);


-- ------------------------------------------------------------
--  match_team_stats:  one row PER TEAM PER MATCH
--    (so every match produces exactly two rows here)
-- ------------------------------------------------------------
CREATE TABLE match_team_stats (
    id              INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    match_id        INT     NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    team_id         INT     NOT NULL REFERENCES teams(id),
    is_home         BOOLEAN NOT NULL,          -- TRUE = this team was at home

    goals           INT,
    shots           INT,
    shots_on_target INT,
    corners         INT,
    fouls           INT,
    yellow_cards    INT,
    red_cards       INT,

    -- A team appears at most once per match.
    UNIQUE (match_id, team_id)
);


-- ------------------------------------------------------------
--  Indexes: speed up the joins/filters we'll query on most.
-- ------------------------------------------------------------
CREATE INDEX idx_matches_home    ON matches(home_team_id);
CREATE INDEX idx_matches_away    ON matches(away_team_id);
CREATE INDEX idx_matches_season  ON matches(season_id);
CREATE INDEX idx_mts_team        ON match_team_stats(team_id);
CREATE INDEX idx_mts_match       ON match_team_stats(match_id);
