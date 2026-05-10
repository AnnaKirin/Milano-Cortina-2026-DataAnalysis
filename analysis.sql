SET variable DATA_DIR = '/Users/anitak/Documents/Uniwerek/TSM_DtMgmt/Milano-Cortina/data/';

DROP TABLE IF EXISTS schedules_raw;
DROP SEQUENCE id_schedules_sequence;
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
SELECT start_date, end_date, "day", status, discipline, discipline_code, event, event_medal, phase, gender, event_type, venue, venue_code, location, location_code, id
FROM read_csv(getvariable('DATA_DIR') || '/schedules.csv', delim = ',', header = true, union_by_name = true);

-- CREATE TEMP TABLE cleaned_athletes AS
-- SELECT
--     -- Cleaning athlete name (Last, First -> First Last)
--     TRIM(SPLIT_PART(athlete_name, ',', 2)) || ' ' || TRIM(SPLIT_PART(athlete_name, ',', 1)) AS full_name,
--
--     -- Cleaning country code
--     UPPER(TRIM(country_code)) AS country,
--
--     -- Bucketing sports
--     CASE
--         WHEN LOWER(sport_name) LIKE '%track%' THEN 'Outdoor'
--         WHEN LOWER(sport_name) LIKE '%swim%' THEN 'Indoor'
--         ELSE 'Other'
--     END AS environment
-- FROM athletes-raw;






DROP TABLE IF EXISTS medallists;
create table medallists
(
    schedule_id     integer REFERENCES schedules(schedule_id),
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

INSERT INTO medallists ("date", medal_code, medal, code, name, gender, country_code, country, discipline, discipline_code, event_name, schedule_id)
SELECT csv."date", csv.medal_code, csv.medal, csv.code, csv.name, csv.gender, csv.country_code, csv.country, csv.discipline, csv.discipline_code, csv.event_name, s.schedule_id
FROM read_csv(getvariable('DATA_DIR') || '/medallists.csv', delim = ',', header = true, union_by_name = true) csv
    LEFT JOIN schedules s
            ON LOWER(TRIM(s.event)) = LOWER(TRIM(csv.event_name))
            AND s."day" = csv."date"
            AND s.event_medal IN (1, 3);



--QUERY 1
select m.event_name, count(distinct m.country), s.day  from medallists as m
join schedules s on m.schedule_id = s.schedule_id
group by m.event_name, s.day
order by event_name ; --ile krajow zdobylo medali w kazdym evencie


--kiedy dany zawodnik startowal, zrobic temp table PARTICIPATION =>  athele_id | event | discipline
--z jedeno jsona zrobic flatmap, wiele wpisow z jednego wpisu


drop table  standardized_athletes;

CREATE TEMP TABLE standardized_athletes AS
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

select * from standardized_athletes;



select clean_events -> 1  as d from standardized_athletes where code = '48906';

select clean_events -> '$[*]'  as d from standardized_athletes where code = '48906';



