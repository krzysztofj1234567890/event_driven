# event_driven

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


curl -X GET "$(terraform output -raw gateway_url)/orders/create" --header 'Content-Type: application/json' 

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

