variable projectid {
  default = "project-kunskap"
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