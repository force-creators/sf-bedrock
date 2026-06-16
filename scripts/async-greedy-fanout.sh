#!/usr/bin/env bash
set -euo pipefail

ORG_ALIAS="${ORG_ALIAS:-sf-bedrock}"
AGENTS="${AGENTS:-15}"
CONTACT_LIMIT="${CONTACT_LIMIT:-200}"
INITIAL_MAX_THREADS="${INITIAL_MAX_THREADS:-1}"
GREEDY_MAX_THREADS="${GREEDY_MAX_THREADS:-50}"
OBSERVE_SECONDS="${OBSERVE_SECONDS:-10}"
JOB_CLASS="${JOB_CLASS:-HelloWorldAsync}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bedrock-async-fanout.XXXXXX")"
LOG_DIR="$TMP_DIR/logs"
READY_DIR="$TMP_DIR/ready"
mkdir -p "$LOG_DIR" "$READY_DIR"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

write_apex() {
    local file="$1"
    shift
    printf '%s\n' "$@" > "$file"
}

run_apex() {
    local label="$1"
    local file="$2"
    echo ""
    echo "== $label =="
    sf apex run --target-org "$ORG_ALIAS" --file "$file"
}

query() {
    local label="$1"
    local soql="$2"
    echo ""
    echo "== $label =="
    sf data query --target-org "$ORG_ALIAS" --query "$soql"
}

set_thread_max_file() {
    local file="$1"
    local max_threads="$2"
    write_apex "$file" \
        "Id orgId = UserInfo.getOrganizationId();" \
        "List<Thread_Settings__c> existing = [" \
        "    SELECT Id" \
        "    FROM Thread_Settings__c" \
        "    WHERE SetupOwnerId = :orgId" \
        "    LIMIT 1" \
        "];" \
        "Thread_Settings__c settings = existing.isEmpty()" \
        "    ? new Thread_Settings__c(SetupOwnerId = orgId)" \
        "    : new Thread_Settings__c(Id = existing[0].Id);" \
        "settings.Max_Threads__c = $max_threads;" \
        "upsert settings;"
}

echo "Async greedy fan-out validation"
echo "Org alias: $ORG_ALIAS"
echo "Agents: $AGENTS"
echo "Job class: $JOB_CLASS"
echo "Contact limit per enqueue: $CONTACT_LIMIT"
echo "Initial Thread_Settings__c.Max_Threads__c: $INITIAL_MAX_THREADS"
echo "Greedy Thread_Settings__c.Max_Threads__c: $GREEDY_MAX_THREADS"
echo ""
echo "For the clearest signal, configure Async_Job__mdt for $JOB_CLASS with Batch_Size__c = 1 before running."

RUN_START="$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")"

RESET_APEX="$TMP_DIR/reset.apex"
SET_INITIAL_APEX="$TMP_DIR/set-initial-thread-max.apex"
SET_GREEDY_APEX="$TMP_DIR/set-greedy-thread-max.apex"
ENQUEUE_APEX="$TMP_DIR/enqueue.apex"
TRIGGER_APEX="$TMP_DIR/trigger-greedy.apex"

write_apex "$RESET_APEX" \
    "delete [SELECT Id FROM Async__c];" \
    "delete [SELECT Id FROM Async_Archive__c];" \
    "delete [SELECT Id FROM Thread__c];"

set_thread_max_file "$SET_INITIAL_APEX" "$INITIAL_MAX_THREADS"
set_thread_max_file "$SET_GREEDY_APEX" "$GREEDY_MAX_THREADS"

write_apex "$ENQUEUE_APEX" \
    "Async.enqueue($JOB_CLASS.class, [SELECT Id FROM Contact LIMIT $CONTACT_LIMIT]);"
cp "$ENQUEUE_APEX" "$TRIGGER_APEX"

run_apex "Reset Async/Thread data" "$RESET_APEX"
run_apex "Set Thread max to $INITIAL_MAX_THREADS" "$SET_INITIAL_APEX"

query "Thread settings before fan-out" \
    "SELECT Id, Name, SetupOwnerId, Max_Threads__c FROM Thread_Settings__c LIMIT 20"

