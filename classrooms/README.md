# Classrooms Directory

This directory contains the generated classroom configurations. Each classroom will have its own subdirectory containing:

- Terraform configuration files
- Lambda/Azure function code
- Infrastructure state files
- Environment-specific variables

## Directory Structure

When a classroom is created using the `setup_classroom.sh` script, it will create a directory with the following structure:

```
classrooms/
└── <classroom-name>/
    ├── functions/
    │   ├── lambda_function.py    # (AWS) Lambda function code
    │   └── requirements.txt      # Function dependencies
    ├── iam/
    │   ├── main.tf              # IAM roles and policies
    │   └── variables.tf         # IAM module variables
    ├── main.tf                  # Main Terraform configuration
    ├── variables.tf             # Variable definitions
    ├── outputs.tf               # Output definitions
    └── terraform.tfvars         # Environment-specific values
```

## Usage

Do not modify files in this directory directly. Instead, use the provided scripts:

```bash
# Create a new classroom
./scripts/setup_classroom.sh --name your-classroom --cloud aws --region eu-west-1

# Destroy a classroom
./scripts/setup_classroom.sh --name your-classroom --cloud aws --destroy
```

## Note

This directory is used for generated content. The source templates for these files are located in the `iac/` directory. 