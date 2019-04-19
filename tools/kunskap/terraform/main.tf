provider "google" {
  project = "${var.projectid}"
  region  = "${var.region}"
  zone    = "${var.zone}"
}

provider "google-beta" {
  project = "${var.projectid}"
  region = "${var.region}"
  zone = "${var.zone}"
}

# Zip up Kunskap Source Code folder
data "archive_file" "kunskapfiles" {
  type = "zip"
  output_path = "kunskap.zip"
  source_dir = "../source"
}

# Enable APIs; Must be individual resources or else it will disable all other APIs for the project.
# Individual
resource "google_project_service" "billingapi" {
  service = "cloudbilling.googleapis.com"
}

resource "google_project_service" "schedulerapi" {
  service = "cloudscheduler.googleapis.com"
}

resource "google_project_service" "pubsubapi" {
  service = "pubsub.googleapis.com"
}

resource "google_project_service" "cfapi" {
  service = "cloudfunctions.googleapis.com"
}

resource "google_project_service" "bqapi" {
  service = "bigquery-json.googleapis.com"
}

# Create GCS Bucket
resource "google_storage_bucket" "bucket" {
  name = "${var.bucketname}"
  provider = "google"
}

# Create GCS Folder
resource "google_storage_bucket_object" "folder" {
  provider = "google"
  name = "kunskap.zip"
  source = "kunskap.zip"
  bucket = "${google_storage_bucket.bucket.name}"
}

# Create PubSub Topic
resource "google_pubsub_topic" "topic" {
  name = "${var.topic}"
}

# Create a Cloud Function
resource "google_cloudfunctions_function" "function" {
  provider = "google"
  name = "${var.functioname}"
  entry_point = "main"
  timeout = "540"
  runtime = "python37"
  source_archive_bucket = "${google_storage_bucket.bucket.name}"
  source_archive_object = "${google_storage_bucket_object.folder.name}"
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource = "${var.topic}"
  }
  service_account_email = "${local.service_account}"
}

# Creates Scheduler Job -- Note that data cannot be left blank, so it has a dummy input
resource "google_cloud_scheduler_job" "job"{
  provider = "google-beta"
  name = "${var.jobid}"
  schedule = "${var.frequency}"
  pubsub_target {
    topic_name = "projects/${var.projectid}/topics/${var.topic}"
    data = "data"
  }
}