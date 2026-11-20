#!/bin/bash

# AWS IAM Roles Anywhere Client Setup Script
# This script automates the client certificate generation and credential helper setup

set -e

# Default values
CLIENT_NAME="client-$(date +%Y%m%d-%H%M%S)"
CERT_VALIDITY_DAYS=365
SIGNING_HELPER_VERSION="1.4.0"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    echo "Usage: $0 --ca-arn <CA_ARN> --trust-anchor-arn <TRUST_ANCHOR_ARN> --profile-arn <PROFILE_ARN> --role-arn <ROLE_ARN> [OPTIONS]"
    echo ""
    echo "Required parameters:"
    echo "  --ca-arn              Private Certificate Authority ARN"
    echo "  --trust-anchor-arn    Trust Anchor ARN"
    echo "  --profile-arn         Profile ARN"
    echo "  --role-arn            IAM Role ARN"
    echo ""
    echo "Optional parameters:"
    echo "  --client-name         Client certificate Subject CN (default: client-YYYYMMDD-HHMMSS)."
    echo "                        Must match the stack's AllowedClientCommonNamePattern parameter."
    echo "  --cert-validity       Certificate validity in days (default: 365)"
    echo "  --helper-version      AWS Signing Helper version (default: 1.4.0)"
    echo "  --help               Show this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ca-arn)
            CA_ARN="$2"
            shift 2
            ;;
        --trust-anchor-arn)
            TRUST_ANCHOR_ARN="$2"
            shift 2
            ;;
        --profile-arn)
            PROFILE_ARN="$2"
            shift 2
            ;;
        --role-arn)
            ROLE_ARN="$2"
            shift 2
            ;;
        --client-name)
            CLIENT_NAME="$2"
            # The client name becomes the certificate Subject CN, which the role trust
            # policy uses for authorization. Restrict characters so the value cannot
            # inject additional subject fields (e.g. "/CN=...") into the CSR.
            if ! [[ "$CLIENT_NAME" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
                print_error "Client name must be 1-64 characters: letters, numbers, dot, underscore, or hyphen"
                exit 1
            fi
            shift 2
            ;;
        --cert-validity)
            CERT_VALIDITY_DAYS="$2"
            # Validate certificate validity days
            if ! [[ "$CERT_VALIDITY_DAYS" =~ ^[0-9]+$ ]] || [ "$CERT_VALIDITY_DAYS" -lt 1 ] || [ "$CERT_VALIDITY_DAYS" -gt 3650 ]; then
                print_error "Certificate validity days must be a number between 1 and 3650"
                exit 1
            fi
            shift 2
            ;;
        --helper-version)
            SIGNING_HELPER_VERSION="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            print_error "Unknown parameter: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$CA_ARN" || -z "$TRUST_ANCHOR_ARN" || -z "$PROFILE_ARN" || -z "$ROLE_ARN" ]]; then
    print_error "Missing required parameters"
    usage
fi

print_status "Starting IAM Roles Anywhere client setup..."
print_status "Client Name: $CLIENT_NAME"
print_status "Certificate Validity: $CERT_VALIDITY_DAYS days"

# Check prerequisites
print_status "Checking prerequisites..."

if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed"
    exit 1
fi

if ! command -v openssl &> /dev/null; then
    print_error "OpenSSL is not installed"
    exit 1
fi

# Test AWS CLI access
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS CLI is not configured or lacks permissions"
    exit 1
fi

print_status "Prerequisites check passed"

# Create working directory
WORK_DIR="./iam-roles-anywhere-${CLIENT_NAME}"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

print_status "Working directory: $(pwd)"

# Generate private key and CSR
print_status "Generating private key and certificate signing request..."

openssl req -out "${CLIENT_NAME}.csr" -new -newkey rsa:2048 -nodes -keyout "${CLIENT_NAME}-private-key.pem" -subj "/C=US/ST=Washington/L=Seattle/O=MyOrg/OU=IT/CN=${CLIENT_NAME}"

# Secure private key permissions
chmod 600 "${CLIENT_NAME}-private-key.pem"

if [[ $? -ne 0 ]]; then
    print_error "Failed to generate private key and CSR"
    exit 1
fi

print_status "Generated private key: ${CLIENT_NAME}-private-key.pem"
print_status "Generated CSR: ${CLIENT_NAME}.csr"

# Issue client certificate
print_status "Issuing client certificate..."

CERT_ARN=$(aws acm-pca issue-certificate \
    --certificate-authority-arn "$CA_ARN" \
    --csr "fileb://${CLIENT_NAME}.csr" \
    --signing-algorithm SHA256WITHRSA \
    --validity Value="$CERT_VALIDITY_DAYS",Type="DAYS" \
    --template-arn arn:aws:acm-pca:::template/EndEntityCertificate/V1 \
    --query 'CertificateArn' \
    --output text)

if [[ $? -ne 0 ]]; then
    print_error "Failed to issue certificate"
    exit 1
fi

print_status "Certificate ARN: $CERT_ARN"

# Wait for certificate to be issued
print_status "Waiting for certificate to be issued..."
sleep 5

# Get the certificate
print_status "Retrieving client certificate..."

