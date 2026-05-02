#!/bin/bash
export MLX_METAL_PATH="/Users/trgysvc/Developer/EliteAgent/Sources/EliteAgentCore/Resources/"
REPORT_FILE="full_audit_report.md"
echo "# 🛡 EliteAgent Full Autonomous Audit Report" > $REPORT_FILE
echo "Generated: $(date)" >> $REPORT_FILE
echo "System: $(uname -a)" >> $REPORT_FILE
echo "---" >> $REPORT_FILE

SCENARIOS_JSON="tests/scenarios.json"

# Function to run a scenario
run_scenario() {
    local ID=$1
    local PROMPT=$2
    echo "## Scenario: $ID" >> $REPORT_FILE
    echo "**Prompt:** $PROMPT" >> $REPORT_FILE
    
    # Start log capture in background
    LOG_START=$(date "+%Y-%m-%d %H:%M:%S")
    
    echo "Executing..."
    OUTPUT=$(swift run elite --cpu-only "$PROMPT" 2>&1)
    EXIT_CODE=$?
    
    LOG_END=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Extract logs
    LOG_CONTENT=$(log show --predicate "subsystem == 'app.eliteagent.titan' || subsystem == 'com.eliteagent.service'" --start "$LOG_START" --end "$LOG_END" 2>/dev/null)
    
    echo "### Result" >> $REPORT_FILE
    if [ $EXIT_CODE -eq 0 ]; then
        echo "Status: 🟢 PASSED" >> $REPORT_FILE
    else
        echo "Status: 🔴 FAILED (Exit Code: $EXIT_CODE)" >> $REPORT_FILE
    fi
    
    echo "#### Output" >> $REPORT_FILE
    echo '```' >> $REPORT_FILE
    echo "$OUTPUT" >> $REPORT_FILE
    echo '```' >> $REPORT_FILE
    
    echo "#### System Logs" >> $REPORT_FILE
    echo '```' >> $REPORT_FILE
    if [ -z "$LOG_CONTENT" ]; then
        echo "No system logs captured for this period." >> $REPORT_FILE
    else
        echo "$LOG_CONTENT" >> $REPORT_FILE
    fi
    echo '```' >> $REPORT_FILE
    echo "---" >> $REPORT_FILE
}

# Iterate over scenarios
while read -r scenario; do
    ID=$(echo "$scenario" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
    PROMPT=$(echo "$scenario" | python3 -c "import sys, json; print(json.load(sys.stdin)['prompt'])")
    run_scenario "$ID" "$PROMPT"
done < <(python3 -c "import sys, json; data = json.load(open('$SCENARIOS_JSON')); [print(json.dumps(s)) for s in data['scenarios']]")

echo "🏁 Audit Complete. Report saved to $REPORT_FILE"
