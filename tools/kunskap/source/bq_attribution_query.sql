/* Copyright 2019 Google Inc.
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
     http://www.apache.org/licenses/LICENSE-2.0
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.

*/
(
  WITH
    billing_export_table AS (
        SELECT
         *
        FROM
         `{billing_project_id}.{billing_dataset_id}.{billing_table_name}`
    ),
    billing_id_table AS (
    SELECT
      billing_account_id
    FROM
      billing_export_table
    GROUP BY
      billing_account_id
    LIMIT
      1 ),
  project_name_table AS (
    SELECT
      project.id AS project_id,
      project.name AS project_name
    FROM
      billing_export_table
    GROUP BY
      1,
      2
  ),
  projects_with_names AS (
    SELECT data_table.start_date AS start_day, name_table.project_id, data_table.total_slot_ms / (1000*60*60*24) AS slot_days, project_name
    FROM `{billing_project_id}.{audit_logs_dataset_id}.{audit_logs_view_name}` AS data_table
    JOIN project_name_table as name_table
    ON name_table.project_id = data_table.project_id
  ),
  total_slot_per_day AS (
      SELECT start_day AS start_day,
      SUM(slot_days) as num_slots
      FROM projects_with_names
      GROUP BY 1
      ),
  bq_billing_export_data_total_cost AS (
      SELECT  CAST(DATE(usage_start_time, "UTC") AS STRING) AS start_day,
      invoice.month as invoice_month,
      SUM(cost) AS total_cost
      FROM billing_export_table
      WHERE
        service.description = 'BigQuery' AND
        sku.description = 'BigQuery Reserved Capacity Fee'
      GROUP BY
      1,
      2
    ),
  pricing_unit AS (
    SELECT
      s.start_day AS start_day,
      c.invoice_month AS invoice_month,
      c.total_cost/s.num_slots AS cost_per_slot
    FROM
      total_slot_per_day AS s
    JOIN
      bq_billing_export_data_total_cost AS c
    ON
      c.start_day = s.start_day
    ),
  cost_per_project AS (
      SELECT
        usage.start_day,
        usage.project_id,
        usage.project_name,
        usage.slot_days,
        p.cost_per_slot,
        p.invoice_month,
        usage.slot_days*p.cost_per_slot AS cost
      FROM
       projects_with_names AS usage
      JOIN
        pricing_unit AS p
      ON
        p.start_day = usage.start_day
      ),
  -- Gathering information like billing_account_id, service_id from the bq_billing_table
  service_id_description AS (
      SELECT billing_account_id AS billing_account_id,
        service.id AS id,
        service.description AS description
      FROM billing_export_table
      WHERE service.description = "BigQuery" AND sku.description = "BigQuery Reserved Capacity Fee"
      LIMIT 1
        ),
   invoice_month_view as (
      SELECT invoice.month as invoice_month,
      (SELECT TIMESTAMP (CAST(DATE(usage_start_time, "America/Los_Angeles") AS STRING)) ) AS usage_start_time
      FROM
      billing_export_table AS bq_export
      WHERE
      service.description = "BigQuery" AND
      sku.description = "BigQuery Reserved Capacity Fee"
      GROUP BY 1, 2
),
cancelled_bq as (
 SELECT
      (SELECT billing_account_id FROM  service_id_description) AS billing_account_id,
      STRUCT((SELECT id FROM  service_id_description) AS id, (SELECT description FROM  service_id_description) AS description) AS service,
      STRUCT("Reattribution_Negation_BQ_Reserved_Capacity_Fee" AS id, "Reattribution_Negation_BQ_Reserved_Capacity_Fee" AS description) AS sku,
      TIMESTAMP_TRUNC(bq_export.usage_start_time, DAY) AS usage_start_time,
      TIMESTAMP_ADD(TIMESTAMP_TRUNC(bq_export.usage_end_time, DAY), INTERVAL ((3600*23)+3599) SECOND) AS usage_end_time,
      STRUCT(bq_export.project.id AS id,bq_export.project.name AS name, ARRAY<STRUCT<key STRING, value STRING>> [("is_corrected_data" , "1")] AS labels,  "" AS ancestry_numbers ) AS project,
      ARRAY<STRUCT<name STRING, value STRING>> [] AS labels,
      ARRAY<STRUCT<name STRING, value STRING>> [] AS system_labels,
      STRUCT( "" AS location, "" AS country, "" AS region, "" AS zone) AS location,
      CURRENT_TIMESTAMP() AS export_time,
      -1*sum(cost) AS cost,
      "USD" AS currency,
      1.0 AS currency_conversion_rate,
      STRUCT( sum(usage.amount) AS amount,
      "seconds" AS unit,
      sum(usage.amount_in_pricing_units) AS amount_in_pricing_units,
      "month" AS pricing_unit) AS usage,
      ARRAY<STRUCT<name STRING, amount FLOAT64>>[] AS credits,
      STRUCT(mv.invoice_month as month) As invoice,
      cost_type
    FROM
      billing_export_table AS bq_export
    RIGHT JOIN
     invoice_month_view AS mv
   ON
   (SELECT TIMESTAMP (CAST(DATE(bq_export.usage_start_time, "America/Los_Angeles") AS STRING)) ) = mv.usage_start_time
    WHERE
      service.description = "BigQuery" AND
      sku.description = "BigQuery Reserved Capacity Fee"
      GROUP BY usage_start_time, usage_end_time, cost_type, mv.invoice_month, bq_export.project.id, bq_export.project.name
),
corrected_bq as (
  SELECT
      (SELECT billing_account_id FROM  service_id_description) AS billing_account_id,
      STRUCT((SELECT id FROM  service_id_description) AS id, (SELECT description FROM  service_id_description) AS description) AS service,
      STRUCT("Reattribution_Addition_BQ_Reserved_Capacity_Fee" AS id, "Reattribution_Addition_BQ_Reserved_Capacity_Fee" AS description) AS sku,
      TIMESTAMP(cp.start_day) AS usage_start_time,
      TIMESTAMP_ADD(TIMESTAMP(cp.start_day), INTERVAL ((3600*23)+3599) SECOND) AS usage_end_time,
      STRUCT( cp.project_id AS id, cp.project.name AS name,  ARRAY<STRUCT<key STRING, value STRING>> [("is_corrected_data" , "1")] AS labels,"" as ancestry_numbers ) AS project,
      ARRAY<STRUCT<name STRING, value STRING>> [] AS labels,
      ARRAY<STRUCT<name STRING, value STRING>> [] AS system_labels,
      STRUCT( "" AS location, "" AS country, "" AS region, "" AS zone) AS location,
      CURRENT_TIMESTAMP() AS export_time,
      (cp.cost) AS cost,
      "USD" AS currency,
      1.0 AS currency_conversion_rate,
      STRUCT(cp.slot_days AS amount,
      "slot days" AS unit,
      0.0 AS amount_in_pricing_units,
      "slot days" AS pricing_unit) AS usage,
      ARRAY<STRUCT<name STRING, amount FLOAT64>>[] AS credits,
      STRUCT(cp.invoice_month AS month) AS invoice,
      "" AS cost_type
  FROM
       cost_per_project as cp
       )
  SELECT
    *
  FROM
   cancelled_bq
  UNION ALL
  SELECT
    *
  FROM
    corrected_bq
  UNION ALL
  SELECT
    *
  FROM
    billing_export_table
)