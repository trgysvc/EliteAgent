#!/bin/zsh

# 🛸 EliteAgent Marathon Runner v2.0
# "Native Sovereign" Validation Suite

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOG_FILE="marathon_results_$(date +%Y%m%d_%H%M%S).log"

echo "${BLUE}🛸 Starting EliteAgent Marathon Validation...${NC}"
echo "Logging to: $LOG_FILE"

# 1. Logic Validation (Unit/Integration Tests)
echo "\n${YELLOW}Phase 1: Logic & Orchestration Validation (Mocks)${NC}"
if swift test --filter EliteMarathonTests > "$LOG_FILE" 2>&1; then
    echo "${GREEN}✅ Phase 1 Passed: Orchestration logic is sound.${NC}"
else
    echo "${RED}❌ Phase 1 Failed! Check $LOG_FILE for details.${NC}"
    # We don't exit here, so we can see the failures in the log
fi

# 2. Results Summary
echo "\n${BLUE}🏁 Marathon Complete!${NC}"
echo "Summary:"
PASSED=$(grep "passed" "$LOG_FILE" | wc -l)
FAILED=$(grep "failed" "$LOG_FILE" | wc -l)
echo "${GREEN}Tests Passed: $PASSED${NC}"
if [ "$FAILED" -gt 0 ]; then
    echo "${RED}Tests Failed: $FAILED${NC}"
else
    echo "${GREEN}Tests Failed: 0${NC}"
fi
echo "Detailed log saved to: $LOG_FILE"
