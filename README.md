# Milano-Cortina-2026-DataAnalysis

This analysis uncovers several "fun facts" about the Milano-Cortina 2026 Olympic Winter Games by querying athlete,
medallist, session, venue, and event data. Using DuckDB, I cleaned inconsistencies with string functions and CASE WHEN
bucketing, then joined multiple files to surface non‑trivial insights from session timing patterns to host‑nation
performance dynamics. Below are the several discoveries, each derived directly from SQL. Although six files were
provided, only three of them (schedules.csv, medallists.csv, and athletes.csv) were used in this analysis.

## Data Ingestion and ETL

1. Data discovery and selection
   Analyzed the raw CSV data files to assess their structure and selected the target source tables required for the
   schema development.

2. Primary key strategy and initial base ingestion
    * Formulated a strategy to enforce relational integrity in the `schedules_raw` table by generating a unique primary
      key utilizing a database sequence (`id_schedules_sequence`).
    * Initialized the physical schema structure using `CREATE TABLE` DDL statements.
    * Populated the table using dynamic `INSERT INTO` execution, parameterizing the file source path
      variable while explicitly defining the delimiter and accounting for header rows.
    * Eliminated duplicate records at the ingestion stage by leveraging `SELECT DISTINCT` filters.

3. Foreign key mapping
    * Replicated the ingestion methodology for the `medallists_raw` table, establishing a relational integrity
      constraint by referencing the `schedules_raw` primary key as a Foreign Key.
    * Populated this table with raw athlete medal data.
    * Implemented an `INNER JOIN` to accurately map the `schedule_id` and restrict records exclusively to medal-awarding
      events. The join predicates enforced string normalization (trimming whitespace and executing case-insensitive
      matching), exact date synchronization, and a boolean condition filtering strictly for medal-awarding criteria.
    * Constructed the third core relation, `athletes`, from the source `athletes.csv`.

4. Data Cleansing

   The first optimization creates the schedules_cleaned view. A view was chosen over a temporary table because it
   provides dynamic, real-time access to the most up-to-date raw data without consuming physical storage or persisting
   across a single database session.
    * Time Categorization: Derives a time_slot ('Morning', 'Afternoon', 'Evening', 'Night') based on the event's start
      hour.
    * Session Type Classification: Categorizes events as either a 'Medal Session' or 'Non-Medal' by evaluating the
      event_medal column (safely treating NULL values as 0).
    * String Standardization: Aligns columns (discipline, event, phase, venue) by trimming whitespace and converting
      codes (
      discipline_code, event_type) to uppercase.
    * Data Parsing: Cleans the location field by extracting the substring after a hyphen if one exists, and strips all
      hyphens from the id field using regex.
    * Aliasing: Renames "day" to event_date, event to event_name, and phase to event_phase.

   The second optimization establishes the medallists_cleaned view to standardize competitor and awards data.
    * String Normalization: Converts high-cardinality text fields (name, country_code, medal, discipline_code) to
      uppercase and strips trailing/leading whitespaces.
    * Semantic Renaming: Aliases the ambiguous "date" column to award_date for better contextual clarity.

5. JSON parsing
    * The third view `athletes_cleaned` was created and data cleansing executed on unstructured attributes by utilizing
      the `UNNEST` function to expand array
      structures into discrete rows.
    * Sanitized string anomalies by converting single quotes to double quotes to guarantee valid JSON validation,
      resolving embedded quote conflicts, casting the resulting text into formal JSON object structures, and extracting
      targeted object attributes as standard text fields.

## Data Transformation & Execution

Below are some important notes on how the raw data was interpreted and used:
This analysis compares the total number of physical medals awarded per athlete and per country. The same logic applies
to team sports; for instance, if the Polish men's volleyball team wins gold, each of the 12 players receives a physical
medal, but the official Olympic medal table only credits Poland with a single gold medal. Consequently, these metrics
track the absolute count of physical medals distributed rather than the standard country medal rankings. Therefore,
these results cannot be compared with the data contained in the medals.csv file.

### QUERY 1 – Session Distribution by Time Slot and Type

