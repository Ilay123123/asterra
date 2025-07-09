#!/usr/bin/env python3
"""
Lambda function to trigger ECS task when GeoJSON files are uploaded to S3
"""

import json
import boto3
import logging
import os
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ecs_client = boto3.client('ecs')


def handler(event, context):
    """
    AWS Lambda handler function
    Triggered when files are uploaded to S3 bucket
    """

    try:
        # Parse S3 event
        for record in event['Records']:
            # Get bucket and object key from the event
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])

            logger.info(f"Processing file: s3://{bucket}/{key}")

            # Check if it's a GeoJSON file
            if not key.lower().endswith('.geojson'):
                logger.info(f"Skipping non-GeoJSON file: {key}")
                continue

            # Run ECS task to process the file
            response = run_ecs_task(bucket, key)

            logger.info(f"ECS task started: {response.get('taskArn', 'Unknown')}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {len(event["Records"])} files',
                'timestamp': context.aws_request_id
            })
        }

    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")

        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': context.aws_request_id
            })
        }


def run_ecs_task(bucket, key):
    """
    Run ECS Fargate task to process the GeoJSON file
    """

    # Get environment variables
    cluster_name = os.environ['ECS_CLUSTER_NAME']
    task_definition = os.environ['ECS_TASK_DEFINITION']
    subnets = os.environ['ECS_SUBNETS'].split(',')
    security_groups = [os.environ['ECS_SECURITY_GROUPS']]

    # Task configuration
    task_config = {
        'cluster': cluster_name,
        'taskDefinition': task_definition,
        'launchType': 'FARGATE',
        'networkConfiguration': {
            'awsvpcConfiguration': {
                'subnets': subnets,
                'securityGroups': security_groups,
                'assignPublicIp': 'DISABLED'  # Running in private subnet
            }
        },
        'overrides': {
            'containerOverrides': [
                {
                    'name': 'geojson-processor',
                    'environment': [
                        {
                            'name': 'S3_BUCKET',
                            'value': bucket
                        },
                        {
                            'name': 'S3_KEY',
                            'value': key
                        },
                        {
                            'name': 'PROCESSING_MODE',
                            'value': 'single_file'
                        }
                    ]
                }
            ]
        },
        'tags': [
            {
                'key': 'Purpose',
                'value': 'GeoJSON Processing'
            },
            {
                'key': 'TriggeredBy',
                'value': 'S3 Event'
            },
            {
                'key': 'SourceFile',
                'value': f"s3://{bucket}/{key}"
            }
        ]
    }

    # Run the ECS task
    response = ecs_client.run_task(**task_config)

    # Check for failures
    if response.get('failures'):
        failures = response['failures']
        error_msg = f"ECS task failed to start: {failures}"
        logger.error(error_msg)
        raise Exception(error_msg)

    # Log task details
    tasks = response.get('tasks', [])
    if tasks:
        task_arn = tasks[0]['taskArn']
        logger.info(f"ECS task started successfully: {task_arn}")

    return response


def validate_geojson_key(key):
    """
    Validate that the S3 key represents a GeoJSON file
    """

    # Check file extension
    if not key.lower().endswith('.geojson'):
        return False, "Not a GeoJSON file"

    # Check that it's not in a system folder
    system_folders = ['_system', '.tmp', 'logs', 'backups']
    for folder in system_folders:
        if folder in key.lower():
            return False, f"File in system folder: {folder}"

    # Check file size isn't too large (basic validation)
    # Note: Could enhance this with actual S3 head_object call

    return True, "Valid GeoJSON file"


# For testing locally
if __name__ == "__main__":
    # Test event structure
    test_event = {
        "Records": [
            {
                "s3": {
                    "bucket": {
                        "name": "test-bucket"
                    },
                    "object": {
                        "key": "test-file.geojson"
                    }
                }
            }
        ]
    }


    # Mock context
    class MockContext:
        aws_request_id = "test-request-id"


    # Set environment variables for testing
    os.environ['ECS_CLUSTER_NAME'] = 'test-cluster'
    os.environ['ECS_TASK_DEFINITION'] = 'test-task-def'
    os.environ['ECS_SUBNETS'] = 'subnet-12345,subnet-67890'
    os.environ['ECS_SECURITY_GROUPS'] = 'sg-12345'

    # Run test
    result = handler(test_event, MockContext())
    print(json.dumps(result, indent=2))