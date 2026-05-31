SET variable DATA_DIR = '/Users/anitak/Documents/Uniwerek/TSM_DtMgmt/Milano-Cortina/data/';

--Check why count schedules  table different than view  count 628 vs 624
-- ==========================================
-- LOAD SCHEDULES DATA
-- ==========================================
-- Purpose: Import raw schedule data with deduplication
-- Features: Auto-generated schedule_id via sequence
-- Note: DISTINCT removes duplicate rows from CSV
-- Output: imported_schedules_count
-- ==========================================
DROP TABLE IF EXISTS schedules_raw;
DROP SEQUENCE IF EXISTS id_schedules_sequence;
CREATE SEQUENCE id_schedules_sequence START 1; --DuckDB doesn't have SERIAL for id creating

CREATE TABLE schedules_raw
(
    schedule_id     INTEGER PRIMARY KEY DEFAULT nextval('id_schedules_sequence'),
    start_date      TIMESTAMP WITH TIME ZONE,
    end_date        TIMESTAMP WITH TIME ZONE,
    "day"           DATE,
    status          VARCHAR,
    discipline      VARCHAR,
    discipline_code VARCHAR,
    event           VARCHAR,
    event_medal     BIGINT,
    phase           VARCHAR,
    gender          VARCHAR,
    event_type      VARCHAR,
    venue           VARCHAR,
    venue_code      VARCHAR,
    location        VARCHAR,
    location_code   VARCHAR,
    id              VARCHAR
);

INSERT INTO schedules_raw (start_date, end_date, "day", status, discipline, discipline_code, event, event_medal, phase, gender, event_type, venue, venue_code, location, location_code, id)
SELECT DISTINCT start_date, end_date, "day", status, discipline, discipline_code, event, event_medal, phase, gender, event_type, venue, venue_code, location, location_code, id
FROM read_csv(getvariable('DATA_DIR') || '/schedules.csv', delim = ',', header = true, union_by_name = true);

select count(*) from schedules_raw;


-- ==========================================
-- LOAD MEDALLISTS DATA
-- ==========================================
-- Purpose: Import medallists and link to schedule IDs
-- Join logic: event name + date to medal-awarding sessions (event_medal > 0)
-- Output: imported_medalists_count
-- ==========================================
DROP TABLE IF EXISTS medallists_raw;
create table medallists_raw
(
    schedule_id     integer REFERENCES schedules_raw(schedule_id),
    "date"          DATE,
    medal_code      INTEGER,
    medal           VARCHAR,
    code            INTEGER,
    name            VARCHAR,
    gender          VARCHAR,
    country_code    VARCHAR,
    country         VARCHAR,
    discipline      VARCHAR,
    discipline_code VARCHAR,
    event_name      VARCHAR
);

INSERT INTO medallists_raw
    ("date", medal_code, medal, code, name, gender, country_code, country, discipline, discipline_code, event_name, schedule_id)
SELECT DISTINCT csv."date", csv.medal_code, csv.medal, csv.code, csv.name, csv.gender, csv.country_code, csv.country, csv.discipline, csv.discipline_code, csv.event_name, s.schedule_id
FROM read_csv(getvariable('DATA_DIR') || '/medallists.csv', delim = ',', header = true, union_by_name = true) csv
    INNER JOIN schedules_raw s
            ON LOWER(TRIM(s.event)) = LOWER(TRIM(csv.event_name))
            AND s."day" = csv."date"
            AND s.event_medal > 0;

select count(*) as imported_medalist from medallists_raw;

-- ==========================================
-- LOAD ATHLETES DATA
-- ==========================================
DROP TABLE IF EXISTS athletes;
CREATE TABLE athletes as
select *
from read_csv(getvariable('DATA_DIR') || '/athletes.csv',
              delim = ',',
              header = true);

-- ==========================================
-- CLEAN SCHEDULES DATA
-- ==========================================
-- Description: Creates cleaned, deduplicated schedule view
-- Filters: FINISHED events only
-- Enriches: Adds time slot, medal session flag, cleaned location and ID
-- ==========================================
CREATE OR REPLACE VIEW schedules_cleaned AS
SELECT
    schedule_id,
    start_date,
    end_date,
    event_medal,
    "day" as event_date,

    CASE
        WHEN hour(start_date) BETWEEN 6 AND 11 THEN 'Morning'
        WHEN hour(start_date) BETWEEN 12 AND 17 THEN 'Afternoon'
        WHEN hour(start_date) BETWEEN 18 AND 23 THEN 'Evening'
        ELSE 'Night'
    END AS time_slot,

    trim(discipline) as discipline,
    upper(discipline_code) AS discipline_code,
    trim(event) AS event_name,
    trim(phase) AS event_phase,
    upper(event_type) AS event_type,
    CASE
        WHEN coalesce(event_medal, 0) != 0 THEN 'Medal Session' --to treat NULL as 0 first
        ELSE 'Non-Medal'
    END AS session_type,
    trim(venue) as venue,
    CASE
        WHEN location LIKE '%-%' THEN trim(split_part(location, '-', 2))
        ELSE location
    END AS location_cleaned,
    regexp_replace(id, '-+', '', 'g') AS clean_id,

