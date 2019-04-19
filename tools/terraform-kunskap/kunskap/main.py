# Copyright 2019 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Function called by PubSub trigger to execute  cron jon tasks."""
import datetime
import logging
from string import Template
import config
from google.cloud import bigquery


def file_to_string(sql_path):
    """Converts a SQL file holding a SQL query to a string.
    Args:
        sql_path: String containing a file path
    Returns:
        String representation of a file's contents
    """
    with open(sql_path, 'r') as sql_file:
        return sql_file.read()


def create_view(bq_client):
    """Creates BigQuery view to hold BigQuery audit log data.

    Args:
        bq_client: Object representing reference to a BigQuery Client
    """
    sql = file_to_string(config.config_vars['create_view_sql_path'])
    sql = sql.format(**config.config_vars)

    dataset_ref = bq_client.get_dataset(bigquery.DatasetReference(
        project=config.config_vars['billing_project_id'],
        dataset_id=config.config_vars['audit_logs_dataset_id']))
    view_ref = dataset_ref.table(config.config_vars['audit_logs_view_name'])
    view = bigquery.Table(view_ref)
    view.view_query = sql

    table_list = [table.table_id for table in list(bq_client.list_tables(dataset_ref))]
    if config.config_vars['audit_logs_view_name'] in table_list:
        bq_client.update_table(view, ['view_query'])

    else:
        bq_client.create_table(view)


def execute_transformation_query(bq_client):
    """Executes transformation query to a new destination table.
    Args:
        bq_client: Object representing a reference to a BigQuery Client
    """
    dataset_ref = bq_client.get_dataset(bigquery.DatasetReference(
        project=config.config_vars['billing_project_id'],
        dataset_id=config.config_vars['output_dataset_id']))
    table_ref = dataset_ref.table(config.config_vars['output_table_name'])
    job_config = bigquery.QueryJobConfig()
    job_config.destination = table_ref
    job_config.write_disposition = bigquery.WriteDisposition().WRITE_TRUNCATE
    job_config.time_partitioning = bigquery.TimePartitioning(
        field='usage_start_time',
        expiration_ms=None)
    sql = file_to_string(config.config_vars['create_output_table_sql_file_path'])
    sql = sql.format(**config.config_vars)
    logging.info('Attempting query on all dates...')
    # Execute Query
    query_job = bq_client.query(
        sql,
        job_config=job_config)

    query_job.result()  # Waits for the query to finish
    logging.info('Transformation query complete. All partitions are updated.')


def main(data, context):
    """Triggered from a message on a Cloud Pub/Sub topic.
    Args:
        data (dict): Event payload.
        context (google.cloud.functions.Context): Metadata for the event.
    """
    bq_client = bigquery.Client()

    try:
        current_time = datetime.datetime.utcnow()
        log_message = Template('Cloud Function was triggered on $time')
        logging.info(log_message.safe_substitute(time=current_time))

        try:
            create_view(bq_client)
            execute_transformation_query(bq_client)

        except Exception as error:
            log_message = Template('Transformation query failed due to '
                                   '$message.')
            logging.error(log_message.safe_substitute(message=error))

    except Exception as error:
        log_message = Template('$error').substitute(error=error)
        logging.error(log_message)

if __name__ == '__main__':
    main('data', 'context')
