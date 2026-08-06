#!/usr/bin/env bash
#
# Bootstrap the S3 bucket and DynamoDB table used for Terraform remote state.
# One-time setup, run outside Terraform itself, before the first `terraform init`.
# Safe to run multiple times — checks for existing resources before creating them.
#
# Usage: scripts/bootstrap-state.sh [--region eu-central-1]

set -euo pipefail

REGION="eu-central-1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--region eu-central-1]" >&2
      exit 1
      ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="petclinic-terraform-state-${ACCOUNT_ID}"
TABLE_NAME="petclinic-terraform-locks"

echo "Region:     ${REGION}"
echo "Account ID: ${ACCOUNT_ID}"
echo "S3 bucket:  ${BUCKET_NAME}"
echo "DynamoDB:   ${TABLE_NAME}"
echo

# --- S3 bucket for state -----------------------------------------------

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  EXISTING_LOCATION=$(aws s3api get-bucket-location --bucket "${BUCKET_NAME}" --query LocationConstraint --output text)
  # S3 reports "None" (LocationConstraint null) for buckets in us-east-1.
  if [[ "${EXISTING_LOCATION}" == "None" ]]; then
    EXISTING_LOCATION="us-east-1"
  fi
  if [[ "${EXISTING_LOCATION}" != "${REGION}" ]]; then
    echo "ERROR: S3 bucket ${BUCKET_NAME} already exists but is in region" >&2
    echo "  ${EXISTING_LOCATION}, not the requested ${REGION}." >&2
    echo "  S3 bucket names are globally unique, so this name cannot be" >&2
    echo "  recreated in ${REGION} while it still exists in ${EXISTING_LOCATION}." >&2
    echo "  Either re-run with --region ${EXISTING_LOCATION}, or delete the" >&2
    echo "  existing bucket first if you intend to recreate it in ${REGION}." >&2
    exit 1
  fi
  echo "S3 bucket ${BUCKET_NAME} already exists in ${REGION} — skipping creation."
else
  echo "Creating S3 bucket ${BUCKET_NAME}..."
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
fi

echo "Enabling versioning on ${BUCKET_NAME}..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

echo "Enabling default encryption (AES256) on ${BUCKET_NAME}..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'

echo "Blocking all public access on ${BUCKET_NAME}..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# --- DynamoDB table for locking -----------------------------------------

if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  echo "DynamoDB table ${TABLE_NAME} already exists — skipping creation."
else
  echo "Creating DynamoDB table ${TABLE_NAME}..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --region "${REGION}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=Project,Value=petclinic Key=ManagedBy,Value=bootstrap-script

  echo "Waiting for table ${TABLE_NAME} to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}"
fi

echo
echo "Bootstrap complete."
echo
echo "backend.tf in terraform/environments/{dev,prod}/ expects:"
echo "  bucket         = \"${BUCKET_NAME}\""
echo "  dynamodb_table = \"${TABLE_NAME}\""
echo "  region         = \"${REGION}\""
echo
echo "If the account ID differs from the placeholder already in backend.tf, update it there."
