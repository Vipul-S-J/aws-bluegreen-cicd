# AWS CodeDeploy Configuration

This document describes the AWS CodeDeploy setup used for the blue/green deployment of this application. All account-specific identifiers are shown as `<placeholders>` and should be replaced with your own values.

## Overview

| Setting | Value |
|---|---|
| Compute platform | EC2/On-Premises |
| Deployment type | **Blue/Green** |
| Deployment configuration | `CodeDeployDefault.AllAtOnce` |
| Green fleet provisioning | Copy the existing Auto Scaling Group |
| Traffic routing | Application Load Balancer (immediate reroute) |
| Original (blue) instances | **Terminate immediately — 0-minute wait** |
| Artifact source | Amazon S3 (`<artifacts-bucket>`) |

## 1. CodeDeploy Application

Create an application on the EC2/On-Premises compute platform.

```bash
aws deploy create-application \
  --application-name <codedeploy-app-name> \
  --compute-platform Server \
  --region <aws-region>
```

## 2. Service Role

CodeDeploy needs an IAM service role that it can assume to manage EC2, Auto Scaling, and ELB resources.

- **Trust policy:** allow `codedeploy.amazonaws.com` to assume the role.
- **Managed policy:** `AWSCodeDeployRole`.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "codedeploy.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

## 3. Deployment Group (Blue/Green)

The deployment group ties together the deployment style, the ASG to copy for the green fleet, the ALB target group, and the blue fleet termination behavior.

### Key settings

- **Deployment style**
  - Type: `BLUE_GREEN`
  - Option: `WITH_TRAFFIC_CONTROL` (ALB manages traffic)
- **Green fleet provisioning**
  - `COPY_AUTO_SCALING_GROUP` — CodeDeploy creates the green fleet by copying the referenced Auto Scaling Group.
- **Load balancer**
  - Target group behind the Application Load Balancer.
- **Blue instance termination**
  - Action: `TERMINATE`
  - Termination wait time: **0 minutes** (blue fleet is removed immediately after success).
- **Deployment ready option**
  - `CONTINUE_DEPLOYMENT` — reroute traffic to green as soon as it is ready.

### CLI example

```bash
aws deploy create-deployment-group \
  --application-name <codedeploy-app-name> \
  --deployment-group-name <deployment-group-name> \
  --service-role-arn arn:aws:iam::<account-id>:role/<codedeploy-service-role> \
  --deployment-config-name CodeDeployDefault.AllAtOnce \
  --auto-scaling-groups <source-auto-scaling-group> \
  --region <aws-region> \
  --deployment-style "deploymentType=BLUE_GREEN,deploymentOption=WITH_TRAFFIC_CONTROL" \
  --blue-green-deployment-configuration '{
    "terminateBlueInstancesOnDeploymentSuccess": {
      "action": "TERMINATE",
      "terminationWaitTimeInMinutes": 0
    },
    "deploymentReadyOption": {
      "actionOnTimeout": "CONTINUE_DEPLOYMENT"
    },
    "greenFleetProvisioningOption": {
      "action": "COPY_AUTO_SCALING_GROUP"
    }
  }' \
  --load-balancer-info '{
    "targetGroupInfoList": [{ "name": "<alb-target-group-name>" }]
  }'
```

## 4. Deployment Lifecycle Hooks

The deployment lifecycle is driven by `appspec.yml` at the artifact root, which maps CodeDeploy lifecycle events to scripts in the `aws-cd/` directory:

| Lifecycle event | Script |
|---|---|
| `AfterInstall` | `aws-cd/after_install.sh` |
| `ApplicationStart` | `aws-cd/application_start.sh` |
| `ValidateService` | `aws-cd/validate_service.sh` |
| `AfterBlockTraffic` | `aws-cd/after_block_traffic.sh` |

Each script changes into the application's `bin` directory on the instance and invokes the corresponding CodeDeploy helper script.

## 5. Triggering a Deployment

Artifacts are uploaded to S3 by the GitLab pipeline (`aws deploy push`), then a deployment is created from that S3 location:

```bash
aws deploy create-deployment \
  --application-name <codedeploy-app-name> \
  --deployment-group-name <deployment-group-name> \
  --s3-location bucket=<artifacts-bucket>,key=app-srv/<env>/app-srv-<build>-<ts>.zip,bundleType=zip \
  --region <aws-region>
```

## Notes

- The Auto Scaling Group referenced here uses a mixed-instances policy (Graviton + x86, On-Demand base + Spot). See [`../Asg-mixed-instance-policy.json`](../Asg-mixed-instance-policy.json).
- Scaling is handled by a CloudWatch target-tracking policy (~1,900 ALB requests per target), independent of CodeDeploy.
- Keep account IDs, role ARNs, bucket names, and target group names out of version control — use the placeholders above.
