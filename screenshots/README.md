# Screenshots

This folder holds the evidence images referenced throughout the README and docs — the Wazuh dashboard views used in the investigation walkthrough.

## Expected files

| Filename | Description |
|---|---|
| `dashboard-investigation.png` | Wazuh **Events** view, filtered to `rule.groups: amazon`, showing 571 ingested CloudTrail/GuardDuty events over a 48-hour window. The highlighted rows show 3 failed root `ConsoleLogin` attempts occurring within under 1 second of each other (rule 80254, severity level 5 — the highest level observed in the dataset), alongside surrounding successful logins, IAM activity, and two distinct API error types (`Client.InvalidInstanceID.Malformed` and `NoSuchEntityException`) for context. |

## What this image demonstrates

- End-to-end log delivery from AWS CloudTrail through S3 into the Wazuh dashboard
- Wazuh's rule engine correctly escalating failed root authentication attempts to a higher severity level than routine successful activity
- A realistic mix of event types (successes, client errors, and the high-severity failed-login cluster) in a single investigative view
- The basis for the root-login investigation example documented in the main README
