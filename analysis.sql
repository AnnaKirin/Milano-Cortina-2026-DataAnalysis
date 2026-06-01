SET
variable DATA_DIR = './data/';

-- ==========================================
-- LOAD SCHEDULES DATA
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

INSERT INTO schedules_raw (start_date, end_date, "day", status, discipline, discipline_code, event, event_medal, phase,
                           gender, event_type, venue, venue_code, location, location_code, id)
SELECT DISTINCT start_date,
                end_date,
                "day",
                status,
                discipline,
                discipline_code,
                event,
                event_medal,
                phase,
                gender,
                event_type,
                venue,
                venue_code,
                location,
                location_code,
                id
FROM read_csv(getvariable('DATA_DIR') || '/schedules.csv', delim = ',', header = true, union_by_name = true);

-- ==========================================
-- LOAD MEDALLISTS DATA
-- ==========================================

DROP TABLE IF EXISTS medallists_raw;
create table medallists_raw
(
    schedule_id     integer REFERENCES schedules_raw (schedule_id),
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
("date", medal_code, medal, code, name, gender, country_code, country, discipline, discipline_code, event_name,
 schedule_id)
SELECT DISTINCT csv."date",
                csv.medal_code,
                csv.medal,
                csv.code,
                csv.name,
                csv.gender,
                csv.country_code,
                csv.country,
                csv.discipline,
                csv.discipline_code,
                csv.event_name,
                s.schedule_id
FROM read_csv(getvariable('DATA_DIR') || '/medallists.csv', delim = ',', header = true, union_by_name = true) csv
         INNER JOIN schedules_raw s
                    ON LOWER(TRIM(s.event)) = LOWER(TRIM(csv.event_name))
                        AND s."day" = csv."date"
                        AND s.event_medal > 0;


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

CREATE
OR REPLACE VIEW schedules_cleaned AS
SELECT schedule_id,
       start_date,
       end_date,
       event_medal,
       "day" as       event_date,

       CASE
           WHEN hour (start_date) BETWEEN 6 AND 11 THEN 'Morning'
        WHEN hour(start_date) BETWEEN 12 AND 17 THEN 'Afternoon'
        WHEN hour(start_date) BETWEEN 18 AND 23 THEN 'Evening'
        ELSE 'Night'
END
AS time_slot,

    trim(discipline) as discipline,
    upper(discipline_code) AS discipline_code,
    trim(event) AS event_name,
    trim(phase) AS event_phase,
    upper(event_type) AS event_type,
    CASE
        WHEN coalesce(event_medal, 0) != 0 THEN 'Medal Session'
        ELSE 'Non-Medal'
END
AS session_type,
    trim(venue) as venue,
    CASE
        WHEN location LIKE '%-%' THEN trim(split_part(location, '-', 1)) || '-' || trim(split_part(location, '-', 2))
        ELSE location
END
AS location_cleaned,
    regexp_replace(id, '-+', '', 'g') AS clean_id,

FROM schedules_raw
where status = 'FINISHED';

-- ==========================================
-- CLEAN MEDALLISTS DATA
-- ==========================================

CREATE
OR REPLACE VIEW medallists_cleaned AS
SELECT schedule_id,
       upper(trim(name))         AS athlete_name,
       code,
       upper(trim(country_code)) AS country_code,
       trim(country)             AS country,
       medal_code,
       upper(trim(medal))        AS medal_type,
       upper(discipline_code)    AS discipline_code,
       trim(discipline)          AS discipline,
       trim(event_name)          AS event_name,
       "date"                    AS award_date
FROM medallists_raw;

-- ==========================================
-- CLEAN ATHLETES DATA
-- ==========================================

DROP TABLE IF EXISTS athletes_cleaned;
CREATE
OR REPLACE VIEW athletes_cleaned AS
SELECT code,
       name,
       unnest(CAST(REPLACE
                   (REPLACE(events, '''', '"'),
                    '"s', '''s')
           AS JSON[]
            )) ->>'discipline' AS discipline, unnest(CAST (REPLACE
    (REPLACE(events, '''', '"'), '"s', '''s') AS JSON[]
    ))->>'event' AS event
FROM athletes;



-- ==========================================
-- QUERY 1 Session Distribution by Time Slot and Type
-- ==========================================

WITH session_stats AS (SELECT time_slot,
                              session_type,
                              COUNT(*)                         AS session_count,
                              COUNT(DISTINCT location_cleaned) AS unique_venues,
                              COUNT(DISTINCT discipline)       AS disciplines_involved
                       FROM schedules_cleaned
                       GROUP BY GROUPING SETS ((time_slot, session_type), (time_slot), (session_type))),
     total_in_time_slot AS (SELECT time_slot,
                                   SUM(session_count) AS total_in_time_slot
                            FROM session_stats
                            where session_type IS NOT NULL
                            GROUP BY time_slot)
SELECT ss.time_slot,
       ss.session_type,
       ss.session_count,
       ss.unique_venues,
       ss.disciplines_involved,
       ROUND(100.0 * ss.session_count / ts.total_in_time_slot, 2)|| '%' AS percentage_of_total,
       CASE
           WHEN ss.session_type = 'Medal Session' THEN 'High Value'
           WHEN ss.session_type = 'Non-Medal' THEN 'Regular'
           ELSE 'Time-slot metrics'
           END                                                    AS priority
FROM session_stats ss
         JOIN total_in_time_slot ts
              ON ss.time_slot IS NOT DISTINCT
FROM ts.time_slot
ORDER BY CASE ss.time_slot
    WHEN 'Morning' THEN 1
    WHEN 'Afternoon' THEN 2
    WHEN 'Evening' THEN 3
    ELSE 4
END
,
         ss.session_count;

-- ==========================================
-- QUERY 2 Venue Performance by Country Group
-- ==========================================

WITH venue_performance AS (SELECT sc.location_cleaned AS venue,
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
       ROUND(100.0 * vp.medals_won / vt.total_medals_at_venue, 2) || '%'  AS pct_of_venue_medals,
       -- Performance Index: actual share of medals vs expected share based on athlete participation
       ROUND(
               (vp.medals_won * 1.0 / vt.total_medals_at_venue)
                   / (vp.unique_athletes * 1.0 / vt.total_athletes_at_venue),
               2) || '%'                                                  AS performance_index,
       -- Gold Rate: proportion of medals won that are gold, signals medal quality
       ROUND(100.0 * vp.gold_medals / NULLIF(vp.medals_won, 0), 2) || '%' AS gold_rate_pct

FROM venue_performance vp
         INNER JOIN venue_totals vt ON vp.venue = vt.venue
ORDER BY vp.venue,
         CASE vp.country_group
             WHEN 'Italy (Host)' THEN 1
             WHEN 'Alpine States' THEN 2
             ELSE 3
             END;

-- ==========================================
-- QUERY 3 Top Performing Country per Venue
-- ==========================================

WITH medals_per_location AS (SELECT s.location_cleaned  AS venue,
                                  m.country,
                                  COUNT(m.medal_type) AS total_medals,
                                  s.event_type
                           FROM medallists_cleaned m
                                    INNER JOIN schedules_cleaned s ON s.schedule_id = m.schedule_id
                           GROUP BY s.location_cleaned, m.country, s.event_type),
     countries_rank AS (SELECT venue,
                               country,
                               total_medals,
                               event_type,
                               DENSE_RANK() OVER (
            PARTITION BY venue
            ORDER BY total_medals DESC
        ) AS rank
                        FROM medals_per_location),
     top_countries AS (SELECT venue,
                              country,
                              total_medals,
                              event_type,
                              rank
                       FROM countries_rank
                       WHERE rank = 1)
SELECT venue,
       country,
       total_medals,
       event_type,
       CASE
           WHEN COUNT(*) OVER (PARTITION BY venue) > 1
        THEN 'Tied'
           ELSE 'Sole Leader'
           END AS leadership_status
FROM top_countries
ORDER BY event_type, total_medals DESC;
