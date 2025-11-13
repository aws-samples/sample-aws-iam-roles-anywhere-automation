# AWS IAM Roles Anywhere with Private Certificate Authority

This solution automates the deployment of AWS IAM Roles Anywhere with Private Certificate Authority, enabling secure certificate-based authentication for external workloads accessing AWS resources without long-term access keys.

## Architecture

![Architecture Diagram](architecture_diagram.png)

## What This Solution Provides

- **Automated AWS Infrastructure**: CloudFormation template creates Private CA, Trust Anchor, IAM Role, and Profile
- **Client Certificate Generation**: Automated script generates certificates for external systems
- **Configurable Permissions**: Flexible IAM policy assignment based on your requirements
- **Production Ready**: Security-scanned and follows AWS best practices

## Prerequisites

### For AWS Infrastructure Deployment
- AWS CLI installed and configured with administrative permissions
- Administrative permissions for IAM, IAM Roles Anywhere, and AWS Private Certificate Authority services

### For Client System Setup
- AWS CLI installed with permissions to:
  - `acm-pca:IssueCertificate`
  - `acm-pca:GetCertificate`
- OpenSSL installed on the client system

## Quick Start

### Step 1: Deploy AWS Infrastructure

```bash
aws cloudformation deploy \
    --template-file iam-roles-anywhere-infrastructure.yml \
    --stack-name my-roles-anywhere \
    --parameter-overrides \
        ProjectName="MyCompany" \
        IAMPolicyArns="arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" \
    --capabilities CAPABILITY_NAMED_IAM
```

### Step 2: Get Stack Outputs

```bash
# Get the ARNs from your deployed stack
CA_ARN=$(aws cloudformation describe-stacks --stack-name my-roles-anywhere --query 'Stacks[0].Outputs[?OutputKey==`PrivateCAArn`].OutputValue' --output text)
TRUST_ANCHOR_ARN=$(aws cloudformation describe-stacks --stack-name my-roles-anywhere --query 'Stacks[0].Outputs[?OutputKey==`TrustAnchorArn`].OutputValue' --output text)
PROFILE_ARN=$(aws cloudformation describe-stacks --stack-name my-roles-anywhere --query 'Stacks[0].Outputs[?OutputKey==`ProfileArn`].OutputValue' --output text)
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name my-roles-anywhere --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' --output text)
```

### Step 3: Setup Client Certificate

```bash
# Make script executable
chmod +x setup-client.sh

# Run client setup
./setup-client.sh \
    --ca-arn $CA_ARN \
    --trust-anchor-arn $TRUST_ANCHOR_ARN \
    --profile-arn $PROFILE_ARN \
    --role-arn $ROLE_ARN
```

### Step 4: Test the Setup

```bash
# Navigate to the created client directory
cd iam-roles-anywhere-client-*

# Test credentials
./test-credentials.sh
```

## Configuration Options

### IAM Policy Examples

**Read-Only Access (Default):**
```bash
--parameter-overrides IAMPolicyArns="arn:aws:iam::aws:policy/ReadOnlyAccess"
```

**S3 Access Only:**
```bash
--parameter-overrides IAMPolicyArns="arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
```

**Multiple Policies:**
```bash
--parameter-overrides IAMPolicyArns="arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess,arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
```

### CloudFormation Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ProjectName` | Name prefix for all resources | `MyRolesAnywhere` |
| `CertificateValidityYears` | Root CA certificate validity (1-10 years) | `3` |
| `SessionDurationSeconds` | Max session duration (900-43200 seconds) | `3600` |
| `IAMPolicyArns` | Comma-separated IAM policy ARNs | `ReadOnlyAccess` |

## Using the Credentials

Once setup is complete, your external system can get temporary AWS credentials:

```bash
# Get credentials (returns JSON with AccessKeyId, SecretAccessKey, SessionToken)
./get-credentials.sh

# Or use in your application
CREDS=$(./get-credentials.sh)
export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r '.SessionToken')

# Now use AWS CLI or SDKs normally
aws s3 ls
```

## Security Best Practices

- **Rotate certificates regularly** (recommended: annually)
- **Use least-privilege IAM policies** for your specific use case
- **Store private keys securely** on client systems (never share or commit)
- **Monitor certificate expiration** and implement renewal processes
- **Enable CloudTrail logging** for audit trails
- **Use separate CAs** for different environments (dev/prod)

## Troubleshooting

### Common Issues

**"ValidationException: Error creating TrustAnchor"**
- Ensure Private CA is in ACTIVE status
- Verify you have proper permissions for IAM Roles Anywhere

**"Permission denied" when running scripts**
- Run `chmod +x setup-client.sh` to make script executable

**"Certificate validation failed"**
- Check that client certificate was issued by the trusted CA
- Verify certificate hasn't expired

**"Access denied" errors**
- Verify IAM role permissions match your use case
- Check trust policy configuration

## Files Description

- `iam-roles-anywhere-infrastructure.yml` - CloudFormation template for AWS resources
- `setup-client.sh` - Automated client certificate generation and setup
- `arch_diagram.png` - Solution architecture diagram

## Contributing

This is an open-source AWS pattern. Feel free to submit issues and enhancement requests!

## License

This project is licensed under the MIT License - see the AWS samples license for details.

---

**Need help?** Check the [AWS IAM Roles Anywhere documentation](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/) for additional guidance.
