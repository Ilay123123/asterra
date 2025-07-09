# scripts/windows-init.ps1
<powershell>
# Enable RDP
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -Value 0

# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install essential tools
choco install -y git
choco install -y docker-desktop
choco install -y vscode
choco install -y python3
choco install -y awscli
choco install -y terraform

# Install QGIS (GIS development workspace)
choco install -y qgis

# Install PostgreSQL client tools
choco install -y postgresql

# Configure Windows Firewall for RDP
New-NetFirewallRule -DisplayName "Allow RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow

# Install CloudWatch agent
$cwagent = "https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi"
Invoke-WebRequest -Uri $cwagent -OutFile "C:\amazon-cloudwatch-agent.msi"
Start-Process msiexec.exe -Wait -ArgumentList '/i C:\amazon-cloudwatch-agent.msi /quiet'

# Create CloudWatch config
$cwconfig = @"
{
    "logs": {
        "logs_collected": {
            "windows_events": {
                "collect_list": [
                    {
                        "event_name": "System",
                        "event_levels": ["ERROR", "WARNING"],
                        "log_group_name": "/aws/ec2/asterra-windows",
                        "log_stream_name": "{instance_id}-system"
                    }
                ]
            }
        }
    }
}
"@

$cwconfig | Out-File -FilePath "C:\Program Files\Amazon\AmazonCloudWatchAgent\config.json" -Encoding UTF8

# Start CloudWatch agent
& "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:"C:\Program Files\Amazon\AmazonCloudWatchAgent\config.json" -s

# Create development folder
New-Item -Path "C:\Development" -ItemType Directory -Force

# Set up development environment message
$message = @"
ASTERRA Development Workspace Setup Complete!

Installed tools:
- Git
- Docker Desktop
- Visual Studio Code
- Python 3
- AWS CLI
- Terraform
- QGIS (GIS Development)
- PostgreSQL Client

Development folder created at: C:\Development

To connect via RDP, use the public IP of this instance.
"@

$message | Out-File -FilePath "C:\Development\README.txt" -Encoding UTF8

Write-Host $message
</powershell>