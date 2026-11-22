#!/usr/bin/env bash
#
# setup-aws-wazuh-integration.sh
#
# Merges the IAM, KMS, and S3 bucket policy statements needed for the
# Wazuh aws-s3 module to read CloudTrail, GuardDuty, and VPC Flow Logs
# from a single S3 bucket.
#
# This script MERGES into existing policies (it does not overwrite them),
# so running it against a bucket that already has a CloudTrail policy
# attached is safe.
#
# Run this in CloudShell or any environment with the AWS CLI and
# administrator-level credentials. It does NOT run on the Wazuh manager —
# wazuh-reader intentionally cannot make these changes itself.
#
# Requires: aws CLI, jq
#
# Usage:
#   Edit the variables below, then: bash setup-aws-wazuh-integration.sh

set -euo pipefail

# ---------- Variables — EDIT THESE ----------
REGION="us-east-1"
ACCOUNT="<ACCOUNT_ID>"
BUCKET="<BUCKET_NAME>"
KMS_KEY_ID="<KMS_KEY_ID>"          # just the key ID, not the full ARN
WAZUH_IAM_USER="wazuh-reader"
# ---------------------------------------------

KEY_ARN="arn:aws:kms:${REGION}:${ACCOUNT}:key/${KMS_KEY_ID}"

echo "== Looking up GuardDuty detector =="
DET=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds[0]' --output text)
DETARN="arn:aws:guardduty:${REGION}:${ACCOUNT}:detector/${DET}"
echo "Detector: $DET"

echo "== Looking up default VPC =="
VPC=$(aws ec2 describe-vpcs --region "$REGION" --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text)
echo "Default VPC: $VPC"

# ---------- 1. Merge the KMS key policy ----------
echo "== Updating KMS key policy =="
aws kms get-key-policy --key-id "$KMS_KEY_ID" --policy-name default --region "$REGION" \
  --query Policy --output text > /tmp/key_old.json

jq --arg key "$KEY_ARN" --arg acct "$ACCOUNT" --arg det "$DETARN" '
  .Statement |= (map(select(.Sid != "AllowGuardDutyKey")) + [{
    "Sid": "AllowGuardDutyKey",
    "Effect": "Allow",
    "Principal": {"Service": "guardduty.amazonaws.com"},
    "Action": ["kms:GenerateDataKey","kms:Encrypt"],
    "Resource": $key,
    "Condition": {"StringEquals": {"aws:SourceAccount": $acct, "aws:SourceArn": $det}}
  }])' /tmp/key_old.json > /tmp/key_new.json

aws kms put-key-policy --key-id "$KMS_KEY_ID" --policy-name default \
  --policy file:///tmp/key_new.json --region "$REGION"
echo "KMS key policy updated."

# ---------- 2. Merge the S3 bucket policy ----------
echo "== Updating S3 bucket policy =="
aws s3api get-bucket-policy --bucket "$BUCKET" --region "$REGION" \
  --query Policy --output text > /tmp/bucket_old.json 2>/dev/null \
  || echo '{"Version":"2012-10-17","Statement":[]}' > /tmp/bucket_old.json