echo ""
echo "== Launching $AGENTS concurrent enqueue transactions =="
START_FILE="$TMP_DIR/start"
PIDS=()
for i in $(seq 1 "$AGENTS"); do
    (
        touch "$READY_DIR/$i"
        while [[ ! -f "$START_FILE" ]]; do
            sleep 0.02
        done
        sf apex run --target-org "$ORG_ALIAS" --file "$ENQUEUE_APEX" > "$LOG_DIR/agent-$i.log" 2>&1
    ) &
    PIDS+=("$!")
done

while [[ "$(find "$READY_DIR" -type f | wc -l | tr -d ' ')" != "$AGENTS" ]]; do
    sleep 0.05
done

touch "$START_FILE"

FAILED=0
for i in "${!PIDS[@]}"; do
    agent_number=$((i + 1))
    if ! wait "${PIDS[$i]}"; then
        echo "Agent $agent_number failed. Log: $LOG_DIR/agent-$agent_number.log"
        FAILED=1
        continue
    fi
    if ! grep -q "Executed successfully" "$LOG_DIR/agent-$agent_number.log"; then
        echo "Agent $agent_number did not report successful execution. Log: $LOG_DIR/agent-$agent_number.log"
        FAILED=1
    fi
done

if [[ "$FAILED" != "0" ]]; then
    echo ""
    echo "One or more enqueue agents failed. Leaving org state intact for inspection."
    exit 1
fi

query "Async status after concurrent enqueue with max=$INITIAL_MAX_THREADS" \
    "SELECT Status__c status, COUNT(Id) total FROM Async__c GROUP BY Status__c ORDER BY Status__c"
query "Thread status after concurrent enqueue with max=$INITIAL_MAX_THREADS" \
    "SELECT Status__c status, COUNT(Id) total FROM Thread__c GROUP BY Status__c ORDER BY Status__c"
query "Thread rows after concurrent enqueue" \
    "SELECT Id, Name, Status__c, CreatedDate, LastModifiedDate FROM Thread__c ORDER BY CreatedDate ASC LIMIT 50"

run_apex "Set Thread max to $GREEDY_MAX_THREADS" "$SET_GREEDY_APEX"
run_apex "Send one more enqueue to trigger greedy slot filling" "$TRIGGER_APEX"

query "Async status immediately after greedy trigger" \
    "SELECT Status__c status, COUNT(Id) total FROM Async__c GROUP BY Status__c ORDER BY Status__c"
query "Thread status immediately after greedy trigger" \
    "SELECT Status__c status, COUNT(Id) total FROM Thread__c GROUP BY Status__c ORDER BY Status__c"
query "Recent platform Queueable jobs immediately after greedy trigger" \
    "SELECT Status, ApexClass.Name className, COUNT(Id) total FROM AsyncApexJob WHERE CreatedDate >= $RUN_START AND ApexClass.Name IN ('ThreadRunner', '$JOB_CLASS') GROUP BY Status, ApexClass.Name ORDER BY ApexClass.Name, Status"

echo ""
echo "== Waiting $OBSERVE_SECONDS seconds for the backlog to drain =="
sleep "$OBSERVE_SECONDS"

query "Async status after observe window" \
    "SELECT Status__c status, COUNT(Id) total FROM Async__c GROUP BY Status__c ORDER BY Status__c"
query "Thread status after observe window" \
    "SELECT Status__c status, COUNT(Id) total FROM Thread__c GROUP BY Status__c ORDER BY Status__c"
query "Recent platform Queueable jobs after observe window" \
    "SELECT Status, ApexClass.Name className, COUNT(Id) total FROM AsyncApexJob WHERE CreatedDate >= $RUN_START AND ApexClass.Name IN ('ThreadRunner', '$JOB_CLASS') GROUP BY Status, ApexClass.Name ORDER BY ApexClass.Name, Status"
query "Errors after observe window" \
    "SELECT Id, Name, Apex__c, Status__c, Error_Message__c FROM Async__c WHERE Status__c = 'Error' LIMIT 20"

echo ""
echo "Done. Expected shape: initial max=1 leaves one running thread and pending backlog; raising max and sending one more enqueue should start many queued thread runners in the next synchronous transaction."
