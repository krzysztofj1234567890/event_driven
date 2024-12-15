import boto3
import json
import os
import logging
import time
import traceback
from collections import OrderedDict

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
  logging.info( f"event: {event}" )

  redshift_workgroup_name = os.environ.get('REDSHIFT_WORKGROUP')
  redshift_database_name = os.environ.get('REDSHIFT_DATABASE')
  redshift_secret_arn = os.environ.get('REDSHIFT_SECRET_ARN')
  logging.info("redshift_secret_arn: {}:".format(redshift_secret_arn))

  result = OrderedDict()
  body = {}
  statusCode = 200

  try:
    redshift_data_api_client = boto3.client('redshift-data')

    selectResult = select_from_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name, redshift_secret_arn )
    responseBody = [{'selectResult': selectResult }]

    body = json.dumps(responseBody)

    logging.info("Result: {}:".format(result))

    result = {
        "statusCode": statusCode,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": body
    }

  except BaseException as ex:
    logging.error("ERROR: {}:".format(ex))
    statusCode = 400
    logging.error(str(ex) + "\n" + traceback.format_exc())
    result = {
        "statusCode": statusCode,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": "ERROR"
    }

  return result

def select_from_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name, redshift_secret_arn ):
    logger.info("------------- select_from_table --------------")
    result = ""

    try:
        res = redshift_data_api_client.execute_statement(
            Database=redshift_database_name, 
            WorkgroupName=redshift_workgroup_name, 
            SecretArn=redshift_secret_arn,
            Sql="SELECT * FROM public.kj_order")
        query_id = res["Id"]

        desc = redshift_data_api_client.describe_statement(Id=query_id)
        query_status = desc["Status"]
        logger.info( "Query status: {}".format(query_status))
        logger.info( "Query result: {}".format(  res ))

        MAX_WAIT_CYCLES = 20
        attempts = 0
        done = False
        
        while not done and attempts < MAX_WAIT_CYCLES:
            logger.info("attempts: {}".format( attempts ) )
            attempts += 1
            # a loop instead of sleep??
#            time.sleep(1)

            desc = redshift_data_api_client.describe_statement(Id=query_id)
            query_status = desc["Status"]
            logger.info( "Query status: {}".format(query_status))
            logger.info( "Query desc: {}".format(  desc ))

            if query_status == "FAILED":
                done = True
                logger.error( 'SQL query failed:' + desc["Error"])
            elif query_status == "FINISHED":
                logger.info("query status is: {} for query id: {}".format(query_status, query_id ))
                done = True
                logger.info("result")
                if desc['HasResultSet']:
                    response = redshift_data_api_client.get_statement_result(Id=query_id)
                    result = response['Records']
                    logger.info("Printing response of query --> {}".format( result ))
            else:
                logger.info("Current working... query status is: {} ".format(query_status))
    except BaseException as ex:
        logging.error("ERROR: {}:".format(ex))
    return result 
        