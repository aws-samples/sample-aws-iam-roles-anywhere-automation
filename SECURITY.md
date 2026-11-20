# Security Policy

> **Important:** Sample code for non-production use. Do not deploy to production environments without additional security testing and review.

This sample shows how to set up AWS Identity and Access Management Roles Anywhere (IAM Roles Anywhere) with AWS Private Certificate Authority (AWS Private CA). It is not a hardened production certificate authority or IAM trust path. Review the known limitations and production recommendations below before you adapt it for production.

## Reporting a Vulnerability

If you discover a potential security issue in this project, notify AWS Security through the [AWS vulnerability reporting page](https://aws.amazon.com/security/vulnerability-reporting/). Do **not** create a public issue.

## Security Controls in This Sample

- **Scoped role trust policy**: The IAM role can only be assumed through the trust anchor in this stack, in the deploying account, with a client certificate issued by this stack's CA and a Subject CN that matches `AllowedClientCommonNamePattern`.
- **Temporary credentials**: Workloads receive short-lived session credentials instead of long-term access keys.
- **Client name validation**: `setup-client.sh` accepts only letters, numbers, `.`, `_`, and `-` in `--client-name`, which prevents extra subject fields from being injected into the certificate signing request.
- **Private key permissions**: `setup-client.sh` sets the client private key to mode `600` (owner read and write only) right after it is generated.
- **Ignored key material**: `.gitignore` excludes `*.pem`, `*.csr`, and the generated `iam-roles-anywhere-*/` directories so client keys are not committed by accident.

## Known Limitations and Production Recommendations

### 1. Default ReadOnlyAccess policy and unconstrained IAMPolicyArns

The role uses the AWS managed `ReadOnlyAccess` policy by default, and `IAMPolicyArns` accepts any policy ARN.

- **Risk**: Every workload gets account-wide read access by default, and a highly privileged policy such as `AdministratorAccess` could be attached by mistake.
- **Production recommendation**: Use a customer managed policy scoped to the specific resources the workload needs. Add a permissions boundary to the role, and reject administrator policies with an `AllowedPattern` on the parameter.

### 2. `acm-pca:IssueCertificate` is required to run setup-client.sh

`setup-client.sh` calls `acm-pca:IssueCertificate` and `acm-pca:GetCertificate`, so whoever runs it can create client certificates for the CA.

- **Risk**: Anyone with `IssueCertificate` on the CA can create a certificate whose CN matches `client-*` and assume the role. Granting this permission to the external system itself brings back long-term credentials.
- **Production recommendation**: Run the script only from a trusted administrator workstation or CI/CD role, not from the external system. Scope `acm-pca:IssueCertificate` to this CA ARN and the `EndEntityCertificate/V1` template ARN. Set `AllowedClientCommonNamePattern` to the exact CN of each workload.

### 3. AWS Signing Helper downloaded without an integrity check

The script downloads `aws_signing_helper` from the official AWS HTTPS endpoint but does not verify a checksum, and `--helper-version` is not format-validated.

- **Risk**: A tampered or wrong download would run an unverified binary that handles the private key and credentials.
- **Production recommendation**: Verify the published SHA-256 checksum for the pinned version before making the binary executable. Validate `--helper-version` against `^[0-9]+\.[0-9]+\.[0-9]+$`, and keep the pinned version current with the [IAM Roles Anywhere credential helper releases](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html).

### 4. Root CA issues client certificates directly, with no revocation

The root CA signs end-entity certificates, has no certificate revocation list (CRL), and uses an RSA 2048-bit key.

- **Risk**: A leaked client key cannot be revoked without deleting the CA, and root CA expiry causes an outage without warning.
- **Production recommendation**: Issue client certificates from a subordinate CA instead of the root. Enable a CRL and import it into IAM Roles Anywhere. Enable trust anchor expiry notifications. Consider `RSA_4096` or `EC_prime256v1` keys.

### 5. ARN arguments are not validated before use in generated scripts

`setup-client.sh` writes the ARN arguments into `get-credentials.sh` without validation.

- **Risk**: If automation passes less trusted values, shell metacharacters in an ARN would run as code when `get-credentials.sh` executes.
- **Production recommendation**: Validate each ARN with a regular expression, and quote values with `printf '%q'` when generating files.

## Operational Best Practices

- **Private key storage**: Keep private keys with mode `600` and never share or commit them. In production, store keys in a hardware security module (HSM), a TPM, or an operating system keystore supported by the credential helper.
- **Certificate rotation**: The default client certificate validity is 365 days. Rotate certificates before they expire and monitor expiration dates.
- **Environment separation**: Use separate CAs and trust anchors for each environment.
- **Logging**: Enable AWS CloudTrail to audit `CreateSession` calls and role usage.
- **Network access**: The setup script needs HTTPS access to `rolesanywhere.amazonaws.com` to download the credential helper.

## Dependencies

- **OpenSSL**: Keep OpenSSL updated.
- **AWS CLI**: Keep the AWS CLI updated.
- **Bash**: Use a currently supported Bash version.
