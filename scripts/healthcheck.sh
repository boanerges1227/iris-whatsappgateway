#!/usr/bin/env bash
# Check the namespace and Demo Production; login availability alone does not imply health.
set -euo pipefail
output=$(iris session IRIS -U WHATSAPP <<'IRIS'
write !,"WHATSAPP_HEALTH=",##class(WhatsApp.Util.Setup).Healthy(),!
halt
IRIS
)
echo "$output" | grep -Eq '^WHATSAPP_HEALTH=1[[:space:]]*$'
