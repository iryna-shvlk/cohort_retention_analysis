
/* COHORT RETENTION ANALYSIS 
  This script cleans raw user and event data, standardizes inconsistent date formats,
  and calculates monthly retention offsets.
*/

-- Normalizing separators in signup strings
with

us_u as (
  select 
    cur.user_id,
    cur.signup_datetime,
    regexp_replace(
      replace(replace(trim(cur.signup_datetime), '/', '-'), '.', '-'),
      '\s+', ' ', 'g'
    ) as united_separators
  from cohort_users_raw cur
),
-- Spliting date and time parts for easier parsing
dt_u as (
  select
    us_u.user_id,
    trim(us_u.united_separators) as united_separators,
    split_part(trim(us_u.united_separators), ' ', 1) as date_part,
    split_part(trim(us_u.united_separators), ' ', 2) as time_part
  from us_u
),
-- Breaking down date into day, month, and year components
dmy_u as (
  select 
    dt_u.user_id,
    split_part(dt_u.date_part, '-', 1) as day,
    split_part(dt_u.date_part, '-', 2) as month,
    split_part(dt_u.date_part, '-', 3) as year,
    dt_u.time_part
  from dt_u
),
-- Reconstructing and casting to proper TIMESTAMP format (handling 2-digit years)
cd_u as (
  select 
    dmy_u.user_id,
    to_timestamp(
      concat(
        case when length(dmy_u.day) = 1 then concat('0', dmy_u.day) else dmy_u.day end,
        '-',
        case when length(dmy_u.month) = 1 then concat('0', dmy_u.month) else dmy_u.month end,
        '-',
        case when length(dmy_u.year) = 2 then concat('20', dmy_u.year) else dmy_u.year end,
        ' ',
        dmy_u.time_part
      ),
      'DD-MM-YYYY HH24:MI'
    ) as signup_datetime_parsed
  from dmy_u
),
-- Finalizing cleaned users table
cohort_users as (
  select 
    cur.*,
    cd_u.signup_datetime_parsed
  from cohort_users_raw cur
  join cd_u
    on cd_u.user_id = cur.user_id
),
-- Repeating cleaning logic for the events table
us_e as (
  select 
    cer.user_id,
    cer.event_id,
    cer.event_datetime,
    regexp_replace(
      replace(replace(trim(cer.event_datetime), '/', '-'), '.', '-'),
      '\s+', ' ', 'g'
    ) as united_separators
  from cohort_events_raw cer
),

dt_e as (
  select
    us_e.user_id,
    us_e.event_id,
    trim(us_e.united_separators) as united_separators,
    split_part(trim(us_e.united_separators), ' ', 1) as date_part,
    split_part(trim(us_e.united_separators), ' ', 2) as time_part
  from us_e
),

dmy_e as (
  select 
    dt_e.user_id,
    dt_e.event_id,
    split_part(dt_e.date_part, '-', 1) as day,
    split_part(dt_e.date_part, '-', 2) as month,
    split_part(dt_e.date_part, '-', 3) as year,
    dt_e.time_part
  from dt_e
),

cd_e as (
  select 
    dmy_e.user_id,
    dmy_e.event_id,
    to_timestamp(
      concat(
        case when length(dmy_e.day) = 1 then concat('0', dmy_e.day) else dmy_e.day end,
        '-',
        case when length(dmy_e.month) = 1 then concat('0', dmy_e.month) else dmy_e.month end,
        '-',
        case when length(dmy_e.year) = 2 then concat('20', dmy_e.year) else dmy_e.year end,
        ' ',
        dmy_e.time_part
      ),
      'DD-MM-YYYY HH24:MI'
    ) as event_datetime_parsed
  from dmy_e
),
-- Finalizing cleaned events table and joining with users
cohort_events as (
  select 
    cer.*,
    cd_e.event_datetime_parsed
  from cohort_events_raw cer
  join cd_e
    on cd_e.event_id = cer.event_id
   and cd_e.user_id = cer.user_id
),
-- Filtering out test data and invalid records
clean_analysis as (
  select 
    cu.user_id,
    cu.full_name,
    cu.email,
    cu.country,
    cu.signup_source,
    cu.signup_device,
    cu.promo_signup_flag,
    cast(date_trunc('month', cu.signup_datetime_parsed) as date) as signup_month,
    ce.event_id,
    ce.event_type,
    ce.revenue,
    cast(date_trunc('month', ce.event_datetime_parsed) as date) as event_month
  from cohort_users cu
  inner join cohort_events ce
    on cu.user_id = ce.user_id
  where ce.event_type is not null
    and trim(ce.event_type) <> ''
    and ce.event_type <> 'test_event'
    and cu.signup_datetime_parsed is not null
    and ce.event_datetime_parsed is not null
)
-- Final Output: Calculating active users per cohort and month offset
select
  ca.promo_signup_flag,
  ca.signup_month as cohort_month,
  cast(
    (
      (extract(year from ca.event_month) - extract(year from ca.signup_month)) * 12
      + (extract(month from ca.event_month) - extract(month from ca.signup_month))
    ) as int
  ) as month_offset,
  count(distinct ca.user_id) as users_total
from clean_analysis ca
where ca.event_month >= date '2025-01-01'
  and ca.event_month < date '2025-07-01'
group by 1, 2, 3
order by 1, 2, 3;
