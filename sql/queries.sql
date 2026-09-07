-- ============================================================
--  Football Analytics — Query Library
--
--  A running collection of analytical queries against the
--  'football' database. Each is labelled with the question
--  it answers. Run any one by selecting it and pressing
--  Ctrl+Enter in DBeaver.
-- ============================================================


-- ------------------------------------------------------------
-- Q1. The 10 highest-scoring matches of the season.
--     Concepts: SELECT, arithmetic in ORDER BY, LIMIT.
-- ------------------------------------------------------------
SELECT match_date, home_goals, away_goals
FROM matches
ORDER BY home_goals + away_goals DESC
LIMIT 10;


-- ------------------------------------------------------------
-- Q2. Highest-scoring matches, showing real team names.
--     Concepts: JOIN, table aliases, joining the same table
--     twice (home + away) with different aliases, column AS.
-- ------------------------------------------------------------
SELECT home.name AS home_team,
       away.name AS away_team,
       m.home_goals,
       m.away_goals
FROM matches m
JOIN teams home ON home.id = m.home_team_id
JOIN teams away ON away.id = m.away_team_id
ORDER BY m.home_goals + m.away_goals DESC
LIMIT 10;


-- ------------------------------------------------------------
-- Q3. Each team's total goals scored across the season.
--     Concepts: aggregation with SUM(), GROUP BY (one bucket
--     per team), aggregate result labelled with AS.
--     Uses match_team_stats (one row per team per match), so
--     summing per team needs no home/away juggling.
-- ------------------------------------------------------------
SELECT t.name,
       SUM(mts.goals) AS total_goals
FROM match_team_stats mts
JOIN teams t ON t.id = mts.team_id
GROUP BY t.name
ORDER BY total_goals DESC;


-- ------------------------------------------------------------
-- Q4. Teams that scored more than 70 goals in the season.
--     Concepts: HAVING filters GROUPS (after aggregation),
--     unlike WHERE which filters ROWS (before grouping).
--     The SUM() is repeated in HAVING because the total_goals
--     alias isn't available yet at HAVING time (Postgres).
-- ------------------------------------------------------------
SELECT t.name,
       SUM(mts.goals) AS total_goals
FROM match_team_stats mts
JOIN teams t ON t.id = mts.team_id
GROUP BY t.name
HAVING SUM(mts.goals) > 70
ORDER BY total_goals DESC;


-- ------------------------------------------------------------
-- Q5. Goals conceded per team (best defences first).
--     Concepts: SELF-JOIN — join match_team_stats to itself,
--     'me' vs 'opp', matched on same match_id but different
--     team_id (<>), so each team's row can see what the
--     opponent scored (= what it conceded).
-- ------------------------------------------------------------
SELECT t.name,
       SUM(opp.goals) AS goals_conceded
FROM match_team_stats me
JOIN match_team_stats opp
     ON opp.match_id = me.match_id AND opp.team_id <> me.team_id
JOIN teams t ON t.id = me.team_id
GROUP BY t.name
ORDER BY goals_conceded ASC;


-- ------------------------------------------------------------
-- Q6. The full league table, rebuilt from raw match data.
--     Concepts: SELF-JOIN (me vs opp) + CASE (if/else per row
--     to award 3/1/0 points) + SUM/COUNT aggregation +
--     multi-key ORDER BY tiebreak (points, then goal diff).
--     Reproduces the real 2023/24 Premier League table.
-- ------------------------------------------------------------
SELECT t.name,
       COUNT(*)                                     AS played,
       SUM(CASE WHEN me.goals > opp.goals THEN 3
                WHEN me.goals = opp.goals THEN 1
                ELSE 0 END)                         AS points,
       SUM(me.goals)                                AS goals_for,
       SUM(opp.goals)                               AS goals_against,
       SUM(me.goals) - SUM(opp.goals)               AS goal_diff
FROM match_team_stats me
JOIN match_team_stats opp
     ON opp.match_id = me.match_id AND opp.team_id <> me.team_id
JOIN teams t ON t.id = me.team_id
GROUP BY t.name
ORDER BY points DESC, goal_diff DESC;


-- ------------------------------------------------------------
-- Q7. League table with an automatic position number.
--     Concepts: CTE (WITH ... AS) to name a sub-result and
--     build on it; WINDOW FUNCTION RANK() OVER (ORDER BY ...)
--     which numbers rows WITHOUT collapsing them (unlike
--     GROUP BY). Ties broken by goal_diff inside OVER().
-- ------------------------------------------------------------
WITH league_table AS (
    SELECT t.name,
           SUM(CASE WHEN me.goals > opp.goals THEN 3
                    WHEN me.goals = opp.goals THEN 1
                    ELSE 0 END)            AS points,
           SUM(me.goals) - SUM(opp.goals) AS goal_diff
    FROM match_team_stats me
    JOIN match_team_stats opp
         ON opp.match_id = me.match_id AND opp.team_id <> me.team_id
    JOIN teams t ON t.id = me.team_id
    GROUP BY t.name
)
SELECT RANK() OVER (ORDER BY points DESC, goal_diff DESC) AS position,
       name,
       points,
       goal_diff
FROM league_table
ORDER BY position;
