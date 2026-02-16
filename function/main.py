"""
ECS Auto-Restart Lambda Function

This Lambda function monitors ECS services and automatically restarts them
if they have zero running tasks and zero desired count.

Author: Vin Lonje
Environment Variables Required:
    - ECS_CLUSTER_NAME: Name of the ECS cluster
    - ECS_SERVICE_NAMES: Comma-separated list of service names
    - DESIRED_TASK_COUNT: Number of tasks to start when restarting
    - SNS_TOPIC_ARN: SNS topic ARN for alerts (optional)
    - ENVIRONMENT: Environment name (production/staging/development)
"""

import os
import json
import boto3
import logging
from datetime import datetime

# Configure logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ecs_client = boto3.client('ecs')
sns_client = boto3.client('sns')


def send_alert(subject, message):
    """
    Send SNS alert if configured
    
    Args:
        subject (str): Email subject
        message (str): Email message body
    """
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not topic_arn:
        return
    
    try:
        sns_client.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=message
        )
    except Exception as e:
        logger.error(f"Failed to send alert: {str(e)}")


def check_and_restart_service(cluster_name, service_name, desired_count):
    """
    Check a single service and restart if needed
    
    Args:
        cluster_name (str): ECS cluster name
        service_name (str): ECS service name
        desired_count (int): Desired task count for restart
        
    Returns:
        dict: Service check result with status and details
    """
    try:
        logger.info(f"Checking service: {service_name} in cluster: {cluster_name}")
        
        # Describe the ECS service
        response = ecs_client.describe_services(
            cluster=cluster_name,
            services=[service_name]
        )
        
        # Check if service exists
        if not response['services']:
            logger.error(f"Service not found: {service_name}")
            return {
                'service': service_name,
                'status': 'not_found',
                'message': f'Service not found in cluster {cluster_name}'
            }
        
        # Get service details
        service = response['services'][0]
        running_count = service['runningCount']
        current_desired_count = service['desiredCount']
        service_status = service['status']
        
        logger.info(
            f"Service: {service_name} | "
            f"Status: {service_status} | "
            f"Running: {running_count} | "
            f"Desired: {current_desired_count}"
        )
        
        # Aggressive restart: Restart if running count is 0, regardless of desired count
        if running_count == 0:
            logger.warning(
                f"Service {service_name} has 0 running tasks "
                f"(desired count: {current_desired_count}) - initiating restart"
            )
            
            # Restart the service
            update_response = ecs_client.update_service(
                cluster=cluster_name,
                service=service_name,
                desiredCount=desired_count,
                forceNewDeployment=True
            )
            
            logger.info(
                f"Service {service_name} restarted successfully - "
                f"new desired count: {desired_count}"
            )
            
            return {
                'service': service_name,
                'status': 'restarted',
                'previous_desired_count': current_desired_count,
                'new_desired_count': desired_count,
                'deployment_id': update_response['service']['deployments'][0]['id']
            }
        else:
            # Service is healthy
            return {
                'service': service_name,
                'status': 'healthy',
                'running_count': running_count,
                'desired_count': current_desired_count,
                'service_status': service_status
            }
            
    except Exception as e:
        logger.error(f"Error checking service {service_name}: {str(e)}", exc_info=True)
        return {
            'service': service_name,
            'status': 'error',
            'error': str(e)
        }


def lambda_handler(event, context):
    """
    Main Lambda handler function
    
    Args:
        event (dict): Lambda event object
        context (object): Lambda context object
        
    Returns:
        dict: Execution result with status and details
    """
    logger.info("=== ECS Auto-Restart Lambda Started ===")
    
    # Get configuration from environment variables
    cluster_name = os.environ['ECS_CLUSTER_NAME']
    service_names = os.environ['ECS_SERVICE_NAMES'].split(',')
    desired_count = int(os.environ['DESIRED_TASK_COUNT'])
    environment = os.environ.get('ENVIRONMENT', 'production')
    
    logger.info(
        f"Configuration: "
        f"Cluster={cluster_name}, "
        f"Services={service_names}, "
        f"DesiredCount={desired_count}, "
        f"Environment={environment}"
    )
    
    # Initialize result tracking
    results = []
    restarted_services = []
    errors = []
    
    # Check each service
    for service_name in service_names:
        service_name = service_name.strip()
        result = check_and_restart_service(cluster_name, service_name, desired_count)
        results.append(result)
        
        if result['status'] == 'restarted':
            restarted_services.append(service_name)
        elif result['status'] == 'error':
            errors.append(service_name)
    
    # Send alert if services were restarted
    if restarted_services:
        logger.info(f"Sending restart alert for {len(restarted_services)} service(s)")
        alert_subject = f"[{environment.upper()}] ECS Services Auto-Restarted"
        alert_message = f"""ECS Auto-Restart Alert

Environment: {environment}
Cluster: {cluster_name}
Timestamp: {datetime.now().isoformat()}

Services Restarted ({len(restarted_services)}):
{chr(10).join(f'  - {svc}' for svc in restarted_services)}

All services have been set to desired count: {desired_count}

This is an automated notification from the ECS Auto-Restart system.
"""
        send_alert(alert_subject, alert_message)
    
    # Send alert if errors occurred
    if errors:
        logger.error(f"Errors encountered for {len(errors)} service(s)")
        error_subject = f"[{environment.upper()}] ECS Monitor Errors"
        error_message = f"""ECS Monitor encountered errors

Environment: {environment}
Cluster: {cluster_name}
Timestamp: {datetime.now().isoformat()}

Services with Errors ({len(errors)}):
{chr(10).join(f'  - {svc}' for svc in errors)}

Please check CloudWatch Logs for details.
"""
        send_alert(error_subject, error_message)
    
    logger.info(
        f"=== Lambda Execution Complete === "
        f"Services Checked: {len(service_names)}, "
        f"Restarted: {len(restarted_services)}, "
        f"Errors: {len(errors)}"
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'cluster': cluster_name,
            'services_checked': len(service_names),
            'services_restarted': len(restarted_services),
            'errors': len(errors),
            'results': results,
            'timestamp': datetime.now().isoformat()
        })
    }