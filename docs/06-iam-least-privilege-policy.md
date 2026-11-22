# 06 — Least-Privilege IAM Policy for the Reader User

## Principle

The `wazuh-reader` IAM user exists for exactly one purpose: let the Wazuh
manager read log objects from one S3 bucket. It should be able to do
**nothing else** — not list other buckets, not touch IAM, not write
anything.

## Final policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::<BUCKET_NAME>"
    },
    {
      "Sid": "ReadLogs",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<BUCKET_NAME>/*"
    },
    {
      "Sid": "DecryptGuardDuty",
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "<KMS_KEY_ARN>"
    },
    {
      "Sid": "DescribeFlowLogs",
      "Effect": "Allow",
      "Action": "ec2:DescribeFlowLogs",
      "Resource": "*"
    }
  ]
}
```

Also at [`configs/iam-policy-wazuh-reader.json`](../configs/iam-policy-wazuh-reader.json).

## Why each statement exists

| Statement | Why it's needed |
|---|---|
| `ListBucket` | Required to enumerate objects under a prefix before reading them |
| `ReadLogs` | Required to actually download each log file |
| `DecryptGuardDuty` | GuardDuty findings are KMS-encrypted on export; without this, files download but can't be read (see troubleshooting Issue 4) |
| `DescribeFlowLogs` | The `vpcflow` module type calls this EC2 API before reading S3 objects (see troubleshooting Issue 5) |

Note: `ec2:DescribeFlowLogs` only supports `Resource: "*"` — AWS does not
allow scoping this action to a specific flow log ARN. It remains read-only
and has no destructive capability, so this is an acceptable least-privilege
exception.

## What this user explicitly cannot do

- List or access any other S3 bucket
- Write, delete, or modify any S3 object
- Create, modify, or delete IAM users, roles, or policies
- Launch, stop, or terminate EC2 instances
- Read or modify any KMS key other than the one explicitly granted
- Access any AWS service not listed above

## Verifying the boundary

```bash
# Should succeed
aws s3 ls s3://<BUCKET_NAME>/ --profile wazuh

# Should fail with AccessDenied — confirms the boundary holds
aws s3 ls --profile wazuh
aws iam list-users --profile wazuh
```

## Credential hygiene notes

- Access keys for `wazuh-reader` should be rotated periodically, and
  immediately if ever exposed (e.g. accidentally shown in a screenshot or
  terminal recording).
- IAM allows a maximum of two active access keys per user — deactivate and
  delete old ones rather than letting them accumulate.
- Store credentials only at `/root/.aws/credentials` on the Wazuh manager
  (file permissions `600`), never committed to version control.