FROM schedules_raw
where status = 'FINISHED';

select count(*) from schedules_cleaned;

-- ==========================================
-- CLEAN MEDALLISTS DATA
-- ==========================================
-- Purpose: Standardize medallist data for reporting
-- Operations:
--   - Uppercase: athlete_name, country_code, medal_type, discipline_code
--   - Trim whitespace from all text fields
--   - Rename: date → award_date for clarity
-- Output: Cleaned view for medal analysis and duplicate detection
-- Validation: Shows athlete-country combinations with medal counts
-- ==========================================
CREATE OR REPLACE VIEW medallists_cleaned AS
SELECT
    schedule_id,
    upper(trim(name)) AS athlete_name,
    code,
    upper(trim(country_code)) AS country_code,
    trim(country) AS country,
    medal_code,
    upper(trim(medal)) AS medal_type,
    upper(discipline_code) AS discipline_code,
    trim(discipline) AS discipline,
    trim(event_name) AS event_name,
    "date" AS award_date
FROM medallists_raw;

select count(*) from medallists_cleaned;

-- ==========================================
-- CLEAN ATHLETES DATA
-- ==========================================
-- Purpose: Expand nested JSON arrays in athletes table into relational format
-- Source: athletes table with 'events' column containing JSON array
-- Transformations:
--   - Fix JSON formatting: replace single quotes with double quotes
--   - Handle apostrophes: preserve '''s' contractions (e.g., "Men's")
--   - Unnest JSON array: one row per discipline/event combination per athlete
-- Output: Flattened athlete-event relationships for further analysis
-- Example: Athlete with 3 events → 3 rows
-- ==========================================

DROP TABLE IF EXISTS  athletes_cleaned;
CREATE TEMP TABLE athletes_cleaned AS
SELECT
    code,name,
    unnest(CAST(REPLACE
        (REPLACE(events, '''', '"'),
         '"s', '''s')
        AS JSON[]
            ))->>'discipline' AS discipline,
    unnest(CAST(REPLACE
        (REPLACE(events, '''', '"'), '"s', '''s') AS JSON[]
            ))->>'event' AS event
FROM athletes;



-- ==========================================
-- QUERY 1 How many session types are in each time slot?
-- ==========================================
-- Purpose: Analyze session distribution with statistical context
-- Additional facts: session's amount, venue diversity, involved disciplines,
-- percentages, scheduling priority for TV
-- ==========================================

WITH session_stats AS (
    SELECT
        time_slot,
        session_type,
        COUNT(*) AS session_count,
        COUNT(DISTINCT location_cleaned) AS unique_venues,
        COUNT(DISTINCT discipline) AS disciplines_involved
    FROM schedules_cleaned
    GROUP BY GROUPING SETS ((time_slot, session_type), (time_slot), (session_type))
),
     total_in_time_slot AS (SELECT time_slot,
                               SUM(session_count) AS total_in_time_slot
                        FROM session_stats
                        where session_type IS NOT NULL
                        GROUP BY time_slot
)
SELECT
     ss.time_slot,
    ss.session_type,
    ss.session_count,
    ss.unique_venues,
    ss.disciplines_involved,
    ROUND(100.0 * ss.session_count / ts.total_in_time_slot, 2) AS percentage_of_total,
    CASE
        WHEN ss.session_type = 'Medal Session' THEN '★ High Value'
        WHEN ss.session_type = 'Non-Medal' THEN '☆ Regular'
        ELSE 'Time-slot metrics'
        END AS priority
FROM session_stats ss
JOIN total_in_time_slot ts
ON ss.time_slot IS NOT DISTINCT FROM ts.time_slot
ORDER BY CASE ss.time_slot
             WHEN 'Morning' THEN 1
             WHEN 'Afternoon' THEN 2
             WHEN 'Evening' THEN 3
             ELSE 4
             END,
         ss.session_count;

