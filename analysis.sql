SET variable DATA_DIR = '/Users/anitak/Documents/Uniwerek/TSM_DtMgmt/Milano-Cortina/data/';


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

select count(*) as imported_schedules from schedules_raw;


-- ==========================================
-- LOAD MEDALLISTS DATA
-- ==========================================
-- Purpose: Import medallists and link to schedule IDs
-- Join logic: event name + date to medal-awarding sessions (event_medal > 0)
-- Output: imported_medalists_count
-- ==========================================
DROP TABLE IF EXISTS medallists_raw
;
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
FROM read_csv(getvariable('DATA_DIR') || '/medallists' ||
              '.csv', delim = ',', header = true, union_by_name = true) csv
    INNER JOIN schedules_raw s
            ON LOWER(TRIM(s.event)) = LOWER(TRIM(csv.event_name))
            AND s."day" = csv."date"
            AND s.event_medal > 0;

select count(*) as imported_medalist from medallists_raw
;

-- ==========================================
-- LOAD ATHLETES DATA (JSON PARSING)
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
DROP TABLE IF EXISTS athletes;
CREATE TABLE athletes as
select *
from read_csv(getvariable('DATA_DIR') || '/athletes.csv',
              delim = ',',
              header = true);


DROP TABLE IF EXISTS  athletes_cleaned;
CREATE TEMP TABLE athletes_cleaned AS
SELECT
    code,name,
    unnest(CAST(REPLACE                         --expand an array into a set of rows.
        (REPLACE(events, '''', '"'),            --replace single quote to double for correct json
         '"s', '''s')                           --correct double quotes in words
        AS JSON[]                               --cast this text as table with json objects
            ))->>'discipline' AS discipline,    --Get JSON object field as text
    unnest(CAST(REPLACE
        (REPLACE(events, '''', '"'), '"s', '''s') AS JSON[]
            ))->>'event' AS event
FROM athletes;


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

select * from schedules_cleaned;


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
-- QUERY 1 How many session types are in each time slot?
-- ==========================================
-- Purpose: Analyze session distribution with statistical context
-- Additional facts: percentages, rankings, seasonality, venue diversity
-- ==========================================
-- add Percentage of total
-- Rank within time slot
-- Medal density assumption (medal sessions are more valuable)
select time_slot, session_type, count (session_type)
from schedules_cleaned
group by grouping sets( (time_slot, session_type), (time_slot), (session_type))
order by time_slot, session_type DESC;



-- ==========================================
-- QUERY 2 TOP COUNTRY PER LOCATION
-- ==========================================
-- Purpose: For each venue, shows which country won the most medals in every type of event
-- Metrics: Total medal count per country per location
-- Output: Top performing country per location with medal tally
-- ==========================================
--count medals per country and loc
--rank countries within each location by medal count
--show top country per location

WITH medalsPerLocation AS (select s.location_cleaned, m.country, count(m.medal_type) as total_medals, s.event_type
                           from medallists_cleaned m
                                    inner join schedules_cleaned s on s.schedule_id = m.schedule_id
                           group by s.location_cleaned, m.country, s.event_type
                           order by s.location_cleaned, total_medals DESC),
     countries_rank AS (SELECT location_cleaned,
                               country,
                               total_medals,
                               event_type,
                               row_number() OVER (partition by ml.location_cleaned
                               ORDER BY ml.total_medals DESC) as rank
                        FROM medalsPerLocation ml
                        order by ml.location_cleaned, rank),
     top_countries AS (SELECT c.location_cleaned, c.country, c.total_medals, c.event_type
                       FROM countries_rank c
                       WHERE rank = 1)
select * from top_countries
order by event_type;

--add comment that this counts fishical medals not counted in the country rating
--porownac ilosc medali fizycznych na osobe i na kraj
--To samo dotyczy sportów drużynowych. Jeśli polska reprezentacja siatkarzy zdobyłaby złoto,
-- każdy z 12 zawodników dostałby fizyczny medal, ale w tabeli medalowej Polska dopisałaby
-- sobie tylko +1 do kolumny "Złoto".


-- ==========================================
-- QUERY 3 Which countries maximize medal returns from limited session opportunities?
-- ==========================================
-- Story: Some countries enter many sessions but win few medals.
--        Others are clinical - few sessions, high medal conversion.
-- Business value: Identify high-performance programs and broadcast scheduling
-- ==========================================

-- How many medal sessions did each country PARTICIPATE in?
-- How many medals did they actually WIN?
-- EFFICIENCY METRICS
-- Categorization




--kiedy dany zawodnik startowal, zrobic temp table PARTICIPATION =>  athele_id | event | discipline
--z jedeno jsona zrobic flatmap, wiele wpisow z jednego wpisu

select event -> 1  as d from standardized_athletes where code = '48906';

select clean_events -> '$[*]'  as d from standardized_athletes where code = '48906';



