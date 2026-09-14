#!/usr/bin/env python3
"""Discover importable bootstrap resources without changing AWS state.

Only the exact names generated for a deployment are considered.  An existing
resource is importable only when all ownership tags match; discovery failures
are fatal rather than being treated as an absent resource.
"""
import argparse
import json
import subprocess
import sys


class AwsError(RuntimeError):
    pass


def aws(region, *args):
    command = ["aws", *args, "--region", region, "--output", "json"]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise AwsError("AWS read failed (%s): %s" % (" ".join(args), result.stderr.strip()))
    try:
        return json.loads(result.stdout or "{}")
    except json.JSONDecodeError as error:
        raise AwsError("AWS read returned invalid JSON (%s): %s" % (" ".join(args), error))


def owns(tags, expected):
    return all(tags.get(key) == value for key, value in expected.items())


def bucket_exists(region, bucket):
    # list-buckets succeeds only for buckets owned by the current principal;
    # that is preferable to treating head-bucket's opaque 403 as absence.
    buckets = aws(region, "s3api", "list-buckets").get("Buckets", [])
    return any(item.get("Name") == bucket for item in buckets)


def bucket_tags(region, bucket):
    value = aws(region, "s3api", "get-bucket-tagging", "--bucket", bucket)
    return {item["Key"]: item["Value"] for item in value.get("TagSet", [])}


def table(region, name):
    try:
        return aws(region, "dynamodb", "describe-table", "--table-name", name).get("Table")
    except AwsError as error:
        # This is the only AWS error with absence semantics that this helper
        # accepts. Every other permission/network/service error remains fatal.
        if "ResourceNotFoundException" in str(error):
            return None
        raise


def kms_keys_with_tags(region, expected, account_id):
    keys = aws(region, "kms", "list-keys").get("Keys", [])
    matches = []
    for key in keys:
        key_id = key["KeyId"]
        metadata = aws(region, "kms", "describe-key", "--key-id", key_id).get("KeyMetadata", {})
        arn = metadata.get("Arn", "")
        if (metadata.get("KeyState") != "Enabled" or metadata.get("KeyManager") != "CUSTOMER" or
                not arn.startswith("arn:aws:kms:%s:%s:key/" % (region, account_id))):
            continue
        tags = aws(region, "kms", "list-resource-tags", "--key-id", key_id).get("Tags", [])
        if owns({tag["TagKey"]: tag["TagValue"] for tag in tags}, expected):
            matches.append({"arn": arn, "id": metadata.get("KeyId", key_id)})
    return matches


def kms_alias(region, deployment, key):
    alias_name = "alias/node-operator-%s-bootstrap-state" % deployment
    aliases = aws(region, "kms", "list-aliases").get("Aliases", [])
    matches = [item for item in aliases if item.get("AliasName") == alias_name]
    if not matches:
        return None
    if len(matches) != 1 or matches[0].get("TargetKeyId") not in (key["arn"], key["id"]):
        raise AwsError("refusing to adopt KMS alias %s with an unexpected target" % alias_name)
    return alias_name


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", required=True)
    parser.add_argument("--deployment", required=True)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--logs-bucket", required=True)
    parser.add_argument("--table", required=True)
    parser.add_argument("--state-address", action="append", default=[])
    parser.add_argument("--state-id", action="append", default=[])
    args = parser.parse_args()
    expected = {"Project": "node-operator", "Deployment": args.deployment, "DeploymentRegion": args.region,
                "ManagedBy": "terraform", "Purpose": "terraform-state-bootstrap"}
    present = set(args.state_address)
    state_ids = {}
    for item in args.state_id:
        address, separator, identifier = item.partition("=")
        if not separator or not address or not identifier:
            raise AwsError("invalid Terraform state identity")
        state_ids[address] = identifier

    def emit(address, identifier):
        if address not in present:
            print("%s\t%s" % (address, identifier))
        elif state_ids.get(address) != identifier:
            raise AwsError("Terraform state identity for %s does not match the selected bootstrap resource" % address)

    state_bucket_exists = bucket_exists(args.region, args.bucket)
    for address, name in (("aws_s3_bucket.state", args.bucket), ("aws_s3_bucket.state_access_logs", args.logs_bucket)):
        if bucket_exists(args.region, name):
            if owns(bucket_tags(args.region, name), expected):
                emit(address, name)
            else:
                raise AwsError("refusing to adopt unowned S3 bucket %s" % name)
        elif address in present:
            raise AwsError("Terraform state records missing S3 bucket %s" % name)

    found_table = table(args.region, args.table)
    if found_table:
        tags = aws(args.region, "dynamodb", "list-tags-of-resource", "--resource-arn", found_table["TableArn"]).get("Tags", [])
        if owns({tag["Key"]: tag["Value"] for tag in tags}, expected):
            emit("aws_dynamodb_table.lock", args.table)
        else:
            raise AwsError("refusing to adopt unowned DynamoDB table %s" % args.table)
    elif "aws_dynamodb_table.lock" in present:
        raise AwsError("Terraform state records missing DynamoDB table %s" % args.table)

    keys = kms_keys_with_tags(args.region, expected, args.account_id)
    if len(keys) > 1:
        raise AwsError("refusing to choose between multiple owned bootstrap KMS keys")
    if keys:
        emit("aws_kms_key.state", keys[0]["id"])
        alias = kms_alias(args.region, args.deployment, keys[0])
        if alias:
            emit("aws_kms_alias.state", alias)
        elif "aws_kms_alias.state" in present:
            raise AwsError("Terraform state records a missing bootstrap KMS alias")
    elif "aws_kms_key.state" in present:
        raise AwsError("Terraform state records a missing owned bootstrap KMS key")
    if state_bucket_exists:
        # An existing state bucket is never silently moved to a newly-created
        # key. Its observed default encryption must bind to this exact key.
        encryption = aws(args.region, "s3api", "get-bucket-encryption", "--bucket", args.bucket)
        rules = encryption.get("ServerSideEncryptionConfiguration", {}).get("Rules", [])
        observed = rules[0].get("ApplyServerSideEncryptionByDefault", {}).get("KMSMasterKeyID") if rules else None
        objects = aws(args.region, "s3api", "list-objects-v2", "--bucket", args.bucket, "--max-keys", "1").get("Contents", [])
        if not keys and not objects:
            return
        if len(keys) != 1 or not observed or observed not in (keys[0]["arn"], keys[0]["id"]):
            raise AwsError("refusing to change encryption on existing state bucket without its owned bootstrap KMS key")


if __name__ == "__main__":
    try:
        main()
    except AwsError as error:
        print("bootstrap reconciliation: %s" % error, file=sys.stderr)
        sys.exit(1)
