/* ====================================================================
PROJECT: Maji Ndogo Water Crisis Analysis
AUTHOR: Judy Madonsela
DATE: 2026
TOOL: MySQL Workbench
DESCRIPTION: Analysis of 60,000 water access survey records across 
provinces, towns and water sources to inform government restoration 
decisions

CHAPTERS:
   1. Database & Table Setup
   2. Exploratory Data Analysis
   3. Data Cleaning & Integrity Fixes
   4. Analysis & Insights
   5. Deeper Analysis — Provincial Breakdown
   6. Progress Tracking Table
=====================================================================*/

-- ====================================================================
-- CHAPTER 1: DATABASE & TABLE SETUP
-- ====================================================================

-- Create database
CREATE DATABASE md_water_crisis;
USE md_water_crisis;
/* Data received as CSV files from field survey. 
Tables imported via MySQL Workbench import wizard:
   - employee				: Details of field survey employees who
							  conducted the water source visits
   - location				: Geographic data of all water sources  
                              - address, provinces, towns and location 
                              types (urban/rural)
   - visits					: Survey visits queue times records linking  
							  employees, locations and water sources 
   - water_quality			: Quality scores and subjective assessments
							  recorded at each water source visit
   - water_source			: Types of water sources surveyed 
							  (taps, wells, rivers etc.) and number of 
                              people served 
   - well_pollution			: Pollution test results and contamination 
							  data specific to well water sources */

-- Ensuring all the tables has been imported successfully
SHOW TABLES;

-- ====================================================================
-- CHAPTER 2: EXPLORATORY DATA ANALYSIS (EDA)
-- ====================================================================
/* Purpose: Understand the dataset structure, content, and quality 
   before analysis.
   Approach structured around 5 core EDA questions. */
   
-- --------------------------------------------------------------------
-- EDA Q1: What's here?
-- Preview key tables to understand structure & content
-- --------------------------------------------------------------------

SELECT * FROM water_source LIMIT 5;
SELECT * FROM visits LIMIT 5;
SELECT * FROM location LIMIT 5;

/* Remaining tables (employee, water_quality, well_pollution)
   previewed in MySQL Workbench - structures and content noted before 
   proceeding to analysis */
   
-- --------------------------------------------------------------------
-- EDA Q2: How much is here?
-- --------------------------------------------------------------------
SELECT COUNT(*) AS total_water_sources FROM water_source;
SELECT COUNT(*) AS total_visits FROM visits;

/* Full dataset spans 60,000 survey visits across 39,650 unique water 
   sources. Multiple visits recorded per shared tap to capture queue  
   time data - reflecting real-world congestion at high-demand sources 
   */

-- Validate coverage against known population size
SELECT SUM(number_of_people_served) AS total_people_served
FROM water_source;

/* Population completeness check:
   Known population of Maji Ndogo: 28,000,000
   Total number_of_people_served per survey: 27,628,140
   Variance: 371,860 (1.3% of population)
   
   Result is reasonable - 98.7% population coverage achieved.
   Variance attributable to rounding of the known population 
   figure rather than gaps in survey coverage.
   Data assessed as sufficiently complete for analysis. */
   
-- --------------------------------------------------------------------
-- EDA Q3: What are the unique values?
-- Understanding categories, coverage & distributions across key fields
-- --------------------------------------------------------------------

-- Water source types & distribution
SELECT type_of_water_source,
       COUNT(*) AS total
FROM water_source
GROUP BY type_of_water_source
ORDER BY total DESC;

-- Provinces covered & distribution
SELECT province_name,
       COUNT(*) AS total
FROM location
GROUP BY province_name
ORDER BY total DESC;

-- Location types & distribution
SELECT location_type,
       COUNT(*) AS total
FROM location
GROUP BY location_type
ORDER BY total DESC;

