# 05 — Troubleshooting Log

Real issues hit while building this pipeline, documented as encountered.
Format: symptom → root cause → fix → lesson.

---

## Issue 1: Config pointed at a non-existent bucket

**Symptom:**
```
wazuh-modulesd:aws-s3 WARNING: ... NoSuchBucket ... The specified bucket does not exist
```

**Root cause:** The CloudTrail S3 bucket was deleted and recreated (new
random suffix in the name). `ossec.conf` still referenced the old bucket
name.

**Fix:** Updated the `<name>` field in all three `<bucket>` blocks to the new
bucket, re-scoped the IAM policy to it, and re-pointed GuardDuty's export
destination and the VPC Flow Log destination to match.

**Lesson:** S3 bucket names aren't stable identifiers across infrastructure
changes — treat them as config, not constants. A migration touches every
downstream consumer: Wazuh config, IAM policy, GuardDuty export settings,
and flow log destinations, all independently.

---

## Issue 2: AccessDenied on s3:ListBucket

**Symptom:**
```
An error occurred (AccessDenied) when calling the ListObjectsV2 operation:
User: .../wazuh-reader is not authorized to perform: s3:ListBucket
```

**Root cause:** The `wazuh-reader` IAM user had no identity-based policy
granting access to the bucket at all.

**Fix:** Added a least-privilege inline policy scoped to exactly one bucket
(`s3:ListBucket`, `s3:GetBucketLocation`, `s3:GetObject`).

**Lesson:** Monitoring tools need explicit least-privilege grants — they
don't inherit visibility into anything by default, which is the correct,
expected behavior, not a bug.

---

## Issue 3: Doubled S3 path for CloudTrail

**Symptom:** Debug output showed the module checking:
```
AWSLogs/<account>/CloudTrail/AWSLogs/<account>/CloudTrail/<region>/...
```

**Root cause:** Wazuh's `aws-s3` module automatically constructs the
`AWSLogs/<account>/CloudTrail/<region>/` path internally for the
`cloudtrail` bucket type. Adding that same path manually via `<path>`
doubled the prefix, so the module looked in a folder that never existed and
silently reported "no logs to process."

**Fix:** Removed the `<path>` element entirely from the CloudTrail bucket
block.

**Lesson:** Read the module's debug marker line carefully before adding
config elements defensively — an extra, seemingly-harmless field actively
broke a working integration here.

---

## Issue 4: GuardDuty findings existed in S3 but produced no alerts

**Symptom:** No warnings in the Wazuh log, bucket listing confirmed files
existed, but no GuardDuty alerts appeared in `alerts.json`.

**Root cause:** GuardDuty findings are encrypted on export with a
customer-managed KMS key. `wazuh-reader` had S3 read access but no
`kms:Decrypt` permission on that key — a separate IAM grant entirely.

**Fix:** Added a scoped `kms:Decrypt` statement for the specific key ARN to
`wazuh-reader`'s policy.

**Lesson:** S3 object read access (`s3:GetObject`) succeeding does not mean
the *content* of the object is usable — KMS-encrypted objects need a
distinct decrypt grant, and a missing one fails silently rather than with an
obvious error.

---

## Issue 5: ec2:DescribeFlowLogs AccessDenied

**Symptom:**
```
An error occurred (UnauthorizedOperation) when calling the DescribeFlowLogs
operation: ... is not authorized to perform: ec2:DescribeFlowLogs
```
Exit code 12, only on the `vpcflow` bucket block.

**Root cause:** For the `vpcflow` bucket type, Wazuh's module calls the EC2
API (`DescribeFlowLogs`) to resolve flow log metadata before reading the S3
objects themselves — a dependency outside S3 entirely.

**Fix:** Added `ec2:DescribeFlowLogs` (resource `*`, the only scope this
action supports) to `wazuh-reader`'s policy.

**Lesson:** Not every "S3 log reader" integration is pure S3 — check a
module's actual API calls (via debug logging) rather than assuming a
read-only S3 policy is sufficient for every log type.

---

## Issue 6: AWS-managed KMS key rejected for GuardDuty export

**Symptom:** Console error on saving GuardDuty export settings:
```
The request failed because the GuardDuty service principal does not have
permission to the KMS key or the resource specified by the destinationArn
parameter.
```

**Root cause:** `aws/s3` is an AWS-owned, AWS-managed key. Its key policy
cannot be edited by account users, so there's no way to add a statement
granting `guardduty.amazonaws.com` permission to use it.

**Fix:** Created a customer-managed KMS key, added a key policy statement
granting `guardduty.amazonaws.com` `kms:GenerateDataKey` and `kms:Encrypt`,
scoped with `aws:SourceAccount` / `aws:SourceArn` conditions tied to the
specific GuardDuty detector.

**Lesson:** Any AWS service that needs to write to a KMS-encrypted
destination on your behalf requires a customer-managed key — AWS-managed
keys are a dead end for any cross-service permission grant.

---

## Issue 7: Credential profile mismatch

**Symptom:**
```
wazuh-modulesd:aws-s3 WARNING: ... The config profile (wazuh) could not be found
```

**Root cause:** `ossec.conf` referenced `<aws_profile>wazuh</aws_profile>`,
but `/root/.aws/credentials` used the header `[default]`.

**Fix:** Aligned both to the same profile name.

**Lesson:** Config references and credential file headers are matched by
exact string with no fuzzy fallback — a reasonable-looking mismatch produces
a clear error message, but only if you're looking at the right log.

---

## Issue 8: GuardDuty export destination rejected — folder doesn't exist

**Symptom:**
```
BadRequestException: The resource folder specified in the destinationArn
parameter does not exist.
```

**Root cause:** GuardDuty requires the target prefix to already exist as an
object in the bucket before accepting it as an export destination — a brand
new bucket with no `GuardDuty/` folder fails this check.

**Fix:** Created an empty placeholder object at the expected prefix before
retrying:
```bash
aws s3api put-object --bucket <BUCKET_NAME> --key AWSLogs/<ACCOUNT_ID>/GuardDuty/
```

**Lesson:** Some AWS services validate destination *existence*, not just
permission — a correctly-scoped IAM/bucket policy can still fail if the
literal object/prefix hasn't been created yet.
