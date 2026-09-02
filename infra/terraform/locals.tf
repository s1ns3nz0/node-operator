locals {
  common_tags = merge(var.tags, {
    "ManagedBy"    = "terraform"
    "Project"      = "node-operator"
    "Environment"  = "baseline"
    "SecurityTier" = "private"
  })

  name_prefix = "${var.name}-baseline"
}
