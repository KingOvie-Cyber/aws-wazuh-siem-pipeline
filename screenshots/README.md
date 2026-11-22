# Screenshots

Drop your own redacted dashboard screenshots here before pushing to GitHub.

Suggested filenames (referenced in the main README):
- `dashboard-investigation.png` — the Events view showing the failed root
  login rows (rule 80254, level 5) alongside surrounding events

## Before adding any screenshot, redact:

- `data.aws.sourceIPAddress` — your real public IP
- `data.aws.userIdentity.accessKeyId` — real access key IDs
- Your AWS account ID, if visible anywhere in the UI chrome
- Your S3 bucket name, if you'd rather not disclose it

**Use a solid, fully opaque black box over the entire field — not a blur.**
A blur filter preserves enough of the underlying pixel pattern to be
reversible, especially if the same value has ever appeared unblurred
elsewhere (e.g. an earlier screenshot, a chat history, a terminal recording).

The safest option is to remove the sensitive columns from the dashboard view
entirely (column header dropdown → Remove column) before taking the
screenshot, so there's nothing to redact after the fact.
