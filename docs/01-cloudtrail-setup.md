# 01 — CloudTrail Setup

## Goal
Capture account-wide API activity and deliver it to S3 for Wazuh to ingest.

## Steps

1. **CloudTrail > Trails > Create trail**
   - Name: `<TRAIL_NAME>` (e.g. `wazuh-trails`)
   - Apply to all regions: recommended, so activity in any region is captured
   - Management events: Read + Write
   - Data events: optional, adds cost — skip unless you need S3/Lambda object-level logging

2. **Destination S3 bucket**
   - Either let CloudTrail create one, or point it at an existing bucket
   - CloudTrail automatically attaches a bucket policy allowing
     `cloudtrail.amazonaws.com` to call `GetBucketAcl` and `PutObject`, scoped
     to a `SourceArn` condition matching your trail's ARN

3. **Confirm logging is active**
   ```bash
   aws cloudtrail get-trail-status --name <TRAIL_NAME>
   ```
   Look for `"IsLogging": true`.

4. **Where the logs land**
   ```
   s3://<BUCKET_NAME>/AWSLogs/<ACCOUNT_ID>/CloudTrail/<REGION>/<YYYY>/<MM>/<DD>/
   ```

## Delivery timing
CloudTrail batches and delivers log files roughly every 5 minutes, so expect
a 5–15 minute delay between an action occurring and its log file landing in S3.

## Note on the Wazuh-side path

Wazuh's `aws-s3` module **builds the `AWSLogs/<account>/CloudTrail/<region>/`
path itself** for the `cloudtrail` bucket type. Do not add this path manually
in `ossec.conf` — see [04](./04-wazuh-aws-module-config.md) and
[05](./05-troubleshooting-log.md#issue-3) for what happens if you do.