This analysis breaks down how competition sessions are distributed across time slots — Morning, Afternoon, and Evening —
and by session type, distinguishing Medal Sessions from Non-Medal events. For each combination, the query reports the
number of sessions, the spread across unique venues, the range of disciplines involved, and each group's share of total
sessions within its time slot.

`GROUPING SETS` produces intermediate subtotals per time slot alone and per session type alone, surfacing in the result
as `Time-slot metrics` rows. This
makes it possible to read both granular splits and rolled-up totals from the same result set without a separate
aggregation pass.

The priority flag adds an interpretive layer — Medal Sessions are marked as high value, Non-Medal as regular — making it
straightforward to assess not just when sessions are concentrated, but whether the most consequential sessions are
scheduled at times that maximize audience and operational reach.

### QUERY 2 – Venue Performance by Country Group

This query analyzes medal distribution across competition venues by comparing three geopolitical groupings: Italy (the
host nation), Alpine States (neighboring countries with similar winter sports traditions), and Other Countries. The
analysis is restricted to medal sessions only, ensuring that only podium‑deciding events are considered.

The query proceeds in two stages. First, a venue_performance CTE aggregates medals won, gold medals, and
distinct athletes per venue and country group. Second, a `venue_totals` CTE computes total medals
awarded and total athletes competing at each venue.

The final `SELECT` then calculates three performance metrics:

* Percentage of venue medals (`pct_of_venue_medals`): Each group's share of all medals awarded at a given venue,
  expressed
  as a percentage.
* Performance Index: A ratio comparing the group's actual medal share to its expected medal share based on athlete
  participation. A value > 1.0 indicates overperformance (more medals than athlete presence predicts); < 1.0 signals
  underperformance. This metric controls for varying numbers of athletes per group across venues.
* Gold Rate (`gold_rate_pct`): The proportion of the group's medals at that venue that were gold, serving as a proxy for
  medal quality and competitive dominance.

Results are sorted first by venue name, then by a custom priority order placing Italy first, Alpine
States second, and Other Countries third, facilitating direct comparison of host vs. neighbors vs. rest of the world at
each competition site.

### QUERY 3 – Top Performing Country per Venue

This query identifies the nation achieving the highest medal volume at each competition venue, explicitly
differentiating between singular dominance and competitive ties.

The query executes in three logical stages:

* medalsPerLocation CTE: Aggregates total medals won by venue, country, and event type. Each medal counts equally toward
  the total, reflecting overall podium presence rather.

* countries_rank CTE: Applies `DENSE_RANK()` partitioned by venue, ordering by total medals descending. Countries with
  identical medal counts receive the same rank. The use of `DENSE_RANK()` ensures that ties
  produce consecutive rankings without gaps, while still allowing all co‑leaders to be identified as rank = 1.

* top_countries CTE: Filters to only countries achieving rank 1 at their respective venues. This step retains all tied
  nations when multiple share the top medal count.

The outer query adds a `leadership_status` column using a windowed `COUNT(*) OVER (PARTITION BY venue)`. If
more than one row exists for a venue (i.e., multiple countries share the top medal count), the status is labeled 'Tied';
otherwise, it is 'Sole Leader'. Results are ordered by event type and then by total medals descending, allowing
to observe which disciplines tend toward single‑nation dominance versus competitive parity.

## Key Findings

This chapter presents the key findings derived from each query, revealing several "fun facts" about the Milano-Cortina
2026 Olympic Winter Games through systematic analysis of athletes, medallists, and session data. The following
subsections
detail the insights obtained from each of the three analytical queries.

### Query 1 results

An analysis of the first dataset reveals that the competition schedule is heavily weighted toward non-medal sessions,
which account for approximately **79.65%** of the total event count (497 sessions). In contrast, medal-awarding sessions
represent **20.35%** (127 sessions) of the global schedule.

Temporally, the competition volume peaks during the afternoon, which handles the largest share of both total sessions
and unique venue operations. Conversely, morning blocks are primarily reserved for preliminary, non-medal rounds.
The morning contains a total of 172 sessions, meaning it is heavily skewed toward preliminary
rounds. Non-medal sessions dictate **90.7%** (156 sessions) of this block. Only 16 medal sessions occur in the morning,
representing just **9.3%** of the morning's schedule. These finals are highly concentrated, utilizing only 8 unique
venues and spanning 5 disciplines.

