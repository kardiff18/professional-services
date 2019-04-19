provider "google" {
  project = "${var.projectid}"
  region  = "${var.region}"
  zone    = "${var.zone}"
}

# Zip up folder
data "archive_file" "kunskapfiles" {
  type = "zip"
  output_path = "kunskap.zip"
  source_dir = "kunskap"
}


provider "google-beta" {
  project = "${var.projectid}"
  region = "${var.region}"
  zone = "${var.zone}"
}

resource "google_storage_bucket" "bucket" {
  name = "${var.bucketname}"
  provider = "google"
}

resource "google_storage_bucket_object" "folder" {
  provider = "google"
  name = "kunskap.zip"
  source = "kunskap.zip"
  bucket = "${google_storage_bucket.bucket.name}"
}

resource "google_pubsub_topic" "topic" {
  name = "${var.topic}"
}

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
}

resource "google_cloud_scheduler_job" "job"{
  provider = "google-beta"
  name = "${var.jobid}"
  schedule = "${var.frequency}"
  pubsub_target {
    topic_name = "projects/${var.projectid}/topics/${var.topic}"
    data = "abcd"
  }
}