/* Findings:
   - 5 source types identified: wells, rivers, shared taps,
     tap_in_home and tap_in_home_broken
     Notable: tap_in_home_broken recorded as a source type - suggests
     infrastructure deterioration worth investigating in analysis
   - Wells make up 44% of all water sources
   - 5 provinces covered: Sokoto, Kilimani, Hawassa, Akatsi and Amanzi
     Sources spread "evenly" across the country
     (provinces share between 15–24% of total sources)
   - 60% of sources in rural areas
   Coverage confirmed - no gaps in source types, provinces 
   or location types identified */

-- --------------------------------------------------------------------
-- EDA Q4: Any data quality issues?
-- Checking for NULLs & duplicates before relying on data
-- --------------------------------------------------------------------

-- Check for NULLs in critical fields
SELECT COUNT(*) AS null_source_types
FROM water_source 
WHERE type_of_water_source IS NULL;

SELECT COUNT(*) AS null_provinces
FROM location 
WHERE province_name IS NULL;

-- Check for duplicate source records
SELECT source_id, COUNT(*) AS occurrences
FROM water_source 
GROUP BY source_id 
HAVING COUNT(*) > 1;

/* Data quality findings: 
   - No NULLs detected in critical fields.
   - No duplicate source_id records found. */
   
-- ====================================================================
-- CHAPTER 3: DATA CLEANING & INTEGRITY FIXES
-- ====================================================================

/* Purpose: Identify and resolve data quality issues before analysis.
   Cleaning is iterative - all fixes consolidated here for clarity.
   
   Tables cleaned:
   - well_pollution  : Data integrity fixes to description & results
   - employee        : Email population & phone number formatting */

-- --------------------------------------------------------------------
-- 3.1 Well Pollution — Data Integrity Fixes
-- --------------------------------------------------------------------
/* Issue 1: Some descriptions incorrectly begin with "Clean" despite
   biological contamination being present (biological > 0.01 CFU/mL).
   Issue 2: Results column incorrectly marked "Clean" where biological 
   contamination exists - highest risk scenario as people could 
   unknowingly consume contaminated water.
   
   Approach: Test all fixes on a copy of the table before applying 
   to the original - ensuring no unintended changes to source data. */

-- Identify descriptions incorrectly starting with "Clean"
SELECT *
FROM well_pollution
WHERE description LIKE 'Clean %';
-- 38 records identified

-- Identify results marked Clean despite biological contamination
SELECT *
FROM well_pollution
WHERE results = 'Clean' AND biological > 0.01;
-- 64 records identified

-- Create a copy of well_pollution to safely test fixes
CREATE TABLE well_pollution_copy
AS (
    SELECT *
    FROM well_pollution
);

-- Fix 1: Remove "Clean" prefix from contaminated descriptions
UPDATE well_pollution_copy
SET description = 'Bacteria: E. coli'
WHERE description = 'Clean Bacteria: E. coli';

UPDATE well_pollution_copy
SET description = 'Bacteria: Giardia Lamblia'
WHERE description = 'Clean Bacteria: Giardia Lamblia';

-- Fix 2: Update results from Clean to Contaminated: Biological
-- where biological contamination is present
UPDATE well_pollution_copy
SET results = 'Contaminated: Biological'
WHERE biological > 0.01 AND results = 'Clean';

-- Verify fixes - expect 0 rows returned
SELECT *
FROM well_pollution_copy
WHERE description LIKE 'Clean_%'
OR (results = 'Clean' AND biological > 0.01);
-- 0 rows returned — fixes verified 

-- Apply verified fixes to original well_pollution table
UPDATE well_pollution
SET description = 'Bacteria: E. coli'
WHERE description = 'Clean Bacteria: E. coli';

UPDATE well_pollution
SET description = 'Bacteria: Giardia Lamblia'
WHERE description = 'Clean Bacteria: Giardia Lamblia';

UPDATE well_pollution
SET results = 'Contaminated: Biological'
WHERE biological > 0.01 AND results = 'Clean';

-- Drop copy table - no longer needed
DROP TABLE well_pollution_copy;

