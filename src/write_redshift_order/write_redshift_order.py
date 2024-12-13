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
#  requestContext = event['requestContext']
#  resourceId = requestContext['resourceId'] 
#  logging.info( f"resourceId: {resourceId}" )
#  pathParameters = event['pathParameters']
#  logging.info( f"pathParameters: {pathParameters}" )

  # TODO redshift_workgroup_name=event['kj-workgroup']
  # TODO redshift_database_name = event['redshift_database']
  redshift_workgroup_name='kj-workgroup'
  redshift_database_name = 'kj_database'

  result = OrderedDict()
  body = {}
  statusCode = 200

  try:
    redshift_data_api_client = boto3.client('redshift-data')

    create_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name )

    tables = list_tables( redshift_data_api_client, redshift_database_name, redshift_workgroup_name )
    responseBody = [{'tables': tables }]

    insert_into_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name )

    grant_permissions( redshift_data_api_client, redshift_database_name, redshift_workgroup_name )

    body = json.dumps(responseBody)

    logging.info("Result: {}:".format(responseBody))

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

def list_tables( redshift_data_api_client, redshift_database_name, redshift_workgroup_name ):
    logger.info("------------- list_tables --------------")
    response = redshift_data_api_client.list_tables(
        Database=redshift_database_name, 
        WorkgroupName=redshift_workgroup_name, 
        MaxResults=100,
        TablePattern="kj%"
    )
    tables = response['Tables']
    logger.info("List of Tables:")
    for table in tables:
        logger.info( table )
    return tables

def create_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name ):
    logger.info("------------- create_table --------------")
    res = redshift_data_api_client.execute_statement(
        Database=redshift_database_name, 
        WorkgroupName=redshift_workgroup_name, 
        Sql="CREATE TABLE IF NOT EXISTS public.kj_order ( name VARCHAR(25) NOT NULL, created_at DATETIME DEFAULT sysdate )")
    
    query_id = res["Id"]
    desc = redshift_data_api_client.describe_statement(Id=query_id)
    query_status = desc["Status"]
    logger.info( "Query status: {}".format(query_status))

def insert_into_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name ):
    logger.info("------------- insert_into_table --------------")
    res = redshift_data_api_client.execute_statement(
        Database=redshift_database_name, 
        WorkgroupName=redshift_workgroup_name, 
        Sql="INSERT INTO public.kj_order( name ) VALUES ('order_1') ")
    
    query_id = res["Id"]
    desc = redshift_data_api_client.describe_statement(Id=query_id)
    query_status = desc["Status"]
    logger.info( "Query status: {}".format(query_status))
    logger.info( "Query result: {}".format(  res ))

    MAX_WAIT_CYCLES = 20
    attempts = 0
    done = False
    result = ""
    while not done and attempts < MAX_WAIT_CYCLES:
        attempts += 1
        logger.info("attempts: {}".format( attempts ) )
#        time.sleep(1)
        desc = redshift_data_api_client.describe_statement(Id=query_id)
        query_status = desc["Status"]
        if query_status == "FAILED":
            done = True
            logger.error( 'SQL query failed:' + desc["Error"])
        elif query_status == "FINISHED":
            logger.info("query status is: {} for query id: {}".format(query_status, query_id ))
            done = True
            logger.info( desc )
            if desc['HasResultSet']:
                response = redshift_data_api_client.get_statement_result(Id=query_id)
                logger.info("Printing response of query --> {}".format( response['Records']))
        else:
            logger.info("Current working... query status is: {} ".format(query_status))
    return result 

def grant_permissions( redshift_data_api_client, redshift_database_name, redshift_workgroup_name ):
    logger.info("------------- grant_permissions --------------")

    logger.info("CREATE ROLE")
    res = redshift_data_api_client.execute_statement(
        Database=redshift_database_name, 
        WorkgroupName=redshift_workgroup_name, 
        Sql="CREATE ROLE role1;")
    query_id = res["Id"]
    desc = redshift_data_api_client.describe_statement(Id=query_id)
    query_status = desc["Status"]
    logger.info( "Query status: {}".format(query_status))

    logger.info("GRANT SELECT on TABLE")
    res = redshift_data_api_client.execute_statement(
        Database=redshift_database_name, 
        WorkgroupName=redshift_workgroup_name, 
        Sql="GRANT SELECT on TABLE public.kj_order to ROLE role1;")
    query_id = res["Id"]
    desc = redshift_data_api_client.describe_statement(Id=query_id)
    query_status = desc["Status"]
    logger.info( "Query status: {}".format(query_status))