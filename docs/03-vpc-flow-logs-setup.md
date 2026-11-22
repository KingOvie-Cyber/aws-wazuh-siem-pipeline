# 03 — VPC Flow Logs Setup

## Goal
Capture network-layer traffic (accept/reject, source/destination, ports,
byte counts) for the VPC and deliver it to the same S3 bucket.

## Steps

### 1. Create the flow log

```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids <VPC_ID> \
  --traffic-type ALL \
  --log-destination-type s3 \
  --log-destination arn:aws:s3:::<BUCKET_NAME> \
  --max-aggregation-interval 600
```

Or via console: VPC > Your VPCs > select VPC > Flow logs tab > Create flow log
> Destination: S3 bucket.

- `--traffic-type ALL` captures both accepted and rejected traffic — rejected
  traffic is often the more interesting signal (blocked port scans, etc.)
- `--max-aggregation-interval 600` (10 minutes) is cheaper than 60 seconds;
  use 60 if you need faster-arriving records for a live test

### 2. Add delivery permissions to the bucket policy

Flow Logs delivery uses the `delivery.logs.amazonaws.com` service principal,
distinct from GuardDuty's and CloudTrail's. See
[`configs/s3-bucket-policy.json`](../configs/s3-bucket-policy.json) for the
`AWSLogDeliveryAclCheck` / `AWSLogDeliveryWrite` statements, scoped with
`aws:SourceAccount` and an `ArnLike` condition on `aws:SourceArn` matching
`arn:aws:logs:<REGION>:<ACCOUNT_ID>:*`.

### 3. Where the logs land

```
s3://<BUCKET_NAME>/AWSLogs/<ACCOUNT_ID>/vpcflowlogs/<REGION>/<YYYY>/<MM>/<DD>/
```

### 4. Confirm it's active

```bash
aws ec2 describe-flow-logs \
  --query 'FlowLogs[].[FlowLogId,FlowLogStatus,LogDestination]' \
  --output table
```
Status should read `ACTIVE`.

## A gotcha: this needs EC2 permissions too, not just S3

Wazuh's `aws-s3` module, for the `vpcflow` bucket type, calls
`ec2:DescribeFlowLogs` to resolve flow log metadata before reading the S3
objects. Forgetting this permission on the reader IAM user produces
`UnauthorizedOperation` even though the S3 policy is correct. See
[05 — Issue 5](./05-troubleshooting-log.md#issue-5).

## A note on signal volume

An idle VPC with no running instances produces almost no flow data — files
can be as small as ~160 bytes (header only, no records). To validate the
pipeline end-to-end, launch a short-lived test instance and generate some
traffic (e.g. `ping -c 200 8.8.8.8`), then terminate it once confirmed.

Wazuh's default ruleset does not alert on routine `ACCEPT` traffic — flow
logs are primarily useful as corroborating evidence when pivoting from a
CloudTrail or GuardDuty alert, not as a standalone alert source without
custom rules.