-- --------------------------------------------------------------------
-- 3.2 Employee Table - Email Population
-- --------------------------------------------------------------------
/* Issue: Email addresses missing for all employees.
   Emails required for distributing reports and analytical findings.
   
   Format: first_name.last_name@ndogowater.gov
   Logic: Convert employee_name to lowercase, replace spaces 
   with periods, append domain */

-- Verify email format before updating
SELECT 
    employee_name,
    CONCAT(LOWER(REPLACE(employee_name, ' ', '.')),
    '@ndogowater.gov') AS generated_email
FROM employee
LIMIT 5;

-- Apply email population
UPDATE employee
SET email = CONCAT(LOWER(REPLACE(employee_name, ' ', '.')),
'@ndogowater.gov');

-- Verify update
SELECT employee_name, email
FROM employee
LIMIT 5;

-- --------------------------------------------------------------------
-- 3.3 Employee Table - Phone Number Formatting
-- --------------------------------------------------------------------
/* Issue: Phone numbers stored with an extra character - 
   LENGTH() returns 13 characters instead of expected 12.
   Format should be: + [area code 99] [phone digits] = 12 characters
   
   Fix: TRIM() to remove leading or trailing spaces */

-- Confirm issue
SELECT LENGTH(phone_number)
FROM employee
LIMIT 5;
-- Returns 13 — extra character confirmed

-- Apply fix
UPDATE employee
SET phone_number = TRIM(phone_number);

-- Verify fix
SELECT LENGTH(phone_number)
FROM employee
LIMIT 5;
-- Returns 12 — formatting confirmed 

-- --------------------------------------------------------------------
-- SUMMARY
-- --------------------------------------------------------------------
/* Cleaning completed across 2 tables:
   
   well_pollution:
   - 38 descriptions corrected (Clean prefix removed)
   - 64 results updated from Clean to Contaminated: Biological
   - Fixes tested on copy table before applying to source 
   
   employee:
   - Email addresses populated for all employees
     using first_name.last_name@ndogowater.gov format
   - Phone numbers trimmed to correct 12 character format
   
   Data assessed as clean and reliable for analysis. */
   
-- ====================================================================
-- CHAPTER 4: DATA ANALYSIS & INSIGHTS
-- ====================================================================
/* Purpose: Analyse water source distribution, accessibility, quality
   and queue patterns to identify priority areas for government 
   intervention and infrastructure restoration.
   
   Analysis structured across 3 focus areas:
   4.1 Water source distribution & coverage
   4.2 Well quality analysis
   4.3 Queue time analysis */

-- --------------------------------------------------------------------
-- 4.1 Water Source Distribution & Coverage
-- --------------------------------------------------------------------

-- Average number of people served per water source type
SELECT
    type_of_water_source,
    AVG(number_of_people_served) AS avg_people_per_source
FROM
    water_source
GROUP BY
    type_of_water_source
ORDER BY 2 DESC;

/* Key finding: 2,000 people share a single shared tap on average -
   highest burden of any source type. Shared taps should be 
   prioritised for improvement. */

-- Total population served by each water source type (%)
SELECT
    type_of_water_source,
    ROUND((SUM(number_of_people_served)/27628140)*100) 
        AS percentage_people_per_source
FROM
    water_source
GROUP BY
    type_of_water_source
ORDER BY 2 DESC;

/* Key findings:
   - 43% of the population rely on shared taps in their communities
     with an average of 2,000 people per tap - critical pressure point
   - 31% have water infrastructure installed at home, however 45% 
     (14/31) of home taps are not functioning
   - Combined, shared taps and broken home infrastructure represent
     the most urgent intervention priorities */

-- --------------------------------------------------------------------
-- 4.2 Well Quality Analysis
-- --------------------------------------------------------------------

-- Distribution of well results - clean vs contaminated
SELECT
    results,
    COUNT(*) AS number_of_wells,
    ROUND(COUNT(*)/17383*100) AS percentage
FROM
    well_pollution
GROUP BY
    results;

