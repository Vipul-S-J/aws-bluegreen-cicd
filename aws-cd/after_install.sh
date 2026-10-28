#!/bin/bash
cd /home/ec2-user/efs/bin
sudo env DEPLOYMENT_ID="$DEPLOYMENT_ID" DEPLOYMENT_GROUP_ID="$DEPLOYMENT_GROUP_ID" sh codedeploy_after_install.sh
