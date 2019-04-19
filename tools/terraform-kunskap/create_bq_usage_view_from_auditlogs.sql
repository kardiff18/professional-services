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

SELECT
  protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.projectId as project_id,
  FORMAT_TIMESTAMP("%Y-%m-%d", protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.createTime) as start_date,
  sum(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalProcessedBytes) as total_processed_bytes,
  sum(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs) as total_slot_ms
FROM
`{billing_project_id}.{output_dataset_id}.cloudaudit_googleapis_com_data_access_*` AS audit_logs
WHERE
  protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent IS NOT NULL
  AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatus.state IN ('DONE')
  AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatus.error IS NULL
  AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs IS NOT NULL
  AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalProcessedBytes IS NOT NULL
GROUP BY
  project_id, protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.createTime