/* Key findings:
   - 18% of the population rely on wells as their water source
   - Only 4,916 out of 17,383 wells are clean - just 28% 
   - 72% of wells are contaminated, exposing a significant portion 
     of the population to biological and chemical pollutants
   - Well rehabilitation represents a high-impact intervention 
     given the scale of contamination */

-- --------------------------------------------------------------------
-- 4.3 Queue Time Analysis
-- --------------------------------------------------------------------

-- Overall average queue time (excluding home taps with no queues)
SELECT
    AVG(time_in_queue) AS avg_queue_time
FROM
    visits
WHERE
    time_in_queue > 0;

/* Key finding: Average queue time of 123 minutes - people without 
   home taps spend approximately 2 hours collecting water daily,
   representing a significant burden on communities */

-- Average queue time by day of week
SELECT
    DAYNAME(time_of_record) AS day_of_week,
    ROUND(AVG(time_in_queue)) AS avg_queue_time
FROM
    visits
GROUP BY 1
ORDER BY 2 DESC;

/* Key finding: Saturdays have significantly longer queue times 
   at 246 minutes on average - double the overall average.
   Wednesdays and Sundays record the shortest queue times. */

-- Queue time by hour of day across all days (pivot table)
-- Reveals patterns in when communities collect water during the day
SELECT
    TIME_FORMAT(TIME(time_of_record), '%H:00') AS hour_of_day,
    ROUND(AVG(CASE WHEN DAYNAME(time_of_record) = 'Sunday' 
        THEN time_in_queue END), 0) AS Sunday,
    ROUND(AVG(CASE WHEN DAYNAME(time_of_record) = 'Monday' 
        THEN time_in_queue END), 0) AS Monday,
    ROUND(AVG(CASE WHEN DAYNAME(time_of_record) = 'Tuesday' 
        THEN time_in_queue END), 0) AS Tuesday,
    ROUND(AVG(CASE WHEN DAYNAME(time_of_record) = 'Wednesday' 
        THEN time_in_queue END), 0) AS Wednesday,
    ROUND(AVG(CASE WHEN DAYNAME(time_of_record) = 'Thursday' 
        THEN time_in_queue END), 0) AS Thursday,
    ROUND(AVG(CASE WHEN DAYNAME(time_of_record) = 'Friday' 
        THEN time_in_queue END), 0) AS Friday,
    ROUND(AVG(CASE WHEN DAYNAME(time_of_record) = 'Saturday' 
        THEN time_in_queue END), 0) AS Saturday
FROM visits
WHERE time_in_queue <> 0
GROUP BY hour_of_day
ORDER BY hour_of_day;

/* Queue time patterns identified:
   - Saturdays consistently record the longest queues across all hours
   - Morning and evening peaks observed daily — aligning with 
     household water collection before and after work/school
   - Wednesdays and Sundays are the least congested days
   
   Implication: Infrastructure improvements and water distribution 
   scheduling should account for Saturday peaks and morning/evening 
   demand patterns */
   
-- --------------------------------------------------------------------
-- SUMMARY — KEY INSIGHTS
-- --------------------------------------------------------------------
/* 1. Most water sources are rural at 60%.
   2. 43% of the population rely on shared taps, with an average of 
      2,000 people sharing one tap.
   3. 31% of the population has home water infrastructure, however 
      45% of these systems are non-functional due to issues with 
      pipes, pumps and reservoirs.
   4. 18% of the population rely on wells, of which only 28% are clean.
   5. Citizens face an average queue time of 123 minutes per water 
      collection trip.
   6. Queue time patterns:
      - Saturdays record the longest queues
      - Morning and evening peaks observed daily
      - Wednesdays and Sundays are the least congested */
    
-- ====================================================================
-- CHAPTER 5: DEEPER ANALYSIS — PROVINCIAL & TOWN BREAKDOWN
-- ====================================================================
/* Purpose: Identify where problems are concentrated to enable 
   targeted, prioritised government intervention. */

