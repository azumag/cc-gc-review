# Debug Summary: Work Summaries Are Empty

## Root Cause Analysis

The work summaries in the notification system are empty due to **two critical issues** in the `extract_last_assistant_message` function in `/Users/azumag/work/cc-gc-review/hooks/shared-utils.sh`:

### Issue 1: Incorrect jq Filter for JSONL Format

The function uses jq filters that assume the transcript file is a single JSON array:
```bash
# This FAILS because JSONL files contain individual JSON objects per line
jq -r 'map(select(.type == "assistant")) | ...' transcript.jsonl
```

But JSONL files contain one JSON object per line, not an array. The correct approach is:
```bash
# This WORKS for JSONL format
jq -r 'select(.type == "assistant") | ...' transcript.jsonl
```

### Issue 2: Missing Text Content Filter

The function attempts to get content from the **last** assistant message, but that message might only contain `tool_use` content, not `text` content. It should look for the last assistant message **with text content**.

## Test Results

### Current Function Behavior
- **full_content=true**: ❌ FAILS - "Error: Failed to parse transcript JSON"
- **full_content=false**: ❌ FAILS - "Error: Failed to parse transcript JSON"  
- **line_limit > 0**: ✅ WORKS - Gets last line from recent messages

### What get_work_summary() Returns
- **Current**: Error message string (151 characters)
- **Should Return**: Actual work summary (2000+ characters of meaningful content)

### Actual Content Available
The transcript file contains substantial content from the last assistant message with text:
- **Location**: `/Users/azumag/.claude/projects/-Users-azumag-work-cc-gc-review/11641804-e30a-4198-aacd-3a782a79c64a.jsonl`
- **Size**: 3.0M with 828 lines
- **Last text content**: 2000+ character comprehensive test summary

## Technical Details

### Working Content Extraction
```bash
# Get last assistant message with text content
cat transcript.jsonl | jq -r '
    select(.type == "assistant" and (.message.content[]? | select(.type == "text"))) | 
    .uuid
' | tail -1

# Get all text content from that message
cat transcript.jsonl | jq -r --arg uuid "$uuid" '
    select(.type == "assistant" and .uuid == $uuid) | 
    .message.content[] | 
    select(.type == "text") | 
    .text
'
```

### Message Structure Analysis
- **Last assistant message**: Contains only `tool_use` content
- **Last assistant message with text**: Contains comprehensive work summary
- **Content types found**: `text`, `thinking`, `tool_use`

## Impact on Notification System

1. **Discord Notifications**: Get error message instead of work summary
2. **Task Titles**: Extracted from error message, resulting in generic "Task Completed"
3. **Work Context**: Lost - no actual work description in notifications

## Solution Required

Fix the `extract_last_assistant_message` function in `/Users/azumag/work/cc-gc-review/hooks/shared-utils.sh` to:

1. **Use correct jq filters** for JSONL format (individual JSON objects per line)
2. **Find last assistant message with text content** instead of just last assistant message
3. **Handle edge cases** where no text content exists

The notification system's transcript path detection is working correctly - the issue is purely in the content extraction logic.