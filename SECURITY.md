# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in this AWS IAM Roles Anywhere automation, please report it.

**Please do not report security vulnerabilities through public GitHub issues.**

## Security Best Practices for Users

### Certificate Management
- **Private Key Security**: Store private keys with restricted permissions (600)
- **Certificate Rotation**: Rotate certificates before expiration
- **Secure Storage**: Use secure key management systems in production
- **Monitoring**: Monitor certificate expiration dates

### Infrastructure Security
- **Least Privilege**: Use minimal required IAM policies for your use case
- **Environment Separation**: Use separate CAs for different environments
- **CloudTrail Logging**: Enable CloudTrail for audit trails
- **Network Security**: Implement proper network controls

### Operational Security
```bash
# Secure private key permissions
chmod 600 *-private-key.pem

# Regular certificate rotation
# Set up monitoring for certificate expiration

# Use environment-specific configurations
# Separate dev/staging/prod environments
```

### Known Security Considerations

1. **File Permissions**: The setup script creates private keys with default permissions. Ensure proper file permissions in production environments.

2. **Certificate Validity**: Default certificate validity is 365 days. Adjust based on your security requirements.

3. **Network Access**: The script downloads the AWS signing helper from official AWS endpoints. Ensure network access to `rolesanywhere.amazonaws.com`.

## Dependencies Security

- **OpenSSL**: Ensure OpenSSL is updated to latest version
- **AWS CLI**: Keep AWS CLI updated for latest security patches
- **Bash**: Use modern bash versions with security updates
