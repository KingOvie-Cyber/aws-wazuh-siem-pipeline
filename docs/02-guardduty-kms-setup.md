# 02 — GuardDuty Findings Export Setup

## Goal
Export GuardDuty findings to the same S3 bucket used for CloudTrail, encrypted
with a customer-managed KMS key, so Wazuh can read them.

## Why a customer-managed key is required

GuardDuty's export feature needs to write encrypted objects to S3, which
requires a KMS key policy statement granting `guardduty.amazonaws.com`
permission to use the key. **AWS-managed keys (e.g. `aws/s3`) cannot be used**
because their key policy is owned by AWS and cannot be edited. See
[05 — Issue 6](./05-troubleshooting-log.md#issue-6) for the exact error this
produces if attempted.

## Steps

### 1. Create a customer-managed KMS key
- KMS > Customer managed keys > Create key
- Key type: Symmetric, Encrypt and decrypt
- Alias: e.g. `guardduty-findings-key`
- Key administrators: yourself or an admin IAM user/role (not required —
  the account root always retains control)

### 2. Add the GuardDuty statement to the key policy

See [`configs/kms-key-policy.json`](../configs/kms-key-policy.json). The
important statement:

```json
{
  "Sid": "AllowGuardDutyKey",
  "Effect": "Allow",
  "Principal": {"Service": "guardduty.amazonaws.com"},
  "Action": ["kms:GenerateDataKey", "kms:Encrypt"],
  "Resource": "<KMS_KEY_ARN>",
  "Condition": {
    "StringEquals": {
      "aws:SourceAccount": "<ACCOUNT_ID>",
      "aws:SourceArn": "<GUARDDUTY_DETECTOR_ARN>"
    }
  }
}
```

Always keep the existing `Enable IAM User Permissions` (root) statement —
removing it can lock you out of managing the key.

### 3. Add the GuardDuty statements to the S3 bucket policy

See [`configs/s3-bucket-policy.json`](../configs/s3-bucket-policy.json).
GuardDuty needs `s3:GetBucketLocation` on the bucket and `s3:PutObject` on
objects, both scoped with `aws:SourceAccount` and `aws:SourceArn` conditions
tied to the specific GuardDuty detector. **Merge these into the existing
policy — do not overwrite it**, since CloudTrail's statements must remain.

### 4. Configure the export destination

- GuardDuty > Settings > Findings export options > Edit
- S3 bucket ARN: `arn:aws:s3:::<BUCKET_NAME>`
- KMS key ARN: the customer-managed key from step 1
- Save

If the bucket doesn't yet have a `GuardDuty/` folder under
`AWSLogs/<ACCOUNT_ID>/`, GuardDuty will reject the destination with
`InvalidInputException`. Create an empty placeholder object first:

```bash
aws s3api put-object --bucket <BUCKET_NAME> --key AWSLogs/<ACCOUNT_ID>/GuardDuty/
```

### 5. Give wazuh-reader decrypt permission

GuardDuty findings are encrypted on write; Wazuh needs `kms:Decrypt` on the
same key to read them back. This is a separate grant from S3 read access —
see [05 — Issue 4](./05-troubleshooting-log.md#issue-4).

## Testing

GuardDuty > Settings > **Generate sample findings** produces ~450+ synthetic
findings across all finding types, useful for validating the full pipeline
without waiting for real threat activity. Archive them afterward
(Findings > select all > Actions > Archive) so they don't clutter the
dashboard going forward.

## Delivery timing

New findings typically export within ~5 minutes. Updates to existing
findings (repeated behavior) can take up to 6 hours to re-export.