The afternoon is the most active period of the schedule, capturing 257 total sessions. It serves as the primary window
for high-value events, hosting **69 medal sessions**, which
constitute **26.85%** of the afternoon's programmatic inventory. This block maximizes logistics, spreading operations
across 15 unique venues and 12 distinct disciplines.

The evening block concentrates activity into fewer venues. It displays a
strong density of high-value finals, with **42 medal sessions** making up *
*21.54%** of the evening schedule. These events are structurally consolidated, operating across 9 unique venues, but
maintaining a wide disciplinary breadth (11 disciplines).

**Operational and Logistical Insights**
: Venue Utilization Balance: Non-medal events show broad spatial distribution, peaking at 23 unique venues globally.
  When evaluating specific time-slots, venue operations reach their maximum ceiling in the afternoon (21 unique venues
  active across all session types), reflecting peak logistical demand for staff, broadcasting, and security
  infrastructure.
: Discipline Diversity: The diversity of sports disciplines peaks uniformly across the afternoon and evening time
  blocks. The afternoon medal sessions feature the highest variety, involving 12 separate sports disciplines
  simultaneously competing for podium finishes.
: Prioritization Mapping: The dataset successfully categorizes resource allocation using a dual-tier priority
  framework. All rows explicitly designated as a "Medal Session" map to a **High Value** priority tier, providing clear
  data signals for broadcast scheduling and premium resource provisioning.

### Query 2 results

Evidence for a pure host-nation advantage is mixed, while regional Alpine familiarity appears consistently important.
Italy does not dominate across the board, it
punches above its participation weight at select venues while underperforming at others. The more consistent story is
that Alpine States collectively outperform their participation share at technically demanding mountain venues,
suggesting regional familiarity matters more than strict host-nation status.

Italy shows a genuine performance index above 1.0 at only a handful of venues (Table 1). At Tofane, Italy wins more than
its athlete share predicts and converts two-thirds of those medals to gold. It is the clearest expression of home
advantage in the entire dataset.

| Venue                       | Performance Index | Gold Rate | Notes                       |
|-----------------------------|-------------------|-----------|-----------------------------|
| Tofane Alpine Skiing Centre | 1.33              | 66.67%    | Strongest Italy performance |
| Cortina Sliding Centre      | 1.17              | 36.36%    | Solid, high gold rate       |
| Livigno Snow Park-Cross     | 1.18              | 20.0%     | Above expectation           |

Table 1 – Italy (Host) over-performance

However, on the other venues the picture reverses sharply (Table 2). Stelvio is the most damaging result for the home
advantage thesis — an Italian alpine skiing venue where Italy captures only 11% of medals with a performance index well
below 1.0.

|             Venue            | Performance Index |                   Notes                   |
|:----------------------------:|:-----------------:|:-----------------------------------------:|
| Stelvio Ski Centre-Alpine Skiing Course           | 0.67              | Significant underperformance on home snow |
| Anterselva Biathlon Arena    | 0.75              | Dominated by Alpine States                |
| Tesero Cross-Country Stadium | 0.81              | Other Countries take 70.83%               |

Table 2 – Italy (Host) under-performance

Alpine neighbors are the more structurally advantaged group across mountain disciplines. Unlike Italy's selective edges,
their overperformance is spread consistently across venue types — from biathlon to sliding to ice hockey (Table 3). The
ice hockey arena result deserves particular attention. Alpine States record the single highest performance index of any
group at any venue 1.38, yet convert none of those medals to gold. This is the clearest example in the dataset of
volume without dominance.
At Anterselva and Stelvio, the story is more straightforward — high index combined with strong gold rates confirms that
Alpine States used well their regional familiarity with geography and snow profiles.

