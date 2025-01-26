# event_driven

## Design

Service consists of:
- S3: to store lambdas
- API Gateway: sends http requests to:
  - Lambda (write)
  - EventBridge (read)
- Redshift serverless
- VPC: containig subnets for Redshift serverless
- Lambdas:
  - write data to Redshift
  - read data from Redshift
- SQS
- EventBridge
  - source: API Gateway
  - target: 
    - SQS queue
    - Lambda

## Setup

Check aws configration

```
cat ~/.aws/*
```

## Deploy

```
terraform init
terraform plan
terraform apply
terraform apply -auto-approve
```

### Test

Test lambda and API gateway
```
# write
curl -X POST "$(terraform output -raw gateway_url)/orders/create" --header 'Content-Type: application/json' -d '{"data":{"destination":{"name":"accountName"}}}'
curl -X POST "$(terraform output -raw gateway_url)/orders/create" --header 'Content-Type: application/json' -d '{"data":{"destination":{"name":"accountName"}}}'

curl -X GET "$(terraform output -raw gateway_url)/orders" --header 'Content-Type: application/json' 

```

Error:
```
curl -X GET "$(terraform output -raw gateway_url)/kj" --header 'Content-Type: application/json'
```

## Destroy

```
terraform destroy
```


## References

https://registry.terraform.io/modules/terraform-aws-modules/eventbridge/aws/latest

https://github.com/terraform-aws-modules/terraform-aws-eventbridge

https://github.com/terraform-aws-modules/terraform-aws-eventbridge/blob/master/examples/api-gateway-event-source/main.tf

https://github.com/aws-samples/aws-lambda-redshift-event-driven-app/tree/main

https://boto3.amazonaws.com/v1/documentation/api/1.35.6/reference/services/redshift-data/client/execute_statement.html

https://docs.aws.amazon.com/redshift/latest/mgmt/data-api.html