aws acm-pca get-certificate \
    --certificate-authority-arn "$CA_ARN" \
    --certificate-arn "$CERT_ARN" \
    --query 'Certificate' \
    --output text > "${CLIENT_NAME}-certificate.pem"

if [[ $? -ne 0 ]]; then
    print_error "Failed to retrieve certificate"
    exit 1
fi

print_status "Generated certificate: ${CLIENT_NAME}-certificate.pem"

# Download AWS Signing Helper
print_status "Downloading AWS Signing Helper..."

PLATFORM=$(uname -s)
ARCH=$(uname -m)

case $PLATFORM in
    Linux)
        if [[ "$ARCH" == "x86_64" ]]; then
            HELPER_URL="https://rolesanywhere.amazonaws.com/releases/${SIGNING_HELPER_VERSION}/X86_64/Linux/aws_signing_helper"
        else
            print_error "Unsupported architecture: $ARCH"
            exit 1
        fi
        ;;
    Darwin)
        if [[ "$ARCH" == "x86_64" ]]; then
            HELPER_URL="https://rolesanywhere.amazonaws.com/releases/${SIGNING_HELPER_VERSION}/X86_64/Darwin/aws_signing_helper"
        elif [[ "$ARCH" == "arm64" ]]; then
            HELPER_URL="https://rolesanywhere.amazonaws.com/releases/${SIGNING_HELPER_VERSION}/ARM64/Darwin/aws_signing_helper"
        else
            print_error "Unsupported architecture: $ARCH"
            exit 1
        fi
        ;;
    *)
        print_error "Unsupported platform: $PLATFORM"
        exit 1
        ;;
esac

curl -L -o aws_signing_helper "$HELPER_URL"
chmod +x aws_signing_helper

if [[ $? -ne 0 ]]; then
    print_error "Failed to download AWS Signing Helper"
    exit 1
fi

print_status "Downloaded AWS Signing Helper"

# Create credential helper script
print_status "Creating credential helper script..."

cat > get-credentials.sh << EOF
#!/bin/bash
# AWS Roles Anywhere Credential Helper Script
# Generated on $(date)

./aws_signing_helper credential-process \\
    --certificate ${CLIENT_NAME}-certificate.pem \\
    --private-key ${CLIENT_NAME}-private-key.pem \\
    --trust-anchor-arn $TRUST_ANCHOR_ARN \\
    --profile-arn $PROFILE_ARN \\
    --role-arn $ROLE_ARN
EOF

chmod +x get-credentials.sh

# Create test script
cat > test-credentials.sh << EOF
#!/bin/bash
# Test script for AWS Roles Anywhere credentials

echo "Getting temporary credentials..."
CREDS=\$(./get-credentials.sh)

if [[ \$? -ne 0 ]]; then
    echo "Failed to get credentials"
    exit 1
fi

export AWS_ACCESS_KEY_ID=\$(echo "\$CREDS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=\$(echo "\$CREDS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=\$(echo "\$CREDS" | jq -r '.SessionToken')

echo "Testing credentials..."
aws sts get-caller-identity

echo "Testing S3 access..."
aws s3 ls
EOF

chmod +x test-credentials.sh

# Create configuration summary
cat > setup-summary.txt << EOF
IAM Roles Anywhere Client Setup Summary
=======================================
Generated on: $(date)
Client Name: $CLIENT_NAME
Certificate Validity: $CERT_VALIDITY_DAYS days

Files Generated:
- ${CLIENT_NAME}-private-key.pem    (Private Key - Keep Secure!)
- ${CLIENT_NAME}-certificate.pem    (Client Certificate)
- ${CLIENT_NAME}.csr                (Certificate Signing Request)
- aws_signing_helper                (Credential Helper Binary)
- get-credentials.sh                (Credential Retrieval Script)
- test-credentials.sh               (Test Script)

AWS Resources:
- CA ARN: $CA_ARN
- Trust Anchor ARN: $TRUST_ANCHOR_ARN
- Profile ARN: $PROFILE_ARN
- Role ARN: $ROLE_ARN
- Certificate ARN: $CERT_ARN

Usage:
1. Run ./get-credentials.sh to get temporary AWS credentials
2. Run ./test-credentials.sh to test the setup
3. Use the credentials in your applications

Security Notes:
- Keep the private key file secure and never share it
- Rotate certificates before expiration
- Monitor certificate usage through CloudTrail
EOF

print_status "Setup completed successfully!"
print_status "Working directory: $(pwd)"
print_status ""
print_status "Files created:"
print_status "  - ${CLIENT_NAME}-private-key.pem (KEEP SECURE!)"
print_status "  - ${CLIENT_NAME}-certificate.pem"
print_status "  - aws_signing_helper"
print_status "  - get-credentials.sh"
print_status "  - test-credentials.sh"
print_status "  - setup-summary.txt"
print_status ""
print_status "Next steps:"
print_status "1. Test the setup: ./test-credentials.sh"
print_status "2. Use ./get-credentials.sh in your applications"
print_status "3. Review setup-summary.txt for details"

print_warning "IMPORTANT: Keep the private key file secure and never commit it to version control!"
