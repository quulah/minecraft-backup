#!/usr/bin/env bash

# Helper functions

TEST_DIR="test"
TEST_TMP="$TEST_DIR/tmp"
SCREEN_TMP="tmp-screen"
setUp () {
  rm -rf "$TEST_TMP"
  mkdir -p "$TEST_TMP/server/world"
  mkdir -p "$TEST_TMP/backups"
  echo "file1" > "$TEST_TMP/server/world/file1.txt"
  echo "file2" > "$TEST_TMP/server/world/file2.txt"
  echo "file3" > "$TEST_TMP/server/world/file3.txt"

  screen -dmS "$SCREEN_TMP" bash
  screen -S "$SCREEN_TMP" -X stuff "cat > $TEST_TMP/screen-output\n"
  tmux new-session -d -s "$SCREEN_TMP"
  tmux send-keys -t "$SCREEN_TMP" "cat > $TEST_TMP/tmux-output" ENTER
  sleep 0.5
}

tearDown () {
  screen -S "$SCREEN_TMP" -X quit >/dev/null 2>&1 || true
  tmux kill-session -t "$SCREEN_TMP" >/dev/null 2>&1 || true
}

assert-equals-directory () {
  if [ -d "$1" ]; then
    for FILE in "$1"/*; do
      assert-equals-directory "$FILE" "$2/${FILE##$1}"
    done
  else
    assertEquals "$(cat "$1")" "$(cat "$2")"
  fi
}

check-backup () {
  BACKUP_ARCHIVE="$1"
  mkdir -p "$TEST_TMP/restored"
  tar --extract --file "$TEST_TMP/backups/$BACKUP_ARCHIVE" --directory "$TEST_TMP/restored"
  assert-equals-directory "$TEST_TMP/server/world" "$TEST_TMP/restored"
  rm -rf "$TEST_TMP/restored"
}

# Tests

test-backup-defaults () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-backup "$TIMESTAMP.tar.gz"
}

test-backup-no-compression () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -a "" -e "" -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-backup "$TIMESTAMP.tar" 
}

test-backup-max-compression () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -a "xz" -e "xz" -l 9e -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-backup "$TIMESTAMP.tar.xz" 
}

test-chat-messages () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -c -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  EXPECTED_OUTPUT="$(head -n-1 "$TEST_DIR/data/test-chat-messages.txt")"
  ACTUAL_OUTPUT="$(head -n-1 "$TEST_TMP/screen-output")"
  assertEquals "$EXPECTED_OUTPUT" "$ACTUAL_OUTPUT"
}

test-chat-prefix () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -p "Hello" -c -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  EXPECTED_OUTPUT="$(head -n-1 "$TEST_DIR/data/test-chat-prefix.txt")"
  ACTUAL_OUTPUT="$(head -n-1 "$TEST_TMP/screen-output")"
  assertEquals "$EXPECTED_OUTPUT" "$ACTUAL_OUTPUT"
}

test-check-help () {
  HELP_HEADER="$(./backup.sh -h)"
  assertEquals "Minecraft Backup" "$(head -n1 <<< "$HELP_HEADER")"
}

test-missing-options () {
  OUTPUT="$(./backup.sh 2>&1)"
  EXIT_CODE="$?"
  assertEquals 1 "$EXIT_CODE"
  assertContains "$OUTPUT" "Minecraft screen name not specified"
  assertContains "$OUTPUT" "Server world not specified"
  assertContains "$OUTPUT" "Backup directory not specified"
}

test-missing-options-suppress-warnings () {
  OUTPUT="$(./backup.sh -q 2>&1)"
  EXIT_CODE="$?"
  assertEquals 1 "$EXIT_CODE"
  assertNotContains "$OUTPUT" "Minecraft screen name not specified"
}

test-empty-world-warning () {
  mkdir -p "$TEST_TMP/server/empty-world"
  OUTPUT="$(./backup.sh -v -i "$TEST_TMP/server/empty-world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP" 2>&1)"
  assertContains "$OUTPUT" "Backup was not saved!"
}

test-block-size-warning () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  OUTPUT="$(./backup.sh -m 10 -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP" 2>&1)"
  EXIT_CODE="$?"
  assertContains "$OUTPUT" "is smaller than TOTAL_BLOCK_SIZE"
}

test-screen-interface () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  EXPECTED_CONTENTS=$(echo -e "save-off\nsave-on\nsave-all") 
  SCREEN_CONTENTS="$(cat "$TEST_TMP/screen-output")"
  assertEquals "$SCREEN_CONTENTS" "$EXPECTED_CONTENTS" 
}

test-tmux-interface () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -w tmux -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  EXPECTED_CONTENTS=$(echo -e "save-off\nsave-on\nsave-all") 
  SCREEN_CONTENTS="$(cat "$TEST_TMP/tmux-output")"
  assertEquals "$SCREEN_CONTENTS" "$EXPECTED_CONTENTS" 
}

test-sequential-delete () {
  for i in $(seq 0 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i hour")"
    ./backup.sh -d "sequential" -m 10 -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  done
  for i in $(seq 90 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i hour")"
    check-backup "$TIMESTAMP.tar.gz"
  done
}

test-thinning-delete () {
  for i in $(seq 0 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i hour")"
    ./backup.sh -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  done
  EXPECTED_TIMESTAMPS=(
    # Weekly

    # Daily (30)
    "2021-01-01_00-00-00"
    "2021-01-02_00-00-00"
    "2021-01-03_00-00-00"

    # Hourly (24)
    "2021-01-03_12-00-00"
    "2021-01-03_13-00-00"
    "2021-01-03_14-00-00"
    "2021-01-03_15-00-00"
    "2021-01-03_16-00-00"
    "2021-01-03_17-00-00"
    "2021-01-03_18-00-00"
    "2021-01-03_19-00-00"
    "2021-01-03_20-00-00"
    "2021-01-04_09-00-00"
    "2021-01-04_10-00-00"
    "2021-01-04_11-00-00"

    # Sub-hourly (16)
    "2021-01-04_12-00-00"
    "2021-01-04_13-00-00"
    "2021-01-04_14-00-00"
    "2021-01-04_15-00-00"
    "2021-01-04_16-00-00"
    "2021-01-04_17-00-00"
    "2021-01-04_18-00-00"
    "2021-01-04_19-00-00"
    "2021-01-04_20-00-00"
    "2021-01-04_21-00-00"
    "2021-01-04_22-00-00"
    "2021-01-04_23-00-00"
    "2021-01-05_00-00-00"
    "2021-01-05_01-00-00"
    "2021-01-05_02-00-00"
    "2021-01-05_03-00-00"
  )
  for TIMESTAMP in "${EXPECTED_TIMESTAMPS[@]}"; do
    check-backup "$TIMESTAMP.tar.gz"
  done
}

test-thinning-delete-long () {
  for i in $(seq 0 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i day")"
    OUTPUT="$(./backup.sh -v -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP")"
  done
  EXPECTED_TIMESTAMPS=(
    # Weekly
    "2021-01-04_00-00-00"
    "2021-01-11_00-00-00"
    "2021-01-25_00-00-00"
    "2021-01-25_00-00-00"

    # Daily (30)
    "2021-01-31_00-00-00"
    "2021-03-01_00-00-00"

    # Hourly (24)
    "2021-03-02_00-00-00"
    "2021-03-25_00-00-00"

    # Sub-hourly (16)
    "2021-03-26_00-00-00"
    "2021-04-10_00-00-00"
  )
  assertContains "$OUTPUT" "promoted to next block"
  for TIMESTAMP in "${EXPECTED_TIMESTAMPS[@]}"; do
    check-backup "$TIMESTAMP.tar.gz"
  done
}

# shellcheck disable=SC1091
. test/shunit2/shunit2