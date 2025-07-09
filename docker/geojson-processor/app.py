#!/usr/bin/env python3
"""
ASTERRA GeoJSON Processor
Processes GeoJSON files from S3 and stores them in PostgreSQL with PostGIS
"""

import os
import json
import logging
import boto3
import geopandas as gpd
from flask import Flask, request, jsonify
from sqlalchemy import create_engine, text
import psycopg2
from datetime import datetime
import uuid

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

class GeoJSONProcessor:
    def __init__(self):
        self.s3_client = boto3.client('s3')
        self.secrets_client = boto3.client('secretsmanager')
        self.s3_bucket = os.getenv('S3_BUCKET')
        self.secret_arn = os.getenv('DB_SECRET_ARN')
        self.db_engine = None

    def get_db_connection(self):
        """Get database connection from AWS Secrets Manager"""
        if self.db_engine:
            return self.db_engine

        try:
            response = self.secrets_client.get_secret_value(SecretId=self.secret_arn)
            secret = json.loads(response['SecretString'])

            connection_string = (
                f"postgresql://{secret['username']}:{secret['password']}"
                f"@{secret['host']}:{secret['port']}/{secret['dbname']}"
            )

            self.db_engine = create_engine(connection_string)

            # Ensure PostGIS extension
            with self.db_engine.connect() as conn:
                conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis;"))
                conn.commit()

            logger.info("Database connection established")
            return self.db_engine

        except Exception as e:
            logger.error(f"Failed to get database connection: {e}")
            raise

    def validate_geojson(self, geojson_data):
        """Validate GeoJSON format"""
        try:
            if not isinstance(geojson_data, dict):
                return False, "GeoJSON must be a JSON object"

            if geojson_data.get('type') != 'FeatureCollection':
                return False, "Must be a FeatureCollection"

            if 'features' not in geojson_data:
                return False, "No features found"

            features = geojson_data['features']
            if not isinstance(features, list):
                return False, "Features must be a list"

            if len(features) == 0:
                return False, "No features in collection"

            # Validate each feature
            for i, feature in enumerate(features):
                if not isinstance(feature, dict):
                    return False, f"Feature {i} is not an object"

                if feature.get('type') != 'Feature':
                    return False, f"Feature {i} type is not 'Feature'"

                if 'geometry' not in feature:
                    return False, f"Feature {i} missing geometry"

            return True, "Valid GeoJSON"

        except Exception as e:
            return False, f"Validation error: {e}"

    def process_geojson_file(self, bucket, key):
        """Process a single GeoJSON file"""
        logger.info(f"Processing file: s3://{bucket}/{key}")

        try:
            # Download file from S3
            response = self.s3_client.get_object(Bucket=bucket, Key=key)
            file_content = response['Body'].read().decode('utf-8')

            # Parse JSON
            geojson_data = json.loads(file_content)

            # Validate GeoJSON
            is_valid, message = self.validate_geojson(geojson_data)
            if not is_valid:
                logger.error(f"Invalid GeoJSON: {message}")
                return False, message

            # Read with GeoPandas
            gdf = gpd.read_file(f"s3://{bucket}/{key}")

            # Add metadata columns
            gdf['file_source'] = key
            gdf['processed_at'] = datetime.utcnow()
            gdf['processing_id'] = str(uuid.uuid4())

            # Get database connection
            engine = self.get_db_connection()

            # Create table name from file path
            table_name = f"geojson_{key.replace('/', '_').replace('.', '_').replace('-', '_')}"
            table_name = table_name.lower()[:63]  # PostgreSQL table name limit

            # Store in database
            gdf.to_postgis(
                table_name,
                engine,
                if_exists='replace',
                index=False,
                chunksize=1000
            )

            logger.info(f"Successfully processed {len(gdf)} features into table '{table_name}'")
            return True, f"Processed {len(gdf)} features"

        except json.JSONDecodeError as e:
            error_msg = f"Invalid JSON format: {e}"
            logger.error(error_msg)
            return False, error_msg
        except Exception as e:
            error_msg = f"Error processing file: {e}"
            logger.error(error_msg)
            return False, error_msg

# Global processor instance
processor = GeoJSONProcessor()

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'geojson-processor'
    })

@app.route('/process', methods=['POST'])
def process_file():
    """Process a GeoJSON file from S3"""
    try:
        data = request.get_json()
        bucket = data.get('bucket', processor.s3_bucket)
        key = data.get('key')

        if not key:
            return jsonify({'error': 'Missing key parameter'}), 400

        success, message = processor.process_geojson_file(bucket, key)

        if success:
            return jsonify({
                'status': 'success',
                'message': message,
                'file': f"s3://{bucket}/{key}"
            })
        else:
            return jsonify({
                'status': 'error',
                'message': message,
                'file': f"s3://{bucket}/{key}"
            }), 400

    except Exception as e:
        logger.error(f"Error in process endpoint: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/status')
def status():
    """Service status endpoint"""
    try:
        # Test database connection
        engine = processor.get_db_connection()
        with engine.connect() as conn:
            result = conn.execute(text("SELECT version();"))
            db_version = result.scalar()

        return jsonify({
            'status': 'operational',
            'database': 'connected',
            'db_version': db_version,
            's3_bucket': processor.s3_bucket,
            'timestamp': datetime.utcnow().isoformat()
        })
    except Exception as e:
        return jsonify({
            'status': 'degraded',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }), 503

if __name__ == '__main__':
    # For production, use gunicorn instead
    app.run(host='0.0.0.0', port=8080, debug=False)