-- --------------------------------------------------------------------
-- 5.1 Practical Solutions Framework
-- --------------------------------------------------------------------
/* Based on Chapter 4 insights, the following interventions are 
   recommended per source type:
   
   1. Rivers             → Drill wells for permanent clean supply
   2. Wells (chemical)   → Install reverse osmosis (RO) filter
   3. Wells (biological) → Install UV and RO filter
   4. Shared taps        → If queue ≥ 30 min, install additional taps
                           Number of taps = FLOOR(time_in_queue / 30)
                           Based on UN 30-minute maximum standard
   5. tap_in_home_broken → Diagnose and repair local infrastructure */

-- --------------------------------------------------------------------
-- 5.2 Combined Analysis View
-- --------------------------------------------------------------------
/* Consolidates key columns from multiple tables into a single 
   reusable structure — simplifying subsequent queries.
   visit_count = 1 ensures each source is counted once. */

CREATE VIEW combined_analysis_table AS
SELECT
    water_source.type_of_water_source AS source_type,
    location.town_name,
    location.province_name,
    location.location_type,
    water_source.number_of_people_served AS people_served,
    visits.time_in_queue,
    well_pollution.results
FROM
    visits
LEFT JOIN
    well_pollution ON well_pollution.source_id = visits.source_id
INNER JOIN
    location ON location.location_id = visits.location_id
INNER JOIN
    water_source ON water_source.source_id = visits.source_id
WHERE
    visits.visit_count = 1;

-- --------------------------------------------------------------------
-- 5.3 Water Source Distribution by Province & Town (%)
-- --------------------------------------------------------------------
/* CTE calculates total population per town first.
   Note: Two towns named Harare exist — grouped on composite key 
   (province_name + town_name) to avoid incorrect aggregation. */

WITH town_totals AS (
    SELECT 
        province_name, 
        town_name, 
        SUM(people_served) AS total_ppl_serv
    FROM combined_analysis_table
    GROUP BY province_name, town_name
)
SELECT
    ct.province_name,
    ct.town_name,
    ROUND((SUM(CASE WHEN source_type = 'river'
        THEN people_served ELSE 0 END) * 100.0 
        / tt.total_ppl_serv), 0) AS river,
    ROUND((SUM(CASE WHEN source_type = 'shared_tap'
        THEN people_served ELSE 0 END) * 100.0 
        / tt.total_ppl_serv), 0) AS shared_tap,
    ROUND((SUM(CASE WHEN source_type = 'tap_in_home'
        THEN people_served ELSE 0 END) * 100.0 
        / tt.total_ppl_serv), 0) AS tap_in_home,
    ROUND((SUM(CASE WHEN source_type = 'tap_in_home_broken'
        THEN people_served ELSE 0 END) * 100.0 
        / tt.total_ppl_serv), 0) AS tap_in_home_broken,
    ROUND((SUM(CASE WHEN source_type = 'well'
        THEN people_served ELSE 0 END) * 100.0 
        / tt.total_ppl_serv), 0) AS well
FROM
    combined_analysis_table ct
JOIN
    town_totals tt 
    ON ct.province_name = tt.province_name 
    AND ct.town_name = tt.town_name
GROUP BY
    ct.province_name,
    ct.town_name
ORDER BY 1, 2;

-- -------------------------------------------------------------------
-- CHAPTER 5 SUMMARY
-- -------------------------------------------------------------------
/* Sokoto:  Highest river water dependency — drilling teams dispatched 
            first, prioritising rural areas and city of Bahari.
            Significant wealth inequality flagged — river users and 
            home tap users coexist in the same province.

   Amanzi:  Infrastructure installed but largely non-functional.
            Exception: capital Dahabu — maintained exclusively for 
            previous government leadership.
            Fixing Amanzi infrastructure restores home water access 
            AND reduces queue times simultaneously. */
   
-- ====================================================================
-- CHAPTER 6: PROGRESS TRACKING TABLE
-- ====================================================================
/* Purpose: Create a structured table to track water source 
   improvement assignments, team progress and completion status.
   Each record represents one source requiring intervention. */

