# AWS → Wazuh SIEM Integration

A self-hosted Wazuh SIEM ingesting AWS CloudTrail, GuardDuty, and VPC Flow Logs
via S3, with a least-privilege IAM read path and a real investigation example
surfaced during validation.

## Architecture

```
AWS Account
 ├─ CloudTrail     ──┐
 ├─ GuardDuty       ──┼─→  S3 Bucket  ──→  IAM read-only user (wazuh-reader)  ──→  Wazuh aws-s3 module  ──→  Dashboard
 └─ VPC Flow Logs  ──┘
```

- **CloudTrail** — account-wide API activity
- **GuardDuty** — threat detection findings, exported with a customer-managed KMS key
- **VPC Flow Logs** — network traffic for the account's default VPC
- **IAM** — a single `wazuh-reader` user scoped to exactly what the pipeline needs
- **Wazuh** — polls the S3 bucket every 10 minutes via the `aws-s3` wodle

## Why three sources, not one

| Source | Answers |
|---|---|
| CloudTrail | Who did what, from where, and did it succeed? |
| GuardDuty | Is this behavior actually malicious, and how severe? |
| VPC Flow Logs | What actually moved across the network? |

A single source gives a clue. Correlating all three — same identity, same IP,
same time window — turns isolated log lines into an investigable incident.

## Setup

See [`docs/`](./docs) for the full walkthrough of each piece:

- [01 – CloudTrail setup](./docs/01-cloudtrail-setup.md)
- [02 – GuardDuty + KMS export setup](./docs/02-guardduty-kms-setup.md)
- [03 – VPC Flow Logs setup](./docs/03-vpc-flow-logs-setup.md)
- [04 – Wazuh `aws-s3` module config](./docs/04-wazuh-aws-module-config.md)
- [05 – Troubleshooting log](./docs/05-troubleshooting-log.md)
- [06 – Least-privilege IAM policy](./docs/06-iam-least-privilege-policy.md)

Sanitized reference configs live in [`configs/`](./configs), and a single
setup script that automates the IAM/KMS/S3 plumbing is in
[`scripts/setup-aws-wazuh-integration.sh`](./scripts/setup-aws-wazuh-integration.sh).

## Investigation example: failed root console logins

While validating the pipeline, it surfaced a real finding rather than just
test data:

![Dashboard showing 3 failed root ConsoleLogin attempts](./screenshots/dashboard-investigation.png)

*(Add your own redacted screenshot here — see `screenshots/README.md`.)*

**What the data shows:**
- 3x `ConsoleLogin` failures for the **Root** user within under 1 second
- Rule 80254, severity level 5 — the highest level observed across 570+ events
  in the dataset

**Questions this raises for an analyst:**
- Is this a human mistyping credentials, or a scripted/brute-force attempt?
  (Sub-second spacing between attempts favors the latter.)
- Did a successful login follow shortly after, from the same or a different IP?
- Does the account have MFA enforced on root?

**Response steps this would justify in a live environment:**
1. Cross-reference the source IP against GuardDuty findings for related activity
2. Check the IAM credential report for root account MFA status
3. If attempts continue, consider blocking the source at the network layer and
   rotating root credentials

This single row demonstrates more investigative value than the 560+ routine
events combined — a reminder that volume isn't the goal, signal is.

## Least privilege in practice

The `wazuh-reader` IAM user went through several iterations as the pipeline
was built out — see the troubleshooting log for why each permission was
added. Final policy (also in [`configs/iam-policy-wazuh-reader.json`](./configs/iam-policy-wazuh-reader.json)):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid":"ListBucket","Effect":"Allow","Action":["s3:ListBucket","s3:GetBucketLocation"],"Resource":"arn:aws:s3:::<BUCKET_NAME>"},
    {"Sid":"ReadLogs","Effect":"Allow","Action":"s3:GetObject","Resource":"arn:aws:s3:::<BUCKET_NAME>/*"},
    {"Sid":"DecryptGuardDuty","Effect":"Allow","Action":"kms:Decrypt","Resource":"<KMS_KEY_ARN>"},
    {"Sid":"DescribeFlowLogs","Effect":"Allow","Action":"ec2:DescribeFlowLogs","Resource":"*"}
  ]
}
```

No IAM, EC2 write, or cross-bucket access of any kind.

## Known limitations

- Detection latency is roughly 5–25 minutes end to end (CloudTrail delivery
  delay + Wazuh's 10-minute polling interval) — near-real-time, not real-time.
- VPC Flow Logs produce little signal without active traffic, and Wazuh's
  default ruleset doesn't alert on routine `ACCEPT` traffic.
- GuardDuty sample findings used to validate the pipeline are synthetic and
  were archived afterward.

## What's next

Extending this into a full attack-simulation lab: a monitored host attacked
from Kali, walking the complete detect → investigate → remediate → mitigate
→ document lifecycle.

## Disclaimer

This repo documents a personal home-lab project. All account IDs, bucket
names, IP addresses, and key ARNs shown in configs and docs are placeholders
or have been redacted from screenshots. Nothing here is a copy-paste
production deployment — review and adapt before using any of it elsewhere.
