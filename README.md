# Milano-Cortina 2026 Olympic Winter Games: Data Analysis & Insights

This document is licensed under CC BY 4.0.

## Table of Contents

<!-- TOC -->

* [1. Introduction](#1-introduction)
* [2. Project Setup & Execution](#2-project-setup--execution)
    * [Prerequisites](#prerequisites)
    * [DuckDB Execution Workflow](#duckdb-execution-workflow)
* [3. Data Ingestion and ETL](#3-data-ingestion-and-etl)
    * [Data selection and analytical Assumptions](#data-selection-and-analytical-assumptions)
    * [Primary key strategy and initial base ingestion](#primary-key-strategy-and-initial-base-ingestion)
    * [Foreign key mapping](#foreign-key-mapping)
    * [Data Cleansing](#data-cleansing)
    * [JSON parsing](#json-parsing)
* [4. Analysis and Results](#4-analysis-and-results)
    * [QUERY 1 – Session Distribution by Time Slot and Type](#query-1--session-distribution-by-time-slot-and-type)
        * [Query Design and Logic](#query-design-and-logic)
        * [Results and Interpretation](#results-and-interpretation)
        * [Key Insights](#key-insights)
    * [QUERY 2 – Venue Performance by Country Group](#query-2--venue-performance-by-country-group)
        * [Query Design and Logic](#query-design-and-logic-1)
        * [Results and Interpretation](#results-and-interpretation-1)
        * [Key Insights](#key-insights-1)
    * [QUERY 3 – Top Performing Country per Venue](#query-3--top-performing-country-per-venue)
        * [Query Design and Logic](#query-design-and-logic-2)
        * [Results and Interpretation](#results-and-interpretation-2)
        * [Key Insights](#key-insights-2)
* [5. Discussion of Findings](#5-discussion-of-findings)
    * [Key Patterns Across Queries](#key-patterns-across-queries)
    * [Host Nation vs Regional Advantage](#host-nation-vs-regional-advantage)
    * [Sport Structure Effects (Team vs Individual Bias)](#sport-structure-effects-team-vs-individual-bias)
* [6. Conclusion](#6-conclusion)
    * [Main Takeaways](#main-takeaways)
    * [Limitations](#limitations)
    * [Final Remarks](#final-remarks)
* [Appendix A – Personal Reflection on Analytical Process](#appendix-a--personal-reflection-on-analytical-process)

<!-- TOC -->

## 1. Introduction

This analysis explores the structural, logistical, and competitive patterns of the Milano–Cortina 2026 Olympic Winter
Games. The goal is not just to describe outcomes, but to understand how scheduling decisions, venue distribution, and
competition formats shape the final medal landscape.

The analysis was implemented entirely in SQL using the DuckDB analytical database engine. The raw data was sourced from
a public Kaggle dataset containing structured information about the Milano–Cortina 2026 Olympic Winter Games, including
schedules, athletes, medal results, venues, and event metadata.

The original dataset consists of six CSV files:
`schedules.csv`, `medallists.csv`, `athletes.csv`, `medals.csv`, `venues.csv`, and `teams.csv`.

Original dataset source:
[https://www.kaggle.com/datasets/piterfm/milano-cortina-2026-olympic-winter-games/data?select=medallists.csv](https://www.kaggle.com/datasets/piterfm/milano-cortina-2026-olympic-winter-games/data?select=medallists.csv)

The analysis focuses on three main perspectives:

* how competition sessions are distributed across time and structure
* how medal outcomes vary across venues and country groupings
* how dominance changes depending on sport format and aggregation level

Overall, the project aims to show how seemingly simple questions like “who performed best” or “which country dominated”
depend heavily on how the data is structured and interpreted.

## 2. Project Setup & Execution

### Prerequisites

* DuckDB: Ensure the DuckDB CLI is installed and available in your system PATH.
* Data Sources: Raw CSV files must be located in the directory specified in the script’s configuration variables.

### DuckDB Execution Workflow

The entire ETL pipeline and analytical workflow is implemented in a single, self-contained SQL script.
To execute data transformations, schema creation, and analytical queries, run the script directly from the command line
using DuckDB:

```bash
duckdb < analysis.sql
```

## 3. Data Ingestion and ETL

### Data selection and analytical assumptions

The raw CSV data files were first analyzed to assess their structure and determine which source tables were relevant for
the analytical schema. This investigation focuses on three core relations: `schedules.csv`, `medallists.csv`, and
`athletes.csv`.

This analysis compares the total number of physical medals awarded per athlete and per country. For instance, if the
Polish men's volleyball team wins gold, each of the 12 players receives a physical
medal, but the official Olympic medal table only credits Poland with a single gold medal. Consequently, these metrics
track the absolute count of physical medals distributed rather than the standard country medal rankings. Therefore,
these results cannot be compared with the data contained in the medals.csv file.

### Primary key strategy and initial base ingestion

* Formulated a strategy to enforce relational integrity in the `schedules_raw` table by generating a unique primary
  key utilizing a database sequence (`id_schedules_sequence`).
* Initialized the physical schema structure using `CREATE TABLE` DDL statements.
* Populated the table using dynamic `INSERT INTO` execution, parameterizing the file source path
  variable while explicitly defining the delimiter and accounting for header rows.
* Eliminated duplicate records at the ingestion stage by leveraging `SELECT DISTINCT` filters.

### Foreign key mapping

* Replicated the ingestion methodology for the `medallists_raw` table, establishing a relational integrity
  constraint by referencing the `schedules_raw` primary key as a Foreign Key.
* Populated this table with raw athlete medal data.
* Implemented an `INNER JOIN` to accurately map the `schedule_id` and restrict records exclusively to medal-awarding
  events. The join predicates enforced string normalization (trimming whitespace and executing case-insensitive
  matching), exact date synchronization, and a boolean condition filtering strictly for medal-awarding criteria.
* Constructed the third core relation, `athletes`, from the source `athletes.csv`.

### Data Cleansing

The first optimization creates the schedules_cleaned view. A view was chosen instead of a temporary table because the
cleaned data did not need to be physically stored as a separate dataset and no intermediate results need to be reused.

* Time Categorization: Derives a time_slot ('Morning', 'Afternoon', 'Evening', 'Night') based on the event's start
  hour.
* Session Type Classification: Categorizes events as either a 'Medal Session' or 'Non-Medal' by evaluating the
  event_medal column (safely treating NULL values as 0).
* String Normalization: Aligns columns (discipline, event, phase, venue) by trimming whitespace and converting
  codes (discipline_code, event_type) to uppercase.
* Data Parsing: Cleans the location field by extracting the substring after a hyphen if one exists, and strips all
  hyphens from the id field using regex.
* Aliasing: Renames "day" to event_date, event to event_name, and phase to event_phase.

The second optimization establishes the medallists_cleaned view to standardize competitor and awards data.

* String Normalization: Converts text fields (name, country_code, medal, discipline_code) to
  uppercase and strips trailing/leading whitespaces.
* Aliasing: Aliases the "date" column to award_date for better contextual clarity.

### JSON parsing

* The third view athletes_cleaned was created as an exploratory transformation step to practice handling nested and
  semi-structured data. It was not used directly in the final analytical queries but served to validate the JSON parsing
  workflow.
* The process involved expanding array structures into discrete rows using the `UNNEST` function, sanitizing string
  anomalies by converting single quotes to double quotes to ensure valid JSON formatting, resolving embedded quote
  conflicts, casting the cleaned strings into formal JSON objects, and extracting targeted attributes as standard
  fields.

## 4. Analysis and Results

### QUERY 1 – Session Distribution by Time Slot and Type

#### Query Design and Logic

This analysis examines how competition sessions are distributed across three time slots (Morning, Afternoon, Evening)
and two session types (Medal vs Non-Medal). For each combination, the query returns session counts, venue diversity,
discipline coverage, and relative share within each time slot.

`GROUPING SETS` is used to generate both granular and aggregated views within a single result set, enabling comparisons
across time slots and session types without additional aggregation steps. This allows consistent evaluation of both
detailed and rolled-up scheduling patterns.

A priority flag is applied to distinguish Medal Sessions (high-value events) from Non-Medal Sessions (supporting
events), enabling interpretation of scheduling structure in terms of competitive significance.

#### Results and Interpretation

The overall schedule is heavily weighted toward Non-Medal Sessions, which account for **79.65%** (497 sessions),
compared to **20.35%** (127 sessions) for Medal Sessions.

Temporal distribution shows a clear concentration of activity in the afternoon, which records the highest total number
of sessions and venue utilization. The breakdown across time slots is as follows:

- **Morning:** 172 sessions
    - 156 Non-Medal (90.7%)
    - 16 Medal (9.3%)
    - 8 venues, 5 disciplines

- **Afternoon:** 257 sessions
    - 69 Medal (26.85%)
    - 15 venues, 12 disciplines
    - Highest operational load and highest diversity of medal events

- **Evening:** 195 sessions
    - 42 Medal (21.54%)
    - 9 venues, 11 disciplines
    - More concentrated venue usage with sustained medal presence

Comparatively, the afternoon represents the peak operational period, combining high session volume with the greatest
venue and discipline diversity. The morning is structurally oriented toward preliminary rounds, while the evening
consolidates activity into fewer venues while maintaining a meaningful share of medal events.

#### Key Insights

- **Venue utilization:** The afternoon reaches maximum infrastructure usage (21 concurrent venues across session types),
  indicating peak operational demand.
- **Discipline spread:** Medal events are most diverse in the afternoon, spanning 12 disciplines simultaneously.
- **Scheduling structure:** Medal Sessions are systematically concentrated in later time slots, aligning high-value
  events with periods of higher overall activity.
- **Resource prioritization:** The classification system clearly separates high-value (Medal) from support events,
  enabling scheduling optimization for broadcast and operational planning.

### QUERY 2 – Venue Performance by Country Group

#### Query Design and Logic

This query evaluates medal distribution at the venue level by comparing three country groupings: Italy (host nation),
Alpine States (geographically and competitively proximate winter-sport nations, which are Switzerland, Germany, Austria,
France, Slovenia, Liechtenstein, Monaco), and Other Countries. The analysis is
restricted to medal sessions to ensure that only podium-deciding events are included.

The query is implemented in two aggregation stages. A `venue_performance` CTE computes medals, gold medals, and distinct
athletes per venue and country group. A second `venue_totals` CTE calculates total medals awarded and total athlete
participation per venue, enabling normalization across differently sized delegations.

The final output derives three key metrics:

- **Medal Share (`pct_of_venue_medals`)**: Proportion of total medals at a venue won by each country group.
- **Performance Index**: Ratio of observed medal share to expected share based on athlete participation. Values above
  1.0 indicate overperformance, while values below 1.0 indicate underperformance.
- **Gold Rate (`gold_rate_pct`)**: Share of medals converted into gold, used as a proxy for competitive dominance.

Results are ordered by venue and a fixed country-group priority (Italy → Alpine States → Other Countries), enabling
consistent cross-venue comparison of host, regional, and global performance patterns.

#### Results and Interpretation

The results indicate that a pure host-nation advantage is not consistently present. Italy shows localized
overperformance at select venues but underperforms elsewhere, while Alpine States display more stable gains across
technically demanding mountain disciplines.

Italy records a performance index above 1.0 at a limited number of venues, indicating selective rather than systemic
advantage. The strongest example is Tofane, where Italy exceeds its expected medal share and converts a high proportion
of those medals into gold, representing its clearest home-field effect.

| Venue                       | Performance Index | Gold Rate | Notes                       |
|-----------------------------|-------------------|-----------|-----------------------------|
| Tofane Alpine Skiing Centre | 1.33              | 66.67%    | Strongest Italy performance |
| Cortina Sliding Centre      | 1.17              | 36.36%    | Solid, high gold rate       |
| Livigno Snow Park-Cross     | 1.18              | 20.0%     | Above expectation           |

Table 1 – Italy (host nation) over-performance

In contrast, several venues show clear underperformance, weakening the argument for a systematic home advantage. At
Stelvio, Italy’s medal share drops significantly below expectation, while similar patterns appear in biathlon and
cross-country skiing venues dominated by non-host competitors.

|                  Venue                  | Performance Index | Gold Rate |                   Notes                   |
|:---------------------------------------:|:-----------------:|:---------:|:-----------------------------------------:|
| Stelvio Ski Centre-Alpine Skiing Course | 0.67              | 0.0%      | Significant underperformance on home snow |
|        Anterselva Biathlon Arena        | 0.75              | 20.0%     | Dominated by Alpine States                |
|      Tesero Cross-Country Stadium       | 0.81              | 0.0%      | Other Countries take 70.83%               |

Table 2 – Italy (host nation) under-performance

The Alpine States group shows a more consistent pattern of overperformance across multiple venues, particularly in snow
and ice disciplines requiring environmental familiarity. Unlike Italy’s localized gains, their advantage is distributed
across several competition types, suggesting structural rather than situational strength.

A notable anomaly appears at the ice hockey arena, where Alpine States achieve the highest performance index in the
dataset but fail to convert this into gold medals, indicating high participation impact without top-tier conversion
efficiency.

|                  Venue                  | Medal Share | Performance Index | Gold Rate |                 Notes                |
|:---------------------------------------:|:-----------:|:-----------------:|:---------:|:------------------------------------:|
| Anterselva Biathlon Arena               | 43.33%      | 1.30              | 57.69%    | High volume and high quality         |
| Milano Santagiulia Ice Hockey Arena     | 20.63%      | 1.38              | 0.0%      | Highest index in dataset, zero golds |
| Stelvio Ski Centre-Alpine Skiing Course | 72.22%      | 1.24              | 38.46%    | Controls the venue outright          |
| Tofane Alpine Skiing Centre             | 44.44%      | 1.02              | 25.0%     | Present but not converting           |
| Cortina Sliding Centre                  | 73.33%      | 1.01              | 30.91%    | Volume leader, moderate gold rate    |

Table 3 – Alpine states performance

Several venues exhibit minimal regional bias, with medal distribution strongly favoring Other Countries. These
environments are primarily freestyle and indoor disciplines, where environmental familiarity plays a reduced role and
technical specialization dominates outcomes.

Freestyle snow events in particular show near-total dominance by international competitors, while curling and
cross-country skiing also demonstrate strong non-regional performance concentration.

|                        Venue                       | Medal Share | Performance Index | Gold Rate |              Notes              |
|:--------------------------------------------------:|:-----------:|:-----------------:|:---------:|:-------------------------------:|
| Livigno Snow Park-Halfpipe                         | 100.00%     | 1.0               | 33.33%    |   Zero Alpine states presence   |
| Livigno Aerials & Moguls Park-Moguls & Dual Moguls | 94.44%      | 1.08              | 35.29%    |      Near-total dominance       |
| Milano Santagiulia Ice Hockey Arena                | 79.37%      | 0.93              | 42.94%    |  High volume, strong gold rate  |
| Cortina Curling Olympic Stadium-Sheet C            | 79.10%      | 0.98              | 26.42%    | Specialized ice, neutral ground |
| Milano Ice Skating Arena-Competition Rink          | 74.76%      | 1.02              | 36.36%    |   Consistent podium presence    |

Table 4 – Other Countries performance

#### Key Insights

- **No uniform host-nation advantage:** Italy’s performance is uneven across venues, with overperformance limited to a
  small subset of locations. This indicates that home advantage is not systematic but highly context-dependent.

- **Regional consistency effect (Alpine States):** Alpine States demonstrate more stable overperformance across multiple
  venues, particularly in snow and mountain disciplines. This suggests that geographical and environmental familiarity
  is a stronger determinant than host status alone.

- **Discipline-dependent performance structure:** Technically demanding outdoor events (e.g., alpine skiing, biathlon,
  sliding) show stronger regional clustering effects, while indoor or freestyle events show weaker geographic bias.

- **Clear separation between efficiency and dominance:** Some venues (e.g., ice hockey arena) show high medal volume
  without gold conversion, indicating that participation intensity does not necessarily translate into competitive
  dominance.

- **Neutralization in freestyle disciplines:** Freestyle snow events and selected indoor competitions show minimal
  regional advantage, with medal distribution driven more by program strength than geography.

### QUERY 3 – Top Performing Country per Venue

#### Query Design and Logic

This query identifies the country achieving the highest total medal count at each competition venue and distinguishes
between sole dominance and shared leadership outcomes.

The implementation follows three aggregation stages:

- **medals_per_location CTE**: Aggregates total medals by venue, country, and event type. Each medal is weighted
  equally,
  representing total podium presence rather than medal color or event prestige.

- **countries_rank CTE**: Applies `DENSE_RANK()` partitioned by venue and ordered by total medals in descending order.
  Countries with identical totals share the same rank, ensuring that tied leaders are preserved without rank gaps.

- **top_countries CTE**: Filters for rank = 1, retaining all countries jointly leading a venue. This step explicitly
  captures competitive ties rather than forcing single-winner selection.

The final output computes a leadership status flag, defined using `COUNT(*) OVER (PARTITION BY venue)`. Venues with
more than one top-ranked country are labeled as 'Tied', while single-country leaders are labeled as 'Sole Leader'.
Results are ordered by event type and total medals to distinguish structural differences between competition formats.

#### Results and Interpretation

The analysis highlights how venue leadership patterns vary significantly depending on sport structure and team size. A
clear distinction emerges between high-volume team sports, balanced group competitions, and individually dominated
disciplines.

At a structural level, team sports exhibit strong concentration effects due to large roster sizes, producing clear
single-country dominance at several venues. Ice hockey and curling, in particular, generate the highest medal volumes
per nation due to cumulative team participation across multiple matches.

**High-Volume Team Sports**
Canada dominates the ice hockey tournament at Milano Santagiulia, accumulating 76 physical medals and representing the
clearest example of roster-driven dominance. Finland achieves similar sole-leader status in curling, though at a lower
absolute volume. Other team-oriented venues, such as biathlon and sliding, also show single-country leadership patterns.
In contrast, ski mountaineering at Stelvio demonstrates a three-way tie, reflecting a limited medal pool and higher
competitive dispersion.

|                Venue                |            Country           | Medals |   Leadership  |
|:-----------------------------------:|:----------------------------:|:------:|:-------------:|
| Milano Santagiulia Ice Hockey Arena | Canada                       | 76     | Sole Leader   |
| Cortina Curling Olympic Stadium     | Finland                      | 25     | Sole Leader   |
| Cortina Sliding Centre              | Germany                      | 18     | Sole Leader   |
| Anterselva Biathlon Arena           | France                       | 12     | Sole Leader   |
| Stelvio Ski Mountaineering Course   | Switzerland / Spain / France | 2 each | Three-way Tie |

Table 5 – Team events medals distribution

**Group and Pair Competitions**
Predazzo Ski Jumping-Large Hill (Poland, Austria, Norway – 2 Medals each): Similarly, the large hill features a
three-way tie under the DGRP type, with two physical medals awarded per leading country.

Group-based disciplines (pairs, relays, and synchronized events) show more balanced competitive outcomes, with both sole
dominance and multi-country ties depending on event structure.

The Milano Ice Skating Arena is dominated by Italy with 21 medals, reflecting strong depth in paired and team-based
skating disciplines. In contrast, ski jumping events at Predazzo demonstrate perfect competitive equilibrium, with
multiple nations sharing identical medal totals and no clear dominance emerging.

|                   Venue                   |          Country          | Medals |   Leadership  |
|:-----------------------------------------:|:-------------------------:|:------:|:-------------:|
| Milano Ice Skating Arena-Competition Rink | Italy                     | 21     | Sole Leader   |
| Predazzo Ski Jumping-Normal Hill          | Slovenia / Norway / Japan | 4 each | Three-way Tie |
| Predazzo Ski Jumping-Large Hill           | Poland / Austria / Norway | 2 each | Three-way Tie |

Table 6 – Group and pair events medals distribution

**Individual Competitions**
Individual disciplines produce the most geographically diverse leadership structure, with dominance distributed across
multiple traditional sporting powerhouses. Unlike team-based events, leadership is less concentrated and more
discipline-specific.

Norway leads endurance-based cross-country skiing, while the Netherlands dominates speed skating. Switzerland maintains
control in alpine skiing events, reflecting terrain familiarity and historical specialization. Meanwhile, Japan emerges
as a consistent leader across freestyle snow disciplines, indicating strong performance portability across venues.

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

#### Key Insights

- **Leadership is structurally driven, not purely competitive:** Venue dominance patterns are strongly influenced by
  event format (TEAM vs DGRP vs INDV) rather than geography alone.

- **Team size amplifies dominance effects:** High-roster sports (e.g., ice hockey, curling) generate concentrated “Sole
  Leader” outcomes due to cumulative medal counts per athlete, producing structural rather than performance-based
  dominance.

- **Higher incidence of ties in technical disciplines:** Events with smaller competitive margins (e.g., ski jumping,
  mountaineering) frequently result in shared leadership, indicating tighter competitive parity.

- **Clear separation between dominance types:**
    - TEAM events → high-volume single-nation dominance
    - DGRP events → mixed dominance and frequent ties
    - INDV events → distributed leadership across multiple nations

- **Discipline specialization drives individual success:** Individual competitions are characterized by country-specific
  specialization (e.g., endurance, speed skating, alpine), producing stable but siloed dominance patterns.

- **Freestyle disciplines show cross-national portability:** In contrast to geographically constrained events, freestyle
  snow disciplines exhibit transferable performance across venues, with multiple countries achieving isolated dominance
  in different sub-events.

## 5. Discussion of Findings

### Key Patterns Across Queries

Across all three queries, three consistent structural patterns emerge.

First, scheduling and performance are both highly unevenly distributed. Query 1 shows strong temporal clustering of
medal events in later time slots, while Queries 2 and 3 show spatial clustering of performance in specific venues rather
than uniform distribution across locations.

Second, competitive outcomes are strongly shaped by structure rather than randomness. Venue characteristics, event type,
and participation scale all systematically influence medal distribution patterns.

Third, dominance is rarely absolute. Instead, most patterns reflect conditional advantage—either by region, discipline
type, or competition format.

### Host Nation vs Regional Advantage

The results do not support a uniform host nation advantage. Italy shows selective overperformance at specific venues but
also clear underperformance in others, indicating that home advantage is localized rather than systemic.

In contrast, Alpine States exhibit more consistent overperformance across multiple venues and disciplines, particularly
in technically demanding winter sports. This suggests that environmental familiarity and regional training ecosystems
are more influential than host status alone.

Overall, the evidence supports a regional advantage model rather than a pure host-nation effect.

### Sport Structure Effects (Team vs Individual Bias)

Sport structure is a primary driver of observed dominance patterns. Team-based events generate concentrated outcomes due
to roster size effects, where medal counts scale with participation
rather than competitive superiority alone. This produces artificial-looking dominance in high-volume sports such as ice
hockey and curling.

Group and pair events show more balanced distributions, frequently resulting in tied leadership due to tightly clustered
competitive performance.

Individual events produce the most geographically diverse outcomes, with dominance distributed across specialized
national programs. Here, success is driven more by discipline-specific expertise than venue or structural amplification.

Overall, competition format significantly conditions how dominance appears in the dataset, often more strongly than
geography.

## 6. Conclusion

### Main Takeaways

The analysis demonstrates that medal distribution and venue dominance at Milan–Cortina 2026 are primarily shaped by
structural factors rather than uniform geographic advantage.

Key findings include:

- Strong temporal concentration of medal events in later time slots
- Absence of a consistent host nation advantage
- Stronger and more stable regional (Alpine) performance effects
- Major influence of sport structure on perceived dominance

### Limitations

This analysis is based on physical medal counts rather than official Olympic medal tables, meaning team events are
disproportionately weighted due to roster size effects.
In addition, grouping countries into broad categories (Italy, Alpine States, Other Countries) simplifies geopolitical
variation and may mask intra-group differences.
Finally, performance indices are sensitive to athlete participation estimates, which may introduce bias if participation
is unevenly distributed across events.

### Final Remarks

Rather than a single dominant nation or host advantage, the results indicate a multi-layered competitive system shaped
by geography, sport structure, and event design.
Milan–Cortina 2026 therefore appears less as a host-driven Games and more as a structurally segmented competition
landscape, where advantage depends on context rather than nationality alone.

## Appendix A – Personal Reflection on Analytical Process

This was my first time working on a full structured data analysis project, and it highlighted several important aspects
of working with real-world data.

One of the biggest takeaways is that datasets are almost never ready for analysis straight away, even if they look well
organized at first glance. In my case, the raw Olympic-style dataset had clear tables like schedules, medallists, and
athletes, but I still had to spend a lot of time figuring out how they actually connect and understand the real meaning
of the column's names. For example, I had to
explicitly build the relationship between schedules and medallists using joins, and even then I had to handle issues
like matching dates, trimming strings, and filtering only medal events. Without that step, Query 2 and Query 3 wouldn’t
have made sense at all.

Another important lesson was how much ambiguity exists in basic definitions. Things like “a medal” or “performance” are
not actually defined in the data — you have to decide what they mean. In my report, I treated medals as physical medals
per athlete, not just country results like in official Olympic tables. That completely changes interpretation. For
example, in Query 3, team sports like ice hockey produced extremely high medal counts (like Canada’s 76 medals), not
because they were necessarily “better”, but because each athlete receives a medal. If I had used the official country
medal logic instead, the results would have looked totally different.

The same issue shows up in the “performance index” from Query 2. I had to decide what “performance” means in this
analysis. I
defined it as a ratio between expected medals (based on participation) and actual medals. But that’s just one possible
interpretation — I could have weighted gold medals more heavily, or normalized differently, and the story would change.
So the results are not just “facts,” they are tied to design choices I made.

I also realized that writing SQL queries is basically the same as forming hypotheses. Every query is really just a
question about how I think the system works. For example, in Query 1 I assumed time slots (morning, afternoon, evening)
would reveal something meaningful about scheduling strategy — and that assumption shaped how I built the grouping logic.
If I had framed the question differently, I would have gotten a completely different view of the same data.

Another thing that became clear is how much the structure of the data affects the final conclusions. Whether I group by
country, venue, or athlete completely changes the story. In Query 2, grouping countries into Italy, Alpine States, and
Other Countries helped reveal clear regional patterns in performance. But if I had broken “Other Countries” into smaller
subgroups, the results might have highlighted very different dynamics between specific nations instead of a broad
regional effect. So the insight is not just in the data itself, but in how it is structured and aggregated.

Finally, the whole process was very iterative. I didn’t get the “final” version of the analysis in one go. I kept going
back to adjust joins, fix inconsistencies in naming, and rethink how I was categorizing things like medal sessions vs
non-medal sessions. A lot of the structure in Query 1, especially the time-slot breakdown, only made sense after I had
already explored the raw distribution of sessions a few times.

Overall, the main thing I learned is that data analysis is not just about running queries. It’s about deciding what
questions are actually meaningful, understanding what the data really represents, and being aware that small design
choices can completely change the story you end up telling.