jq --arg b "arn:aws:s3:::${BUCKET}" --arg acct "$ACCOUNT" --arg det "$DETARN" --arg r "$REGION" '
  .Statement |= (map(select(.Sid | test("^(AllowGuardDuty|AWSLogDelivery)") | not)) + [
    {"Sid":"AllowGuardDutyGetBucketLocation","Effect":"Allow","Principal":{"Service":"guardduty.amazonaws.com"},"Action":"s3:GetBucketLocation","Resource":$b,"Condition":{"StringEquals":{"aws:SourceAccount":$acct,"aws:SourceArn":$det}}},
    {"Sid":"AllowGuardDutyPutObject","Effect":"Allow","Principal":{"Service":"guardduty.amazonaws.com"},"Action":"s3:PutObject","Resource":($b+"/*"),"Condition":{"StringEquals":{"aws:SourceAccount":$acct,"aws:SourceArn":$det}}},
    {"Sid":"AWSLogDeliveryAclCheck","Effect":"Allow","Principal":{"Service":"delivery.logs.amazonaws.com"},"Action":["s3:GetBucketAcl","s3:ListBucket"],"Resource":$b,"Condition":{"StringEquals":{"aws:SourceAccount":$acct},"ArnLike":{"aws:SourceArn":("arn:aws:logs:"+$r+":"+$acct+":*")}}},
    {"Sid":"AWSLogDeliveryWrite","Effect":"Allow","Principal":{"Service":"delivery.logs.amazonaws.com"},"Action":"s3:PutObject","Resource":($b+"/AWSLogs/"+$acct+"/*"),"Condition":{"StringEquals":{"aws:SourceAccount":$acct,"s3:x-amz-acl":"bucket-owner-full-control"},"ArnLike":{"aws:SourceArn":("arn:aws:logs:"+$r+":"+$acct+":*")}}}
  ])' /tmp/bucket_old.json > /tmp/bucket_new.json

aws s3api put-bucket-policy --bucket "$BUCKET" --policy file:///tmp/bucket_new.json --region "$REGION"
echo "S3 bucket policy updated."

# ---------- 3. Create the GuardDuty folder placeholder ----------
echo "== Creating GuardDuty destination folder placeholder =="
aws s3api put-object --bucket "$BUCKET" --key "AWSLogs/${ACCOUNT}/GuardDuty/" --region "$REGION"

# ---------- 4. Point GuardDuty's export destination at this bucket ----------
echo "== Updating GuardDuty publishing destination =="
DEST=$(aws guardduty list-publishing-destinations --detector-id "$DET" --region "$REGION" \
  --query 'Destinations[0].DestinationId' --output text)

if [ "$DEST" != "None" ] && [ -n "$DEST" ]; then
  aws guardduty update-publishing-destination --detector-id "$DET" --destination-id "$DEST" --region "$REGION" \
    --destination-properties DestinationArn="arn:aws:s3:::${BUCKET}/AWSLogs/${ACCOUNT}/GuardDuty",KmsKeyArn="$KEY_ARN"
  echo "GuardDuty export destination updated."
else
  echo "No existing GuardDuty publishing destination found — create one via the console first:"
  echo "GuardDuty > Settings > Findings export options"
fi

# ---------- 5. Create/update the VPC Flow Log ----------
echo "== Creating VPC Flow Log =="
aws ec2 create-flow-logs --region "$REGION" --resource-type VPC --resource-ids "$VPC" \
  --traffic-type ALL --log-destination-type s3 --log-destination "arn:aws:s3:::${BUCKET}" \
  --max-aggregation-interval 600

# ---------- 6. Update the wazuh-reader IAM policy ----------
echo "== Updating wazuh-reader IAM policy =="
cat > /tmp/wazuh-reader-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid":"ListBucket","Effect":"Allow","Action":["s3:ListBucket","s3:GetBucketLocation"],"Resource":"arn:aws:s3:::${BUCKET}"},
    {"Sid":"ReadLogs","Effect":"Allow","Action":"s3:GetObject","Resource":"arn:aws:s3:::${BUCKET}/*"},
    {"Sid":"DecryptGuardDuty","Effect":"Allow","Action":"kms:Decrypt","Resource":"${KEY_ARN}"},
    {"Sid":"DescribeFlowLogs","Effect":"Allow","Action":"ec2:DescribeFlowLogs","Resource":"*"}
  ]
}
EOF

aws iam put-user-policy --user-name "$WAZUH_IAM_USER" \
  --policy-name WazuhBucketRead --policy-document file:///tmp/wazuh-reader-policy.json
echo "wazuh-reader IAM policy updated."

echo ""
echo "== Done =="
echo "Next steps:"
echo "1. Update ossec.conf on the Wazuh manager with bucket: ${BUCKET}, account: ${ACCOUNT}"
echo "2. sudo systemctl restart wazuh-manager"
echo "3. sudo grep -a \"aws-s3\" /var/ossec/logs/ossec.log | grep -a -E \"WARNING|ERROR|finished\" | tail -10"