-- --------------------------------------------------------------------
-- 6.1 Create Project_progress Table
-- --------------------------------------------------------------------
/* Table designed to:
   - Store improvement assignments with full location details
   - Track status through workflow: Backlog → In progress → Complete
   - Provide space for teams to log completion dates and comments
   - Link back to water_source via source_id for data integrity */

CREATE TABLE Project_progress (
    Project_id SERIAL PRIMARY KEY,
    source_id VARCHAR(20) NOT NULL 
        REFERENCES water_source(source_id) 
        ON DELETE CASCADE 
        ON UPDATE CASCADE,
    Address VARCHAR(50),
    Town VARCHAR(30),
    Province VARCHAR(30),
    Source_type VARCHAR(50),
    Improvement VARCHAR(50),
    Source_status VARCHAR(50) DEFAULT 'Backlog' 
        CHECK (Source_status IN ('Backlog', 'In progress', 'Complete')),
    Date_of_completion DATE,
    Comments TEXT
);

-- --------------------------------------------------------------------
-- 6.2 Populate Project_progress Table
-- --------------------------------------------------------------------
/* Filter logic:
   - visit_count = 1 ensures each source appears once
   - Shared taps: queue time ≥ 30 min only
   - Wells: contaminated only (clean wells excluded)
   - Rivers: all included
   - tap_in_home_broken: all included
   
   Improvement assigned per source type based on 
   solutions framework in Chapter 5.1 */

INSERT INTO Project_progress
    (source_id, Address, Town, Province, Source_type, Improvement)
SELECT
    water_source.source_id,
    location.address,
    location.town_name,
    location.province_name,
    water_source.type_of_water_source,
    CASE
        WHEN water_source.type_of_water_source = 'river'
            THEN 'Drill well'
        WHEN water_source.type_of_water_source = 'well' 
            AND well_pollution.results LIKE 'Contaminated: Biological'
            THEN 'Install UV and RO filter'
        WHEN water_source.type_of_water_source = 'well' 
            AND well_pollution.results LIKE 'Contaminated: Chemical'
            THEN 'Install RO filter'
        WHEN water_source.type_of_water_source = 'shared_tap' 
            AND visits.time_in_queue >= 30
            THEN CONCAT('Install ', FLOOR(visits.time_in_queue / 30), 
                ' tap(s) nearby')
        WHEN water_source.type_of_water_source = 'tap_in_home_broken'
            THEN 'Diagnose local infrastructure'
    END AS Improvement
FROM
    water_source
INNER JOIN
    visits ON visits.source_id = water_source.source_id
INNER JOIN
    location ON location.location_id = visits.location_id
LEFT JOIN
    well_pollution ON well_pollution.source_id = water_source.source_id
WHERE
    visits.visit_count = 1
    AND (
        (water_source.type_of_water_source = 'shared_tap' 
            AND visits.time_in_queue >= 30)
        OR (water_source.type_of_water_source = 'well' 
            AND well_pollution.results != 'Clean')
        OR water_source.type_of_water_source = 'river'
        OR water_source.type_of_water_source = 'tap_in_home_broken'
    );

-- Verify records inserted
SELECT COUNT(*) AS total_improvements FROM Project_progress;
-- 25,398 improvement assignments successfully inserted

-- Preview improvement assignments
SELECT * FROM Project_progress LIMIT 10;

-- -------------------------------------------------------------------
-- CHAPTER 6 SUMMARY
-- -------------------------------------------------------------------
/* Project_progress table successfully populated with improvement 
   assignments across all qualifying water sources.
   
   Each record contains:
   - Full location details for field teams
   - Source type and specific improvement required
   - Status defaulted to 'Backlog' — ready for team assignment
   - Date_of_completion and Comments fields available for 
     progress updates as work is completed
     
   Table provides the government's operational backbone for 
   tracking the water crisis restoration programme. */
   
   
   
   
   
   
   