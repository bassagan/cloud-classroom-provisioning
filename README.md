# Cloud Classroom Provisioning

This project provides an automated way to create and manage cloud classrooms, where each student gets their own cloud provider account with restricted permissions. Currently supports AWS and Azure.

## Features

- Multi-cloud support (AWS and Azure)
- User management infrastructure for cloud classroom environments
- Automated provisioning of cloud resources
- Classroom management tools and scripts
- Secure access management for students

## Prerequisites

- **AWS Setup**:
  - AWS CLI installed and configured (`aws configure`)
  - AWS account with appropriate permissions
  - Terraform v1.0.0 or later
  - Python 3.9 or later
  - virtualenv (`pip install virtualenv`)

- **Azure Setup**:
  - Azure CLI installed and configured (`az login`)
  - Azure subscription
  - Terraform v1.0.0 or later

## Quick Start

### Creating a New Classroom

Use the `setup_classroom.sh` script to create a new classroom:

```bash
# For AWS
./scripts/setup_classroom.sh --name your-classroom-name --cloud aws --region eu-west-1

# For Azure
./scripts/setup_classroom.sh --name your-classroom-name --cloud azure --location westeurope
```

The script will:
1. Create necessary directory structure
2. Copy required configuration files
3. Package the Lambda/Azure Function with dependencies
4. Deploy all infrastructure using Terraform
5. Output the function URL for creating student accounts

### Destroying a Classroom

To destroy all resources associated with a classroom:

```bash
./scripts/setup_classroom.sh --name your-classroom-name --cloud aws --destroy
```

### Script Options

```
Usage: ./scripts/setup_classroom.sh --name <classroom-name> --cloud [aws|azure] [--region <aws-region>] [--location <azure-location>] [--destroy]

Options:
  --name      Name of the classroom (required)
  --cloud     Cloud provider (aws or azure, default: aws)
  --region    AWS region (default: eu-west-1)
  --location  Azure location (default: westeurope)
  --destroy   Destroy the classroom resources instead of creating them
```

## Creating Student Accounts

Once the classroom is set up, you'll receive a function URL. Use this URL to create student accounts:

1. **Via Browser**: 
   - Open the function URL in your browser
   - Fill out the form with the classroom name
   - Submit to create a new student account

2. **Via curl**:
```bash
curl -X POST -H "Content-Type: application/json" \
     -d '{"classroom_name": "your-classroom-name"}' \
     <function-url>
```

## Project Structure

```
.
├── classrooms/              # Generated classroom configurations
├── functions/              
│   ├── aws/                # AWS Lambda function code
│   └── azure/              # Azure Function code
├── iac/
│   ├── aws/                # AWS Terraform configurations
│   └── azure/              # Azure Terraform configurations
└── scripts/
    ├── package_lambda.sh   # Packages Lambda function with dependencies
    └── setup_classroom.sh  # Main script for classroom management
```

## Student Resources

Each student account is created with:
- Limited IAM/Azure role permissions
- Resource tagging for ownership
- Access to specific services based on classroom needs
- Resource usage limits and quotas

## Security Features

- Resource access restricted by tags
- Automatic cleanup of unused resources
- Limited permissions based on classroom requirements
- Secure credential delivery

## Troubleshooting

1. **Script Permissions**:
   ```bash
   chmod +x scripts/*.sh
   ```

2. **AWS Authentication**:
   ```bash
   aws configure
   aws sts get-caller-identity  # Verify credentials
   ```

3. **Azure Authentication**:
   ```bash
   az login
   az account show  # Verify login
   ```

4. **Lambda Packaging**:
   If you need to manually package the Lambda function:
   ```bash
   ./scripts/package_lambda.sh
   ```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support, please:
1. Check the documentation
2. Review existing issues
3. Open a new issue with detailed information
4. Contact the maintainers 