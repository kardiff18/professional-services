<h2>Introduction</h2>

The purpose of this project is to demonstrate how to automate the process of viewing [Committed Use Discount (CUD)](https://cloud.google.com/compute/docs/instances/signing-up-committed-use-discounts) and [Sustained Use Discount (SUD)](https://cloud.google.com/compute/docs/sustained-use-discounts) charges in GCP on a 
per-project basis to a BigQuery table. This helps to accurately view project cost, since currently when exporting billing 
data, it does not correctly attribute CUD/SUD commitment charges.
<br></br>
Currently, this data can be viewed by running a query in BigQuery on exported billing data and generating a new table with 
this transformed data. This example demonstrates how to automate this process to avoid manually executing the query.
<br></br>
In this example, a user can leverage Cloud Scheduler to schedule the recurring transformation query as a cron job which repeats every few hours. 
Next, the Cloud Scheduler job then publishes a message to a PubSub topic on execution time. A Cloud Function that is 
configured as a subscriber to this topic is then triggered by the PubSub message. The Cloud Function then calls a Python 
script, which performs the transformation query on the billing table and generates the new table with the CUD/SUD commitment 
charges.

<h2>Installation/Set-up</h2>
This project assumes that you already have project set up with billing data exported to BigQuery. Note the billing project id, dataset ids, and the table names, as you will need these later on when configuring the Cloud Function source code.

<h3>Install/Configure the gcloud command line tool:</h3>

1. [Install and initialize the Cloud SDK](https://cloud.google.com/sdk/docs/how-to)

2. In a terminal window, enter the following to add the gcloud components for beta products
````
gcloud components install beta
````

3. Update all components:
````
gcloud components update
````

<h3>Create a new project for viewing the corrected data:</h3>

1. Open a terminal where you installed on the SDK and create a <b>new</b> project

````
gcloud projects create [PROJECT_ID]
````

where `[PROJECT_ID]` is the ID for the project that you want to create.

2. Configure gcloud to use the project that you created

````
gcloud config set project [PROJECT_ID]
````
where `[PROJECT_ID]` is the ID that you created in the previous step.


<h3>Set up BigQuery Permissions</h3>

1. In a terminal window, run the following to verify that a default App Engine service account was created when you enabled the Cloud Functions API.

````
gcloud iam service-accounts list
````
The output should display an email in the form of `[PROJECT_ID]`@appspot.gserviceaccount.com. Copy this email for the next step.

2. In the BigQuery UI, hover over the plus icon for your <b>billing</b> dataset. 

3. Click "Share Dataset"

4. In the pop-up, enter the service account email from step 1. Give it permission <b>"Can View".</b>

5. Hover over the plus icon for the <b>output</b> dataset.

6. Click "Share Dataset"

7. In the pop-up, enter the service account email from step 1. Give it permission <b>"Can Edit".</b>


<h3>Edit Python Config Variables</h3>

1. Clone this repo and open source/config.py in your chosen IDE.

2. Look at the top of the file after the comment about edits:

````python
config_vars = {
    # EDIT THESE WITH YOUR OWN DATASET/TABLES
    'billing_project_id': 'billing_project',
    'billing_dataset_id': 'billing_dataset',
    'billing_table_name': 'billing_table',
    'output_dataset_id': 'output_dataset',
    'output_table_name': 'output_table',
    'audit_logs_dataset_id': 'audit_logs_dataset',

    # Update depending on if you are using CUD/SUD Attribution and/or BQ
    'create_output_table_sql_file_path': 'cud_sud_attribution_query_with_bq_attribution.sql',

    # Update the view name if you would like to rename exported view differently
    'audit_logs_view_name': 'bq_proj_usage_table',

    # There are two slightly different allocation methods that affect how the
    # Commitment charge is allocated:

    # Method 1: Only UTILIZED commitment charges are allocated to projects.
    # (P_method_1_CUD_commitment_cost): Utilized CUD commitment charges are
    # proportionally allocated to each project based on its share of total
    # eligible VM usage during the time increment (P_usage_percentage). Any
    # unutilized commitment cost remains unallocated
    # (BA_unutilized_commitment_cost) and is allocated to the shell project.

    # Method 2: ALL commitment charges are allocated to projects (regardless of
    # utilization). (P_method_2_CUD_commitment_cost): All CUD commitment charges
    # are proportionally allocated to each project based on its share of total
    # eligible VM usage during the time increment (P_usage_percentage). All
    # commitment cost is allocated into the projects proportionally based on the
    # CUD credits that they consumed, even if the commitment is not fully
    # utilized.
    'allocation_method': 'P_method_2_commitment_cost',

    # Do not edit unless you renamed this file yourself.
    'create_view_sql_path': 'create_bq_usage_view_from_auditlogs.sql'
}
````

Change the values of billing_project_id, billing_dataset_id, billing_table_name, output_dataset_id, output_table_name, and audit_logs_dataset_id to your project's respective id, datasets, and tables in BigQuery. 
The output table will be created in this project, so you can choose any name that you would like. 
You must also update the output_table_sql_file_path based on which type of attribution that you would like to do: 
  - If you only need CUD/SUD attribution, select “cud_sud_attribution_query.sql”
  - If you only need BQ attribution, select “bq_attribution_query.sql”
  - If you need both CUD/SUD and BQ attribution, select “cud_sud_attribution_query_with_bq_attribution.sql”
For allocation_method, either “P_method_1_commitment_cost” or “P_method_2_commitment_cost”, based on the preferred allocation method as described in source/config.py. 
Default is P_method_2_commitment_cost. Method 2 is the safest.


<h3>Edit Terraform Config Variables</h3>

```
variable projectid {
  default = "projectname"
}

variable region {
  default = "europe-west1"
}

variable zone {
  default = "europe-west1-c"
}

variable jobid {
  default = "terraformjob"
}

variable frequency {
  default = "0 */12 * * *"
}

variable topic {
  default = "terraform-topic"
}

variable functioname {
  default = "terraform-fn"
}

variable bucketname {
  default = "kunskap-terraform-bucket"
}

locals {
  service_account = "${var.projectid}@appspot.gserviceaccount.com"
}
```

- frequency: This is how often your attribution will occur, in UNIX cron time.
- bucketname: This is the name of the GCS bucket where the compressed source code for the Cloud Function will reside. 
<b>You must rename this to a globally unique name, or else it will fail.</b> Suggested name: ‘projectid-kunskap-bucket’.
- service_account: This is an optional variable. It defaults to using the default App Engine service account. If you want to use a custom service account
to perform your queries on the BQ tables, enter it here.

<h3>Install Terraform:</h3>
To use Terraform, it should first be installed on your machine. It is distributed as a binary package and instructions to installation instructions can be found [here](https://learn.hashicorp.com/terraform/getting-started/install).


<h3>Create the GCP Resources:</h3>
Open up a terminal window, and cd into the directory where you saved the root of this repository. Enter:


1. cd terraform
2. terraform init
3. terraform plan
4. terraform apply
5. yes


<h3>Run the job:</h3>
You can test the workflow above by running the project now, instead of waiting for the scheduled UNIX time. To do this:

1. Open up the Cloud Scheduler page in the console.

2. Click the Run now button.

3. Open up BigQuery in the console.

4. Under your output dataset, look for your `[output_table_name]`, this will contain the data.