-- ==========================================
-- QUERY 2 Venue Familiarity Advantage
-- ==========================================
-- Purpose: Quantify home field advantage by comparing medal performance
--          of host country (Italy) vs neighboring countries vs others
--          across different Olympic venues
-- Metrics:
--   - Total medals won per country group at each venue
--   - Gold medal count per country group
--   - Percentage share of venue's total medals by each group
--   - Medals per unique athlete (efficiency)
--   - Performance index (ratio of actual medals to expected based on participation)
-- Output:
--   - Table showing each venue with breakdown by country group
--   - Highlights venues where host country has strongest advantage
--   - Identifies if neighboring countries share the advantage
--   - Reveals venues with neutral/no home advantage


WITH venue_performance AS (SELECT sc.location_cleaned                                AS venue,
                                  CASE
                                      WHEN mc.country_code = 'ITA' THEN 'Italy (Host)'
                                      WHEN mc.country_code IN ('SUI', 'GER', 'AUT', 'FRA', 'SLO', 'LIE', 'MON')
                                          THEN 'Alpine States'
                                      ELSE 'Other Countries'
                                      END                                            AS country_group,
                                  COUNT(*)                                           AS medals_won,
                                  COUNT(CASE WHEN mc.medal_type = 'GOLD' THEN 1 END) AS gold_medals,
                                  COUNT(DISTINCT mc.code)                            AS unique_athletes
                           FROM medallists_cleaned mc
                                    INNER JOIN schedules_cleaned sc ON mc.schedule_id = sc.schedule_id
                           WHERE sc.session_type = 'Medal Session'
                           GROUP BY sc.location_cleaned, country_group),
     venue_totals AS (SELECT venue,
                             SUM(medals_won)      AS total_medals_at_venue,
                             SUM(unique_athletes) AS total_athletes_at_venue
                      FROM venue_performance
                      GROUP BY venue)
SELECT vp.venue,
       vp.country_group,
       vp.medals_won,
       vp.gold_medals,
       ROUND(100.0 * vp.medals_won / vt.total_medals_at_venue, 2)  AS pct_of_venue_medals,
       -- Performance Index: actual share of medals vs expected share based on athlete participation
       ROUND(
               (vp.medals_won * 1.0 / vt.total_medals_at_venue)
                   / (vp.unique_athletes * 1.0 / vt.total_athletes_at_venue),
               2)    ||'%'                                              AS performance_index,
       -- Gold Rate: proportion of medals won that are gold, signals medal quality
       ROUND(100.0 * vp.gold_medals / NULLIF(vp.medals_won, 0), 2)||'%' AS gold_rate_pct

FROM venue_performance vp
         INNER JOIN venue_totals vt ON vp.venue = vt.venue
ORDER BY vp.venue,
         CASE vp.country_group
             WHEN 'Italy (Host)' THEN 1
             WHEN 'Alpine States' THEN 2
             ELSE 3
             END;
-- ==========================================
-- QUERY 3 TOP COUNTRY PER LOCATION
-- ==========================================
-- Purpose: For each venue, shows which country won the most medals in every type of event
-- Metrics: Total medal count per country per location
-- Output: Top performing country per location with medal tally
-- ==========================================
--TODO USUNAC notatki
-- count medals per country and loc
--rank countries within each location by medal count
--show top country per location

WITH medalsPerLocation AS (select s.location_cleaned as venue, m.country, count(m.medal_type) as total_medals, s.event_type
                           from medallists_cleaned m
                                    inner join schedules_cleaned s on s.schedule_id = m.schedule_id
                           group by s.location_cleaned, m.country, s.event_type
                           order by s.location_cleaned, total_medals DESC),
     countries_rank AS (SELECT venue,
                               country,
                               total_medals,
                               event_type,
                               row_number() OVER (partition by ml.venue
                               ORDER BY ml.total_medals DESC) as rank
                        FROM medalsPerLocation ml
                        order by ml.venue, rank),
     top_countries AS (SELECT c.venue, c.country, c.total_medals, c.event_type
                       FROM countries_rank c
                       WHERE rank = 1)
select * from top_countries
order by event_type;

--add comment that this counts fishical medals not counted in the country rating
--porownac ilosc medali fizycznych na osobe i na kraj
--To samo dotyczy sportów drużynowych. Jeśli polska reprezentacja siatkarzy zdobyłaby złoto,
-- każdy z 12 zawodników dostałby fizyczny medal, ale w tabeli medalowej Polska dopisałaby
-- sobie tylko +1 do kolumny "Złoto".





--kiedy dany zawodnik startowal, zrobic temp table PARTICIPATION =>  athele_id | event | discipline
--z jedeno jsona zrobic flatmap, wiele wpisow z jednego wpisu

select event -> 1  as d from standardized_athletes where code = '48906';

select clean_events -> '$[*]'  as d from standardized_athletes where code = '48906';



