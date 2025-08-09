#!/bin/bash

# FeedMe Backend Build and Deploy Script
set -e

echo "🚀 Building and deploying FeedMe backend..."

# Configuration
REGION="ap-southeast-1"
ACCOUNT_ID="891377017862"
REPO_NAME="feedme-dev-backend"
IMAGE_TAG="1.1"  # New version with fixes

# Step 1: Get ECR login
echo "📝 Getting ECR login..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Step 2: Build Docker image
echo "🔨 Building Docker image..."
cd backend
docker build -t $REPO_NAME:$IMAGE_TAG .

# Step 3: Tag for ECR
echo "🏷️ Tagging image for ECR..."
docker tag $REPO_NAME:$IMAGE_TAG $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG

# Step 4: Push to ECR
echo "📤 Pushing to ECR..."
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG

# Step 5: Update Terraform config
echo "⚙️ Updating Terraform configuration..."
cd ../terraform
sed -i.bak 's/image_tag: "1.0"/image_tag: "1.1"/' config.yaml

# Step 6: Apply Terraform changes
echo "🚀 Deploying updated infrastructure..."
terraform plan
echo "Apply the changes? (y/n)"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    terraform apply
    echo "✅ Deployment complete!"
else
    echo "❌ Deployment cancelled"
    # Restore original config
    mv config.yaml.bak config.yaml
fi

echo "🎉 Build and deploy script completed!"
echo ""
echo "📊 Test your application:"
echo "Health: http://feedme-dev-alb-576890591.ap-southeast-1.elb.amazonaws.com/health"
echo "API: http://feedme-dev-alb-576890591.ap-southeast-1.elb.amazonaws.com/orders"
echo "Frontend: http://feedme-dev-frontend-dev-eed58c3b.s3-website-ap-southeast-1.amazonaws.com"