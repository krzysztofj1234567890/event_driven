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
  table = os.environ.get('DB_TABLE')
  logging.info(f"## Loaded table name from environemt variable DB_TABLE: {table}")
  logging.info( f"event: {event}" )

  # TODO redshift_workgroup_name=event['kj-workgroup']
  # TODO redshift_database_name = event['redshift_database']
  redshift_workgroup_name='kj-workgroup'
  redshift_database_name = 'kj_database'

  result = OrderedDict()
  body = {}
  statusCode = 200

  try:
    redshift_data_api_client = boto3.client('redshift-data')

    selectResult = select_from_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name )
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

def select_from_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name ):
    logger.info("------------- select_from_table --------------")
    result = ""

    try:
        res = redshift_data_api_client.execute_statement(
            Database=redshift_database_name, 
            WorkgroupName=redshift_workgroup_name, 
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
        