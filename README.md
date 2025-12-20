# AWS EC2 Image Builder - Golden AMI Pipeline

[![Terraform](https://img.shields.io/badge/Terraform-1.0%2B-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Image%20Builder-FF9900?logo=amazon-aws)](https://aws.amazon.com/image-builder/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An enterprise-grade, automated Golden AMI pipeline using AWS EC2 Image Builder with Terraform. This solution provides automated, secure, and compliant AMI builds with multi-region distribution and security hardening.

## 🏗️ Architecture

```
┌──────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│   EventBridge    │         │  Image Builder   │         │   Multi-Region   │
│   (Weekly Cron)  ├────────►│     Pipeline     ├────────►│   Distribution   │
└──────────────────┘         └──────────────────┘         └──────────────────┘
                                      │                              │
                                      │                              ├─ us-east-1
                                      ▼                              ├─ eu-west-1
                             ┌────────────────┐                      └─ ap-southeast-1
                             │  Build Process │
                             └────────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                 ▼
              ┌─────────┐       ┌─────────┐      ┌──────────┐
              │ Update  │       │Security │      │CloudWatch│
              │ Linux   │       │Hardening│      │  Agent   │
              └─────────┘       └─────────┘      └──────────┘
                                      │
                                      ▼
                             ┌────────────────┐         ┌──────────┐
                             │  Build Logs    ├────────►│   SNS    │
                             │  (S3 Bucket)   │         │Notification│
                             └────────────────┘         └──────────┘
```

## ✨ Features

- **Automated Weekly Builds**: Scheduled pipeline execution every Sunday
- **Multi-Region Distribution**: Automatic AMI distribution to us-east-1, eu-west-1, and ap-southeast-1
- **Security Hardening**: Custom security components including root login disable and security tools
- **Pre-installed Components**: 
  - AWS Systems Manager Agent
  - Amazon CloudWatch Agent
  - ClamAV antivirus
  - Rootkit Hunter (rkhunter)
- **Build Artifact Storage**: S3 bucket with versioning for logs and artifacts
- **Event Notifications**: SNS notifications for pipeline status changes
- **Enhanced Metadata**: Detailed image metadata for tracking and compliance
- **Automated Testing**: Built-in image validation with configurable timeout
- **Infrastructure as Code**: Fully automated deployment with Terraform

## 📋 Prerequisites

- **Terraform**: Version 1.0 or higher
- **AWS Account**: With appropriate IAM permissions
- **AWS CLI**: Configured with credentials
- **VPC Configuration**: Existing VPC with at least one subnet
- **EC2 Key Pair**: For troubleshooting build instances (optional)
- **Required Terraform Providers**:
  - `hashicorp/aws` (~> 5.0)

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd <repository-directory>
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
primary_region      = "us-east-1"
subnet_id          = "subnet-xxxxxxxxxxxxx"
key_pair_name      = "your-key-pair"        # Optional, for debugging
notification_email = "your-email@domain.com"
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review the Plan

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

### 6. Confirm SNS Subscription

Check your email and confirm the SNS subscription to receive AMI build notifications.

### 7. Trigger First Build (Optional)

```bash
aws imagebuilder start-image-pipeline-execution \
  --image-pipeline-arn <pipeline-arn-from-output>
```

## 🔧 Configuration

### Input Variables

| Variable | Description | Type | Required | Default |
|----------|-------------|------|----------|---------|
| `primary_region` | Primary AWS region for AMI builds | `string` | Yes | - |
| `subnet_id` | VPC subnet ID for builder instances | `string` | Yes | - |
| `key_pair_name` | EC2 key pair for instance access | `string` | No | `null` |
| `notification_email` | Email for SNS notifications | `string` | Yes | - |

### Module Structure

```
.
├── main.tf                 # Main configuration
├── variables.tf            # Input variables
├── outputs.tf             # Output values
├── modules/
│   ├── s3/               # S3 bucket module
│   ├── eventbridge/      # EventBridge rule module
│   └── sns/              # SNS topic module
└── README.md
```

## 📦 Resources Created

### Core Resources
- **EC2 Image Builder Pipeline**: Automated build orchestration
- **Image Recipe**: Base Linux configuration with components
- **Infrastructure Configuration**: Build instance settings
- **Distribution Configuration**: Multi-region AMI distribution

### Supporting Resources
- **IAM Role & Instance Profile**: For Image Builder service
- **Security Group**: Outbound traffic for build instances
- **S3 Bucket**: Build logs and artifacts storage
- **EventBridge Rule**: Pipeline event capture
- **SNS Topic**: Build status notifications

### Components
- **AWS Managed Components**:
  - Amazon Linux 2 updates
  - CloudWatch Agent installation
- **Custom Components**:
  - Security hardening (root login disable)
  - Security tools installation (ClamAV, rkhunter)

## 🔐 Security Features

### Implemented Security Controls

✅ **Automated Security Updates**: Latest patches applied during build  
✅ **Root Login Disabled**: SSH root access blocked by default  
✅ **Antivirus Protection**: ClamAV pre-installed and configured  
✅ **Rootkit Detection**: rkhunter for intrusion detection  
✅ **CloudWatch Agent**: Centralized logging and monitoring  
✅ **Systems Manager**: Secure instance management without SSH  
✅ **Encrypted Storage**: GP3 volumes for better performance  
✅ **Least Privilege IAM**: Minimal permissions for builder role  

### Recommended Enhancements

- [ ] Enable EBS encryption by default
- [ ] Add CIS benchmarking components
- [ ] Implement AWS Inspector scanning
- [ ] Add compliance scanning (STIG, PCI-DSS)
- [ ] Configure AWS GuardDuty integration
- [ ] Add vulnerability scanning with Amazon Inspector
- [ ] Implement AMI lifecycle policies
- [ ] Add AWS Config rules for AMI compliance
- [ ] Enable AWS CloudTrail for API auditing
- [ ] Add custom security policies (SELinux, AppArmor)

## 📅 Build Schedule

The pipeline is configured to run automatically:

**Schedule**: Every Sunday at 00:00 UTC  
**Trigger Condition**: `EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE`

This means builds only execute when:
- The scheduled time is reached AND
- Dependency updates are available (e.g., base AMI updates)

### Manual Trigger

```bash
# Trigger immediate build
aws imagebuilder start-image-pipeline-execution \
  --image-pipeline-arn arn:aws:imagebuilder:region:account:image-pipeline/golden-ami-pipeline

# Check pipeline status
aws imagebuilder list-image-pipeline-executions \
  --image-pipeline-arn arn:aws:imagebuilder:region:account:image-pipeline/golden-ami-pipeline
```

## 🌍 Multi-Region Distribution

AMIs are automatically distributed to:

| Region | Name | Purpose |
|--------|------|---------|
| us-east-1 | US East (N. Virginia) | Primary region |
| eu-west-1 | Europe (Ireland) | European operations |
| ap-southeast-1 | Asia Pacific (Singapore) | APAC operations |

### AMI Naming Convention

```
golden-ami-YYYY-MM-DD-HH-MM-SS
```

Example: `golden-ami-2024-12-20-00-30-45`

### AMI Tags

Each AMI is tagged with:
- `SourceAMI`: The parent AMI used for building
- `BuildDate`: Timestamp of the build
- Additional custom tags can be added in the distribution configuration

## 📊 Monitoring and Logging

### CloudWatch Logs

Build logs are stored in S3 with the following structure:

```
s3://ami-artifacts-{account-id}/logs/{execution-id}/
```

### SNS Notifications

You'll receive email notifications for:
- Pipeline execution started
- Pipeline execution completed
- Pipeline execution failed
- AMI distribution completed

### EventBridge Events

The solution captures these Image Builder events:
- `Image Builder Image State Change`
- State transitions: BUILDING, TESTING, DISTRIBUTING, AVAILABLE, FAILED

### Monitoring Commands

```bash
# View recent pipeline executions
aws imagebuilder list-image-pipeline-executions \
  --image-pipeline-arn <pipeline-arn> \
  --max-results 10

# Get execution details
aws imagebuilder get-image \
  --image-build-version-arn <image-arn>

# Check S3 logs
aws s3 ls s3://ami-artifacts-{account-id}/logs/ --recursive
```

## 🔄 AMI Lifecycle Management

### Recommended Practices

1. **Version Control**: AMIs are automatically versioned with timestamps
2. **Retention Policy**: Implement cleanup for old AMIs
3. **Testing**: Always test new AMIs in non-production first
4. **Rollback Plan**: Keep previous working AMI version

### Example Cleanup Script

```bash
#!/bin/bash
# Deregister AMIs older than 90 days
CUTOFF_DATE=$(date -d '90 days ago' +%s)

aws ec2 describe-images --owners self --filters "Name=name,Values=golden-ami-*" \
  --query 'Images[*].[ImageId,CreationDate,Name]' --output text | \
while read ami_id creation_date name; do
  ami_timestamp=$(date -d "$creation_date" +%s)
  if [ $ami_timestamp -lt $CUTOFF_DATE ]; then
    echo "Deregistering old AMI: $ami_id ($name)"
    aws ec2 deregister-image --image-id $ami_id
  fi
done
```

## 🧪 Testing and Validation

### Built-in Tests

The pipeline includes automated testing:
- **Duration**: 60 minutes maximum
- **Tests Enabled**: Yes
- **Test Types**: AWS managed test suite

### Manual Validation

```bash
# Launch test instance from new AMI
aws ec2 run-instances \
  --image-id ami-xxxxxxxxxxxxx \
  --instance-type t3.micro \
  --key-name your-key-pair \
  --subnet-id subnet-xxxxxxxxxxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=AMI-Test}]'

# Connect via Systems Manager (no SSH key needed)
aws ssm start-session --target i-xxxxxxxxxxxxx

# Verify installed components
sudo systemctl status amazon-ssm-agent
sudo systemctl status amazon-cloudwatch-agent
clamscan --version
rkhunter --version
```

## 💰 Cost Estimation

### Monthly Costs (Approximate)

| Service | Cost Driver | Estimated Cost |
|---------|-------------|----------------|
| EC2 Image Builder | Pipeline (enabled) | Free |
| EC2 Instances | Build time (m5.large, ~1hr/week) | ~$8/month |
| S3 Storage | Build logs | ~$1-5/month |
| SNS | Email notifications | Free tier |
| AMI Storage | EBS snapshots | ~$2/AMI/month |
| Data Transfer | Multi-region AMI copy | ~$0.02/GB |

**Estimated Total**: $15-25/month for weekly builds

### Cost Optimization Tips

1. **Reduce Build Frequency**: Change from weekly to bi-weekly or monthly
2. **Instance Sizing**: Use smaller instance types if builds complete successfully
3. **Region Selection**: Only distribute to regions you actually use
4. **Log Retention**: Implement S3 lifecycle policies for old logs
5. **AMI Cleanup**: Regularly deregister unused AMIs and delete snapshots

## 🐛 Troubleshooting

### Build Failures

**Issue**: Pipeline fails during build phase

**Solution**:
```bash
# Check logs in S3
aws s3 cp s3://ami-artifacts-{account-id}/logs/{execution-id}/ ./logs/ --recursive

# Review CloudWatch logs
aws logs tail /aws/imagebuilder/golden-ami-pipeline --follow

# Check instance profile permissions
aws iam get-role --role-name EC2ImageBuilderRole
```

### Component Installation Failures

**Issue**: Custom components fail to execute

**Solution**:
- Verify commands are compatible with Amazon Linux 2
- Check yum repository availability
- Ensure internet connectivity from builder instances
- Review component YAML syntax

### Distribution Failures

**Issue**: AMI fails to copy to target regions

**Solution**:
- Check IAM permissions for cross-region copying
- Verify EBS snapshot permissions
- Review KMS key policies if using encryption
- Ensure sufficient EBS snapshot quota in target regions

### No Email Notifications

**Issue**: Not receiving SNS emails

**Solution**:
```bash
# Check SNS subscription status
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:region:account:ami-creation-notifications

# Verify EventBridge rule is enabled
aws events describe-rule --name ami-creation-event

# Check EventBridge targets
aws events list-targets-by-rule --rule ami-creation-event
```

## 🔄 CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy AMI Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        
      - name: Terraform Init
        run: terraform init
        
      - name: Terraform Plan
        run: terraform plan
        
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve
```

### Jenkins Pipeline Example

```groovy
pipeline {
    agent any
    stages {
        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }
        stage('Terraform Plan') {
            steps {
                sh 'terraform plan -out=tfplan'
            }
        }
        stage('Terraform Apply') {
            when {
                branch 'main'
            }
            steps {
                sh 'terraform apply tfplan'
            }
        }
    }
}
```

## 📈 Advanced Configurations

### Custom Components

Add your own components to the recipe:

```hcl
resource "aws_imagebuilder_component" "custom_app" {
  name     = "install-custom-app"
  platform = "Linux"
  version  = "1.0.0"

  data = <<EOF
name: InstallCustomApp
description: Install company-specific application
schemaVersion: 1.0

phases:
  - name: build
    steps:
      - name: InstallApp
        action: ExecuteBash
        inputs:
          commands:
            - wget https://company.com/app.rpm
            - yum install -y app.rpm
            - systemctl enable app
EOF
}

# Add to recipe
resource "aws_imagebuilder_image_recipe" "base_linux" {
  # ... existing configuration ...
  
  component {
    component_arn = aws_imagebuilder_component.custom_app.arn
  }
}
```

### Additional Regions

```hcl
distribution {
  region = "us-west-2"

  ami_distribution_configuration {
    name = "golden-ami-{{ imagebuilder:buildDate }}"
    ami_tags = {
      SourceAMI = "{{ imagebuilder:sourceImage }}"
      BuildDate = "{{ imagebuilder:buildDate }}"
      Environment = "Production"
    }
  }
}
```

### Windows Support

```hcl
resource "aws_imagebuilder_image_recipe" "base_windows" {
  name         = "base-windows-recipe"
  parent_image = "arn:aws:imagebuilder:${var.primary_region}:aws:image/windows-server-2022-english-full-base-x86/x.x.x"
  version      = "1.0.0"

  block_device_mapping {
    device_name = "/dev/sda1"

    ebs {
      delete_on_termination = true
      volume_size           = 50
      volume_type           = "gp3"
    }
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.primary_region}:aws:component/update-windows/x.x.x"
  }
}
```

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Standards

- Follow Terraform best practices
- Include comments for complex logic
- Update documentation for new features
- Test changes in a non-production environment

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 References

- [AWS EC2 Image Builder Documentation](https://docs.aws.amazon.com/imagebuilder/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Image Builder Component Manager](https://docs.aws.amazon.com/imagebuilder/latest/userguide/image-builder-component-manager.html)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [CIS Amazon Linux 2 Benchmark](https://www.cisecurity.org/benchmark/amazon_linux)

## 📧 Support

For issues, questions, or contributions:

- **GitHub Issues**: Report bugs or request features
- **Discussions**: Ask questions and share ideas
- **AWS Support**: For AWS service-specific issues
- **Security Issues**: Report to security@yourcompany.com

## 🎯 Roadmap

- [ ] Add support for Ubuntu/Debian base images
- [ ] Implement automated AMI testing with Kitchen-Terraform
- [ ] Add compliance scanning integration (AWS Audit Manager)
- [ ] Create dashboard for AMI inventory
- [ ] Add automated vulnerability patching workflow
- [ ] Implement blue-green AMI deployment strategy
- [ ] Add cost analysis and optimization recommendations

---

**⚠️ Important Notes**:
- Always test AMIs in non-production environments first
- Review and customize security hardening for your requirements
- Implement proper AMI lifecycle management
- Monitor costs and optimize build frequency
- Keep Terraform state files secure and backed up
