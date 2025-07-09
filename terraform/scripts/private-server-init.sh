# scripts/private-server-init.sh
#!/bin/bash

# Update system
apt-get update && apt-get upgrade -y

# Install required packages
apt-get install -y python3 python3-pip gdal-bin postgresql-client docker.io

# Install GeoPandas and related packages
pip3 install geopandas pandas sqlalchemy psycopg2-binary boto3 aws-psycopg2

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Create application directory
mkdir -p /opt/geojson-processor
cd /opt/geojson-processor

# Create GeoJSON processing application
cat > app.py << 'EOF'
#!/usr/bin/env python3
import json
import boto3
import geopandas as gpd
from sqlalchemy import create_engine
import psycopg2
import logging
from io import StringIO
import sys

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class GeoJSONProcessor:
    def __init__(self):
        self.s3_client = boto3.client('s3')
        self.secrets_client = boto3.client('secretsmanager')
        self.s3_bucket = '${s3_bucket}'
        self.secret_arn = '${secret_arn}'

    def get_db_connection(self):
        """Get database connection from AWS Secrets Manager"""
        try:
            response = self.secrets_client.get_secret_value(SecretId=self.secret_arn)
            secret = json.loads(response['SecretString'])

            connection_string = f"postgresql://{secret['username']}:{secret['password']}@{secret['host']}:{secret['port']}/{secret['dbname']}"
            engine = create_engine(connection_string)
            return engine
        except Exception as e:
            logger.error(f"Failed to get database connection: {e}")
            raise

    def validate_geojson(self, file_content):
        """Validate GeoJSON format"""
        try:
            geojson_data = json.loads(file_content)
            if geojson_data.get('type') != 'FeatureCollection':
                return False, "Not a valid FeatureCollection"

            if 'features' not in geojson_data:
                return False, "No features found"

            return True, "Valid GeoJSON"
        except json.JSONDecodeError as e:
            return False, f"Invalid JSON: {e}"
        except Exception as e:
            return False, f"Validation error: {e}"

    def process_geojson_file(self, bucket, key):
        """Process a single GeoJSON file"""
        logger.info(f"Processing file: s3://{bucket}/{key}")

        try:
            # Download file from S3
            response = self.s3_client.get_object(Bucket=bucket, Key=key)
            file_content = response['Body'].read().decode('utf-8')

            # Validate GeoJSON
            is_valid, message = self.validate_geojson(file_content)
            if not is_valid:
                logger.error(f"Invalid GeoJSON: {message}")
                return False

            # Read with GeoPandas
            gdf = gpd.read_file(StringIO(file_content))

            # Get database connection
            engine = self.get_db_connection()

            # Ensure PostGIS extension is enabled
            with engine.connect() as conn:
                conn.execute("CREATE EXTENSION IF NOT EXISTS postgis;")
                conn.commit()

            # Store in database
            table_name = f"geojson_{key.replace('/', '_').replace('.', '_')}"
            gdf.to_postgis(table_name, engine, if_exists='replace', index=False)

            logger.info(f"Successfully processed and stored {len(gdf)} features in table {table_name}")
            return True

        except Exception as e:
            logger.error(f"Error processing file: {e}")
            return False

def main():
    processor = GeoJSONProcessor()

    # For testing, process sample file
    if len(sys.argv) > 1:
        bucket = sys.argv[1]
        key = sys.argv[2]
        processor.process_geojson_file(bucket, key)
    else:
        logger.info("GeoJSON Processor is ready. Provide bucket and key as arguments.")

if __name__ == "__main__":
    main()
EOF

chmod +x app.py

# Create systemd service for the processor
cat > /etc/systemd/system/geojson-processor.service << 'EOF'
[Unit]
Description=GeoJSON Processor Service
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/geojson-processor
ExecStart=/usr/bin/python3 /opt/geojson-processor/app.py
Restart=always
RestartSec=10
Environment=AWS_DEFAULT_REGION=us-east-1

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable geojson-processor
systemctl start geojson-processor

# Install and configure CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/syslog",
                        "log_group_name": "/aws/ec2/asterra-private",
                        "log_stream_name": "{instance_id}-syslog"
                    },
                    {
                        "file_path": "/var/log/geojson-processor.log",
                        "log_group_name": "/aws/ec2/asterra-private",
                        "log_stream_name": "{instance_id}-geojson-processor"
                    }
                ]
            }
        }
    }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
