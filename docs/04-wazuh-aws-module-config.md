# 04 — Wazuh `aws-s3` Module Configuration

## Goal
Configure Wazuh's manager to poll the S3 bucket and ingest all three log
types.

## Full config block

See [`configs/ossec-aws-s3-block.xml`](../configs/ossec-aws-s3-block.xml)
for the complete, sanitized block. Key points below.

```xml
<wodle name="aws-s3">
  <disabled>no</disabled>
  <interval>10m</interval>
  <run_on_start>yes</run_on_start>
  <skip_on_error>yes</skip_on_error>

  <bucket type="cloudtrail">
    <name><BUCKET_NAME></name>
    <aws_account_id><ACCOUNT_ID></aws_account_id>
    <regions><REGION></regions>
    <only_logs_after>2026-NOV-01</only_logs_after>
    <aws_profile>wazuh</aws_profile>
  </bucket>

  <bucket type="guardduty">
    <name><BUCKET_NAME></name>
    <path>AWSLogs/<ACCOUNT_ID>/GuardDuty</path>
    <regions><REGION></regions>
    <only_logs_after>2026-NOV-01</only_logs_after>
    <aws_profile>wazuh</aws_profile>
  </bucket>

  <bucket type="vpcflow">
    <name><BUCKET_NAME></name>
    <aws_account_id><ACCOUNT_ID></aws_account_id>
    <path>AWSLogs/<ACCOUNT_ID>/vpcflowlogs</path>
    <regions><REGION></regions>
    <only_logs_after>2026-NOV-01</only_logs_after>
    <aws_profile>wazuh</aws_profile>
  </bucket>
</wodle>
```

### Important: the `cloudtrail` bucket type needs no `<path>`

The module builds `AWSLogs/<account>/CloudTrail/<region>/` internally. Adding
`<path>` here doubles the prefix and silently produces "no logs to process."
The `guardduty` and `vpcflow` types *do* need an explicit `<path>`, since
their internal path-building differs. See
[05 — Issue 3](./05-troubleshooting-log.md#issue-3) for the exact symptom.

## Credentials

```ini
# /root/.aws/credentials
[wazuh]
aws_access_key_id = <ACCESS_KEY_ID>
aws_secret_access_key = <SECRET_ACCESS_KEY>
```

The profile name in `<aws_profile>` must exactly match the header in this
file — a mismatch fails with `The config profile (wazuh) could not be found`
and gives no other indication of the cause.

## Verifying it's working

```bash
sudo systemctl restart wazuh-manager
sleep 90
sudo grep -a "aws-s3" /var/ossec/logs/ossec.log | grep -a -E "WARNING|ERROR|finished" | tail -10
```

A healthy run shows `Fetching logs finished` with no `WARNING` lines (aside
from expected "no files found" messages for sources with no new data).

To confirm alerts are actually being generated:

```bash
sudo grep -a '"groups":\["amazon"' /var/ossec/logs/alerts/alerts.json | tail -3
```

## Debugging

Enable verbose logging temporarily:

```bash
echo "wazuh_modules.debug=2" | sudo tee -a /var/ossec/etc/local_internal_options.conf
sudo systemctl restart wazuh-manager
```

Or run the module manually for immediate, verbose output on one bucket type:

```bash
sudo /var/ossec/wodles/aws/aws-s3 \
  --bucket <BUCKET_NAME> \
  --aws_profile wazuh \
  --aws_account_id <ACCOUNT_ID> \
  --type cloudtrail --debug 2 --regions <REGION> \
  --only_logs_after 2026-NOV-01
```

**Remember to turn debug off afterward** — it's verbose and not needed for
normal operation. Also remember to set `<logall>` / `<logall_json>` back to
`no` in the `<global>` block if you enabled them to inspect raw archives;
left on, they grow the disk quickly.
