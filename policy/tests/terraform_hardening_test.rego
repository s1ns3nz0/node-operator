package nodeoperator.terraform_test

import rego.v1
import data.nodeoperator.terraform

secure_input := {
  "baseline": {
    "eks_clusters": [{
      "address": "aws_eks_cluster.node_operator",
      "endpoint_private_access": true,
      "endpoint_public_access": false,
      "encrypted_resources": ["secrets"],
      "kms_key_arn": "arn:aws:kms:ap-northeast-2:111122223333:key/01234567-89ab-cdef-0123-456789abcdef"
    }],
    "managed_node_groups": [{
      "address": "aws_eks_node_group.operators",
      "instance_types": ["m7i.2xlarge"],
      "scaling": {"min_size": 2, "desired_size": 2, "max_size": 3},
      "availability_zones": ["ap-northeast-2a", "ap-northeast-2c"],
      "public_ip_association": false,
      "private_subnet_ids": ["subnet-private-a", "subnet-private-c"]
    }],
    "iam_policies": [{
      "address": "aws_iam_role_policy.node_observer",
      "statements": [{
        "address": "aws_iam_role_policy.node_observer.statement[0]",
        "effect": "Allow",
        "actions": ["ec2:DescribeInstances", "eks:DescribeCluster"],
        "resources": ["*"]
      }, {
        "address": "aws_iam_role_policy.node_observer.statement[1]",
        "effect": "Allow",
        "actions": ["s3:GetObject"],
        "resources": ["arn:aws:s3:::node-operator-evidence/reports/approved-report.json"]
      }]
    }]
  }
}

test_secure_baseline_passes if {
  denial := terraform.deny with input as secure_input
  count(denial) == 0
}

test_public_endpoint_is_rejected if {
  fixture := object.union(secure_input, {"baseline": object.union(secure_input.baseline, {"eks_clusters": [object.union(secure_input.baseline.eks_clusters[0], {"endpoint_public_access": true})]})})
  denial := terraform.deny with input as fixture
  denial[_].id == "terraform.eks.public-endpoint"
}

test_missing_control_plane_encryption_is_rejected if {
  fixture := object.union(secure_input, {"baseline": object.union(secure_input.baseline, {"eks_clusters": [object.union(secure_input.baseline.eks_clusters[0], {"encrypted_resources": [], "kms_key_arn": ""})]})})
  denial := terraform.deny with input as fixture
  denial[_].id == "terraform.eks.secrets-encryption"
  denial[_].id == "terraform.eks.kms-key"
}

test_invalid_node_capacity_or_topology_is_rejected if {
  fixture := object.union(secure_input, {"baseline": object.union(secure_input.baseline, {"managed_node_groups": [object.union(secure_input.baseline.managed_node_groups[0], {"instance_types": ["m7i.large"], "scaling": {"min_size": 1, "desired_size": 1, "max_size": 4}, "availability_zones": ["ap-northeast-2a", "ap-northeast-2a"], "public_ip_association": true, "private_subnet_ids": ["subnet-private-a"]})]})})
  denial := terraform.deny with input as fixture
  denial[_].id == "terraform.node-group.instance-type"
  denial[_].id == "terraform.node-group.scaling"
  denial[_].id == "terraform.node-group.two-az"
  denial[_].id == "terraform.node-group.public-ip"
  denial[_].id == "terraform.node-group.private-subnets"
}

test_mutating_or_broad_data_iam_is_rejected if {
  insecure_policy := {"address": "aws_iam_role_policy.node_observer", "statements": [{"address": "aws_iam_role_policy.node_observer.statement[0]", "effect": "Allow", "actions": ["ec2:TerminateInstances", "s3:GetObject", "rds-db:connect"], "resources": ["*"]}]}
  fixture := object.union(secure_input, {"baseline": object.union(secure_input.baseline, {"iam_policies": [insecure_policy]})})
  denial := terraform.deny with input as fixture
  denial[_].id == "terraform.iam.mutation"
  denial[_].id == "terraform.iam.broad-data-access"
}

test_missing_or_malformed_baseline_is_rejected if {
  denial := terraform.deny with input as {}
  denial[_].id == "terraform.baseline.malformed"
}
