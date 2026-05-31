# Milano-Cortina-2026-DataAnalysis

This analysis uncovers several "fun facts" about the Milano-Cortina 2026 Olympic Winter Games by querying athlete,
medallist, session, venue, and event data. Using DuckDB, I cleaned inconsistencies with string functions and CASE WHEN
bucketing, then joined multiple files to surface non‑trivial insights from session timing patterns to host‑nation
performance dynamics. Below are the several discoveries, each derived directly from SQL. Although six files were
provided, only three of them (schedules.csv, medallists.csv, and athletes.csv) were used in this analysis.

Steps:
Analyzied raw tables data in csv and chose the tables I will work on
Decided to use sequence to create Primary key 'id_schedules_sequence' in the table schedules_raw
Uploaded the data to the database using Create table.
Add data from csv using insert into, described delimiter, headers in first row and have varible for the addrees path for
the file
Already in this step remove duplicates by using Select Distict.
Did the same with the next table medallists_raw, indicate primary key from schedules_raw as a Foreign key in
medallists_raw.
I populated a raw medalists table by combining athlete medal data from a CSV with corresponding schedule/event
information.
To get schedule_id for each medal event and ensure only medal-awarding events are included I used INNER JOIN with
conditions: Case-insensitive match after trimming whitespace, Exact date match, Only events that award medals.

Then I created the 3rd table athletes from athletes.csv.
And did the cleaning of the data using unnest to expand the array into a set of rows, replace single quote to double for
correct json,correct double quotes in words,cast this text as table with json objects ,Get JSON object field as text.





### QUERY 1- Session Distribution by Time Slot and Type

This analysis breaks down how competition sessions are distributed across time slots — Morning, Afternoon, and Evening —
and by session type, distinguishing Medal Sessions from Non-Medal events. For each combination, the query reports the
number of sessions, the spread across unique venues, the range of disciplines involved, and each group's share of total
sessions within its time slot.

`GROUPING SETS` drives the structure: beyond the base time slot / session type breakdown, it produces intermediate
subtotals per time slot alone and per session type alone, surfacing in the result as `Time-slot metrics` rows. This
makes it possible to read both granular splits and rolled-up totals from the same result set without a separate
aggregation pass.

The priority flag adds an interpretive layer — Medal Sessions are marked as high value, Non-Medal as regular — making it
straightforward to assess not just when sessions are concentrated, but whether the most consequential sessions are
scheduled at times that maximize audience and operational reach.

### QUERY 2 - Venue Performance by Country Group

This analysis examines medal outcomes across competition venues, comparing Italy as the host nation against neighboring
Alpine states and the rest of the world. For each venue-group combination, the query calculates total and gold medals
won, share of medals relative to all medals available at that venue, a performance index that benchmarks actual medal
share against proportional athlete participation, and the gold rate indicating what fraction of medals won were gold.

The performance index is the key diagnostic metric: a value above 1.0 signals that a group won more medals than its
athlete presence alone would predict, while a value below 1.0 indicates underperformance relative to participation.
Combined with gold rate, this allows the report to distinguish between groups that merely appeared on the podium and
those that dominated it.

### QUERY 3 - Top Performing Country per Venue

This analysis identifies the single highest medal-winning country at each competition venue, along with the event type
hosted there. The query builds in three stages: first aggregating total medals by venue, country, and event type; then
ranking countries within each venue by medal count using a row number window function; and finally filtering to only the
top-ranked country per venue.

The result gives a clean, one-row-per-venue snapshot of which nation dominated each location, making it easy to spot
geographic patterns — whether the host nation commands its home venues, whether certain countries cluster around
specific event types, or whether medal dominance is broadly distributed across the competition landscape.

One structural note worth flagging: where two countries tie on medal count at the same venue, `ROW_NUMBER` will
arbitrarily promote one over the other. If ties are plausible in this dataset, replacing it with `RANK` or `DENSE_RANK`
and relaxing the `WHERE rank = 1` filter would surface all co-leaders rather than silently discarding them.