| Venue                               | Medal Share | Performance Index | Gold Rate | Reading                              |
|:------------------------------------|:-----------:|:-----------------:|:---------:|--------------------------------------|
| Anterselva Biathlon Arena           | 43.33%      | 1.30              | 57.69%    | High volume and high quality         |
| Milano Santagiulia Ice Hockey Arena | 20.63%      | 1.38              | 0.0%      | Highest index in dataset, zero golds |
| Stelvio Ski Centre-Alpine Skiing Course | 72.22%      | 1.24              | 38.46%    | Controls the venue outright          |
| Tofane Alpine Skiing Centre         | 44.44%      | 1.02              | 25.0%     | Present but not converting           |
| Cortina Sliding Centre              | 73.33%      | 1.01              | 30.91%    | Volume leader, moderate gold rate    |

Table 3 – Alpine states performance

Several environments showed a complete absence of local or regional bias, leaving international fields to dominate the
podium tallies (Table 4). Across nearly every freestyle discipline, international teams captured between 73.33% and
100.0% of the medals. The "Other Countries" swept 79.10% of the medals at Cortina Curling Olympic Stadium, showing that
specialized stadium sheet ice remains universally neutral. International teams dominated Tesero Cross-Country Skiing
Stadium as well,
taking 70.83% of the podium spots (51 medals) and achieving a 47.06% Gold Rate, keeping both Italy and the
Alpine States significantly below performance baselines.

| Venue                                   | Other Countries Medal Share |
|:----------------------------------------|-----------------------------|
| Livigno Snow Park-Halfpipe              | 100.00% (12 Medals)         |
| Livigno Aerials & Moguls Park-Moguls    | 94.44% (17 Medals)          |
| Milano Santagiulia Ice Hockey Arena     | 79.37% (177 Medals)         |
| Cortina Curling Olympic Stadium-Sheet C | 79.10% (53 Medals)          |
| Milano Ice Skating Arena-Competitio     | 74.76% (77 Medals)          |

Table 4 – Other Countries performance

### Query 3 results

The dataset maps which nations control specific athletic venues based on their total medal yields, using the absolute
count of physical medals awarded. Because this methodology counts
every individual medal handed out, team and large-group disciplines skew significantly higher in total volume than
individual events. A clear trend emerges
showing that while massive arena-based sports (such as Ice Hockey or Curling) produce a singular, high-volume "Sole
Leader", technical outdoor events (like Ski Jumping and Ski Mountaineering) are highly prone to multi-nation competitive
ties.
The query identifies "Sole Leaders" versus "Tied" nations across three event types: TEAM (multi-athlete squads), DGRP (
Direct Group/Relay/Pairs), and INDV (Individual competitions).

**High-Volume Team Sports**
: Canada stands as the Sole Leader at Milano Santagiulia Ice Hockey Arena. The count of 76 physical medals highlights
the
compounding effect of large roster sizes across multiple team categories.
Finland claims the Sole Leader status at Cortina Curling Olympic Stadium-Sheet C. While curling
rosters are smaller than hockey squads, the physical count reflects multiple team members over the duration of the
tournament sheets. The only exception is ski mountaineering at Stelvio — a low-volume, emerging Olympic discipline where
the medal pool is
too shallow to produce a clear national leader. (Table 5)

|                Venue                |            Country           | Medals |   Leadership  |
|:-----------------------------------:|:----------------------------:|:------:|:-------------:|
| Milano Santagiulia Ice Hockey Arena | Canada                       | 76     | Sole Leader   |
| Cortina Curling Olympic Stadium     | Finland                      | 25     | Sole Leader   |
| Cortina Sliding Centre              | Germany                      | 18     | Sole Leader   |
| Anterselva Biathlon Arena           | France                       | 12     | Sole Leader   |
| Stelvio Ski Mountaineering Course   | Switzerland / Spain / France | 2 each | Three-way Tie |

Table 5 – Team events medals distribution

**Group and Pair Competitions**
:   This category encompasses pairs, duos, and specialized group scoring systems where multiple athletes stand on the
podium together.

Milano Ice Skating Arena-Competition Rink (Italy – 21 Medals): The host nation emerged as a Sole Leader with a
commanding 21 physical medals. This high volume points to dominant roster depth in short track relays or figure skating
team/pair events.

