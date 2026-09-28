"""
Chart home advantage by season, straight from the database (query Q8).

Run from the project root (needs the PGPASSWORD environment variable):
    python analysis/home_advantage.py
"""

import os

import matplotlib.pyplot as plt
import pandas as pd
from sqlalchemy import create_engine

QUERY = """
SELECT s.label AS season,
       m.result,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY s.label), 1) AS pct
FROM matches m
JOIN seasons s ON s.id = m.season_id
GROUP BY s.label, m.result
ORDER BY season, m.result;
"""

SERIES = [("H", "Home win", "#2a78d6"), ("D", "Draw", "#9a9993"),
          ("A", "Away win", "#eb6834")]
INK, INK_2, SURFACE = "#0b0b0b", "#52514e", "#fcfcfb"

engine = create_engine(
    f"postgresql+psycopg2://postgres:{os.environ['PGPASSWORD']}@localhost/football")
df = pd.read_sql(QUERY, engine).pivot(index="season", columns="result", values="pct")

fig, ax = plt.subplots(figsize=(9, 4.6), facecolor=SURFACE)
width = 0.26
x = range(len(df))
for i, (code, label, colour) in enumerate(SERIES):
    positions = [p + (i - 1) * width for p in x]
    bars = ax.bar(positions, df[code], width=width - 0.02, color=colour, label=label)
    for bar, value in zip(bars, df[code]):
        ax.text(bar.get_x() + bar.get_width() / 2, value + 0.6, f"{value:.0f}",
                ha="center", fontsize=9, color=INK_2)

ax.set_facecolor(SURFACE)
ax.set_xticks(list(x), [s + ("\n(no crowds)" if s == "2020/21" else "") for s in df.index])
for side in ("top", "right"):
    ax.spines[side].set_visible(False)
for side in ("left", "bottom"):
    ax.spines[side].set_color("#d6d5d0")
ax.tick_params(colors=INK_2)
ax.yaxis.grid(True, color="#ebeae6")
ax.set_axisbelow(True)
ax.set_ylim(0, 58)
ax.set_ylabel("% of matches", color=INK_2)
ax.set_title("Home advantage by season: it vanished when fans were locked out",
             loc="left", color=INK, fontsize=13, fontweight="bold")
ax.legend(frameon=False, ncol=3, loc="upper right", labelcolor=INK_2)
fig.tight_layout()
fig.savefig("figures/home_advantage.png", dpi=150)
print(df)