Predazzo Ski Jumping-Normal Hill (Slovenia, Norway, Japan – 4 Medals each): This venue demonstrates a clear competitive
equilibrium, resulting in a three-way Tied leadership status. Each nation walked away with four physical medals,
indicating
a dead heat in team-based hill events.

Predazzo Ski Jumping-Large Hill (Poland, Austria, Norway – 2 Medals each): Similarly, the large hill features a
three-way tie under the DGRP type, with two physical medals awarded per leading country.

|                   Venue                   |          Country          | Medals |   Leadership  |
|:-----------------------------------------:|:-------------------------:|:------:|:-------------:|
| Milano Ice Skating Arena-Competition Rink | Italy                     | 21     | Sole Leader   |
| Predazzo Ski Jumping-Normal Hill          | Slovenia / Norway / Japan | 4 each | Three-way Tie |
| Predazzo Ski Jumping-Large Hill           | Poland / Austria / Norway | 2 each | Three-way Tie |

Table 6 – Group and pair events medals distribution

**Individual Competitions**
: Individual disciplines produce the most geographically diverse leaderboard. Traditional powerhouses hold their
historic disciplines — Norway in cross-country, Netherlands in speed skating, Switzerland in alpine — while Japan
emerges as an unexpected multi-venue leader across freestyle snow disciplines.

Norway asserts its classic endurance hegemony as the Sole Leader, accumulating 13 individual physical medals across
various distances. The Dutch speed skating contingent completely controlled the
Milano Speed Skating Stadium, capturing 12 individual medals to take Sole Leader status. Switzerland used its alpine
familiarity to lock down 6 individual medals, standing alone at the top of the Stelvio Ski Centre-Alpine Skiing Course
leaderboard.

Japan's three freestyle wins at Livigno (halfpipe, big air, slopestyle) is the standout pattern. These victories
represent a consistent Japanese program that travels to European venues and
wins regardless of geography.

|                        Venue                       |    Country    | Medals |  Leadership |
|:--------------------------------------------------:|:-------------:|:------:|:-----------:|
| Tesero Cross-Country Skiing Stadium                | Norway        | 13     | Sole Leader |
| Milano Speed Skating Stadium                       | Netherlands   | 12     | Sole Leader |
| Stelvio Ski Centre-Alpine Skiing Course            | Switzerland   | 6      | Sole Leader |
| Livigno Aerials & Moguls Park-Moguls & Dual Moguls | United States | 6      | Sole Leader |
| Livigno Aerials & Moguls Park-Aerials              | China         | 4      | Sole Leader |
| Livigno Snow Park-Big Air                          | Japan         | 3      | Sole Leader |
| Livigno Snow Park-Halfpipe                         | Japan         | 3      | Sole Leader |
| Livigno Snow Park-Slopestyle                       | Japan         | 3      | Sole Leader |

Table 7 – Individual competition events medals distribution

## Project Summary

The 2026 Winter Olympics schedule was engineered for impact — 80% of sessions reserved for build-up, with medal moments
concentrated when audiences peaked — but the host nation Italy captured only a fraction of the advantage that implied.
Genuine home edges appeared at just three venues: Tofane Alpine Skiing Centre, where Italy converted two-thirds of its
medals to gold, Cortina Sliding Centre, and Livigno Cross. Elsewhere, the Alpine neighborhood proved the more consistent
beneficiary, with Switzerland, Austria, France, and Germany collectively outperforming their participation share across
biathlon, alpine skiing, and sliding — disciplines where years of regional training proximity matter more than a flag on
the scoreboard. That regional logic collapsed entirely in the freestyle disciplines, where Japan won halfpipe, big air,
and slopestyle at Livigno, the United States took moguls, and China claimed aerials — programs built on pipelines that
no host advantage can touch. Norway assembled quiet dominance in cross-country, the Netherlands controlled speed
skating, and Canada closed the story with the single loudest statement of the Games: 76 medals at the ice hockey arena,
a number so large it distorts any aggregate table that includes it. Milan-Cortina 2026 was not Italy's Games — it was
the Alps' Games, contested on neutral ground wherever snow gave way to ice, and punctuated by Canada reminding everyone
that team sports write their own rules.